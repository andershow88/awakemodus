import AppKit
import Combine
import CoreGraphics
import IOKit.pwr_mgt

enum SessionDuration: Int, CaseIterable, Identifiable {
    case unlimited = 0, halfHour = 1800, hour = 3600, twoHours = 7200
    var id: Int { rawValue }
    var seconds: TimeInterval? { self == .unlimited ? nil : Double(rawValue) }
    var title: String {
        switch self {
        case .unlimited: return "Unbegrenzt"
        case .halfHour: return "30 Minuten"
        case .hour: return "1 Stunde"
        case .twoHours: return "2 Stunden"
        }
    }
}

enum SessionState { case idle, running, paused, finished }

struct PulseResult {
    var succeeded = true
    var keyboardAvailable = true
}

protocol PowerActivityManaging: AnyObject {
    func begin() throws
    func pulse(keyboard: Bool) -> PulseResult
    func end()
}

struct PowerError: LocalizedError {
    let code: IOReturn
    var errorDescription: String? {
        "macOS konnte den Wachmodus nicht aktivieren (Code \(code)). Bitte erneut versuchen."
    }
}

final class SystemPowerActivity: PowerActivityManaging {
    private var assertions: [IOPMAssertionID] = []
    private var userActivityID = IOPMAssertionID(0)
    private var activity: NSObjectProtocol?

    func begin() throws {
        guard assertions.isEmpty else { return }
        for type in [kIOPMAssertionTypePreventUserIdleSystemSleep, kIOPMAssertionTypePreventUserIdleDisplaySleep] {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                   "WachModus · aktive Sitzung" as CFString, &id)
            guard result == kIOReturnSuccess else {
                end()
                throw PowerError(code: result)
            }
            assertions.append(id)
        }
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                        reason: "WachModus · aktive Sitzung")
    }

    func pulse(keyboard: Bool) -> PulseResult {
        // Reuse the returned ID; macOS can replace it when the previous assertion expires.
        let result = IOPMAssertionDeclareUserActivity("WachModus · Aktivität" as CFString,
                                                     kIOPMUserActiveLocal, &userActivityID)
        var keyboardAvailable = true
        if keyboard {
            keyboardAvailable = CGPreflightPostEventAccess()
            if keyboardAvailable {
                let source = CGEventSource(stateID: .hidSystemState)
                if let down = CGEvent(keyboardEventSource: source, virtualKey: 0x71, keyDown: true),
                   let up = CGEvent(keyboardEventSource: source, virtualKey: 0x71, keyDown: false) {
                    down.post(tap: .cghidEventTap)
                    up.post(tap: .cghidEventTap)
                } else {
                    keyboardAvailable = false
                }
            }
        }
        return PulseResult(succeeded: result == kIOReturnSuccess, keyboardAvailable: keyboardAvailable)
    }

    func end() {
        for id in assertions { IOPMAssertionRelease(id) }
        assertions.removeAll()
        if userActivityID != 0 {
            IOPMAssertionRelease(userActivityID)
            userActivityID = 0
        }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    deinit { end() }
}

private enum SessionClock {
    static let origin = ContinuousClock.now
    static func now() -> TimeInterval {
        let components = origin.duration(to: ContinuousClock.now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

final class KeepAwake: ObservableObject {
    static let pulseInterval: TimeInterval = 25
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval?
    @Published private(set) var nextPulse = 0
    @Published private(set) var pulseSucceeded = true
    @Published private(set) var keyboardAvailable = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var duration: SessionDuration
    @Published var keyboardPulse: Bool {
        didSet {
            preferences?.set(keyboardPulse, forKey: "keyboardPulse")
            keyboardAvailable = !keyboardPulse || CGPreflightPostEventAccess()
        }
    }
    var onChange: (() -> Void)?

    private let power: PowerActivityManaging
    private let clock: () -> TimeInterval
    private let preferences: UserDefaults?
    private let automaticTimer: Bool
    private var timer: Timer?
    private var accumulated: TimeInterval = 0
    private var startedAt: TimeInterval = 0
    private var lastPulseAt: TimeInterval?
    private var deadlineElapsed: TimeInterval?

    init(power: PowerActivityManaging = SystemPowerActivity(), preferences: UserDefaults? = .standard,
         automaticTimer: Bool = true, clock: (() -> TimeInterval)? = nil) {
        self.power = power
        self.preferences = preferences
        self.automaticTimer = automaticTimer
        self.clock = clock ?? SessionClock.now
        duration = SessionDuration(rawValue: preferences?.integer(forKey: "sessionDuration") ?? 0) ?? .unlimited
        keyboardPulse = preferences?.bool(forKey: "keyboardPulse") ?? false
        remaining = duration.seconds
    }

    var isRunning: Bool { state == .running }
    var elapsedText: String { Self.formatTime(elapsed) }
    var remainingText: String { remaining.map(Self.formatTime) ?? "Unbegrenzt" }
    var progress: Double {
        guard let total = duration.seconds, let remaining else { return 1 }
        return min(1, max(0, 1 - remaining / total))
    }
    var stateTitle: String {
        switch state {
        case .idle: return "Bereit"
        case .running: return "Wachmodus aktiv"
        case .paused: return "Pausiert"
        case .finished: return "Sitzung beendet"
        }
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        do {
            try power.begin()
        } catch {
            power.end()
            errorMessage = error.localizedDescription
            onChange?()
            return
        }
        if state != .paused {
            accumulated = 0
            elapsed = 0
            deadlineElapsed = duration.seconds
            remaining = duration.seconds
        }
        errorMessage = nil
        startedAt = clock()
        state = .running
        lastPulseAt = nil
        tick()
        if automaticTimer {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.15
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func pause() {
        guard isRunning else { return }
        tick()
        guard isRunning else { return }
        accumulated = elapsed
        stopActivity()
        state = .paused
        onChange?()
    }

    func reset() {
        stopActivity()
        accumulated = 0
        elapsed = 0
        remaining = duration.seconds
        deadlineElapsed = duration.seconds
        errorMessage = nil
        state = .idle
        onChange?()
    }

    func selectDuration(_ value: SessionDuration) {
        guard value != duration else { return }
        if isRunning { tick() }
        duration = value
        preferences?.set(value.rawValue, forKey: "sessionDuration")
        // A new duration counts from this selection; pausing freezes the countdown.
        remaining = value.seconds
        deadlineElapsed = value.seconds.map { elapsed + $0 }
        onChange?()
    }

    func tick() {
        guard isRunning else { return }
        let now = clock()
        elapsed = accumulated + max(0, now - startedAt)
        if let deadlineElapsed {
            remaining = max(0, deadlineElapsed - elapsed)
            if elapsed >= deadlineElapsed {
                elapsed = deadlineElapsed
                accumulated = elapsed
                stopActivity()
                state = .finished
                onChange?()
                return
            }
        }
        if lastPulseAt == nil || now - lastPulseAt! >= Self.pulseInterval {
            let result = power.pulse(keyboard: keyboardPulse)
            pulseSucceeded = result.succeeded
            keyboardAvailable = result.keyboardAvailable
            lastPulseAt = now
        }
        nextPulse = max(0, Int(ceil(Self.pulseInterval - (now - (lastPulseAt ?? now)))))
        onChange?()
    }

    func shutdown() {
        stopActivity()
        state = .idle
        onChange = nil
    }

    private func stopActivity() {
        timer?.invalidate()
        timer = nil
        power.end()
        lastPulseAt = nil
        nextPulse = 0
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", value / 3600, (value % 3600) / 60, value % 60)
    }

    deinit { timer?.invalidate(); power.end() }
}
