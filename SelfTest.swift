import Foundation
import IOKit.pwr_mgt

private final class TestPowerActivity: PowerActivityManaging {
    var starts = 0
    var pulses = 0
    var active = false
    var failStart = false
    var result = PulseResult()
    var keyboardRequested = false
    func begin() throws {
        starts += 1
        if failStart { throw PowerError(code: kIOReturnError) }
        active = true
    }
    func pulse(keyboard: Bool) -> PulseResult {
        pulses += 1
        keyboardRequested = keyboard
        return result
    }
    func end() { active = false }
}

func runSelfTest(system: Bool) -> Bool {
    var failures = 0
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if condition() { print("  OK  \(name)") }
        else { failures += 1; print("FEHLER  \(name)") }
    }
    print("WachModus · Selbsttest")
    var now: TimeInterval = 0
    let power = TestPowerActivity()
    let engine = KeepAwake(power: power, preferences: nil, automaticTimer: false, clock: { now })
    engine.start()
    engine.start()
    check(engine.isRunning && power.active && power.starts == 1, "Mehrfacher Start hält nur eine Aktivität")
    check(power.pulses == 1 && !power.keyboardRequested, "Sofortiger Systemimpuls, F15 standardmäßig aus")
    now = 24
    engine.tick()
    check(power.pulses == 1 && engine.nextPulse == 1, "Impulsintervall wird eingehalten")
    now = 25
    engine.tick()
    check(power.pulses == 2 && engine.elapsed == 25, "Impuls und Laufzeit nach 25 Sekunden")
    engine.selectDuration(.halfHour)
    check(engine.remaining == 1800 && engine.elapsed == 25, "Neue Laufzeit zählt ab Auswahl")
    now = 35
    engine.pause()
    check(engine.state == .paused && !power.active && engine.remaining == 1790, "Pause gibt Systemaktivität frei")
    now = 100
    engine.tick()
    check(engine.elapsed == 35 && engine.remaining == 1790 && power.pulses == 2, "Pause friert Laufzeit und Impulse ein")
    engine.start()
    now = 110
    engine.tick()
    check(engine.elapsed == 45 && engine.remaining == 1780 && power.active, "Fortsetzen zählt Pausenzeit nicht mit")
    let pulsesBeforeExpiry = power.pulses
    now = 1900
    engine.tick()
    check(engine.state == .finished && !power.active && engine.remaining == 0, "Timer beendet Sitzung auch nach verspätetem Tick")
    check(engine.elapsed == 1825 && power.pulses == pulsesBeforeExpiry, "Kein weiterer Impuls nach Ablauf")
    engine.start()
    check(engine.elapsed == 0 && engine.remaining == 1800 && engine.isRunning, "Nach Ablauf beginnt eine neue Sitzung")
    now = 1920
    engine.selectDuration(.unlimited)
    now = 90000
    engine.tick()
    check(engine.isRunning && engine.remaining == nil, "Unbegrenzt entfernt laufenden Timer")
    engine.reset()
    check(engine.state == .idle && !power.active && engine.elapsed == 0, "Zurücksetzen stoppt und leert die Sitzung")
    engine.selectDuration(.hour)
    engine.start()
    now += 10
    engine.pause()
    engine.selectDuration(.twoHours)
    now += 100
    engine.start()
    now += 5
    engine.tick()
    check(engine.remaining == 7195 && engine.elapsed == 15, "Laufzeitwechsel während Pause")
    engine.shutdown()
    check(!power.active && !engine.isRunning, "Beenden räumt auf")

    power.failStart = true
    engine.start()
    check(!engine.isRunning && !power.active && engine.errorMessage != nil, "Systemfehler meldet keinen falschen Aktivstatus")
    power.failStart = false
    power.result = PulseResult(succeeded: false, keyboardAvailable: false)
    engine.keyboardPulse = true
    engine.start()
    check(engine.errorMessage == nil && !engine.pulseSucceeded && !engine.keyboardAvailable && power.keyboardRequested,
          "Erneuter Start und fehlgeschlagener Impuls werden korrekt angezeigt")
    engine.shutdown()

    var temporary: KeepAwake? = KeepAwake(power: power, preferences: nil, automaticTimer: false, clock: { now })
    temporary?.start()
    temporary = nil
    check(!power.active, "Freigabe auch beim Freigeben des Motors")
    check(KeepAwake.formatTime(3661.9) == "01:01:01", "Zeitformat über Stundengrenzen")

    if system {
        func ownedAssertions() -> Int? {
            var raw: Unmanaged<CFDictionary>?
            guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess, let raw else { return nil }
            let all = raw.takeRetainedValue() as NSDictionary
            let entries = all[NSNumber(value: getpid())] as? [[String: Any]] ?? []
            return entries.filter { ($0[kIOPMAssertionNameKey] as? String)?.hasPrefix("WachModus") == true }.count
        }
        let realPower = SystemPowerActivity()
        do {
            try realPower.begin()
            check((ownedAssertions() ?? 0) >= 2, "macOS hält Bildschirm- und System-Assertions")
            check(realPower.pulse(keyboard: false).succeeded, "macOS akzeptiert Nutzersignal")
            let assertionCount = ownedAssertions()
            check(realPower.pulse(keyboard: false).succeeded, "Nutzersignal kann mit gespeicherter ID wiederholt werden")
            check(ownedAssertions() == assertionCount, "Wiederholter Impuls erzeugt keine zusätzliche Assertion")
            realPower.end()
            check(ownedAssertions() == 0, "Nach Stopp bleiben keine WachModus-Assertions zurück")
            realPower.end()
            check(ownedAssertions() == 0, "Wiederholter Stopp bleibt ohne Systemaktivitäten")
        } catch {
            realPower.end()
            check(false, "Systemprüfung: \(error.localizedDescription)")
        }
    }
    print("\(checks - failures)/\(checks) Prüfungen erfolgreich.")
    return failures == 0
}
