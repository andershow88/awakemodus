import AppKit
import SwiftUI

private extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255, blue: Double(rgb & 0xFF) / 255)
    }
    // ChatGBuetti/src/app/globals.css: accent in light and dark appearance.
    static let chatBlue = Color(rgb: 0x2563EB)
    static let chatBlueOnDark = Color(rgb: 0x6EA8FF)
}

struct Dashboard: View {
    @ObservedObject var engine: KeepAwake
    var appearanceOverride: String? = nil
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settingsPresented = false

    private var selectedAppearance: String { appearanceOverride ?? appearance }
    private var dark: Bool { selectedAppearance == "dark" || (selectedAppearance == "system" && systemScheme == .dark) }
    private var ink: Color { Color(rgb: dark ? 0xE9EDF6 : 0x131A2A) }
    private var muted: Color { Color(rgb: dark ? 0xA3B0CC : 0x4B5872) }
    private var accent: Color { dark ? .chatBlueOnDark : .chatBlue }
    private var panel: Color { dark ? Color(rgb: 0x101627) : .white }
    private var border: Color { Color(rgb: dark ? 0x22304F : 0xD2DCEC) }

    var body: some View {
        GeometryReader { geometry in
            // Scale the complete layout from its compact reference size. Lay out
            // in logical points first so the transformed content still fills the
            // window and button hit areas follow the same transform.
            let referenceHeight: CGFloat = engine.errorMessage == nil ? 460 : 520
            let scale = max(0.1, min(geometry.size.width / 540, geometry.size.height / referenceHeight))
            content
                .frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .background(background)
        .foregroundStyle(ink)
        .tint(accent)
        .preferredColorScheme(selectedAppearance == "system" ? nil : (dark ? .dark : .light))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            sessionCard.frame(maxHeight: .infinity)
            durationPicker
            controls
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var background: some View {
        ZStack(alignment: .topTrailing) {
            Color(rgb: dark ? 0x0A0E1A : 0xF4F6FB)
            RadialGradient(colors: [accent.opacity(0.08), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 400)
        }.ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("WachModus").font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Dein Mac. In deinem Rhythmus.").font(.system(size: 11)).foregroundStyle(muted)
            }
            Spacer()
            Text("2.2").font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(muted).padding(.horizontal, 7).padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(muted.opacity(0.25)))
            Button { settingsPresented.toggle() } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15))
                    .frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Einstellungen")
            .accessibilityLabel("Einstellungen")
            .popover(isPresented: $settingsPresented, arrowEdge: .bottom) { settings }
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: stateSymbol)
                            .font(.system(size: engine.isRunning ? 6 : 11, weight: .semibold))
                        Text(engine.stateTitle).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(engine.isRunning ? accent : muted)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background((engine.isRunning ? accent : muted).opacity(0.10), in: Capsule())
                    Text(headline)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .tracking(-0.5).lineSpacing(0).fixedSize(horizontal: false, vertical: true)
                    Text(description)
                        .font(.system(size: 11)).lineSpacing(2)
                        .foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                orbit.frame(width: 128, height: 128)
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            Rectangle().fill(border).frame(height: 1)
            HStack(spacing: 0) {
                metric("AKTIVE ZEIT", value: engine.elapsedText, symbol: "clock")
                Rectangle().fill(border).frame(width: 1, height: 28).padding(.horizontal, 10)
                metric(engine.duration == .unlimited ? "LAUFZEIT" : "VERBLEIBEND", value: engine.remainingText,
                       symbol: engine.duration == .unlimited ? "infinity" : "hourglass")
                Rectangle().fill(border).frame(width: 1, height: 28).padding(.horizontal, 10)
                metric("SYSTEMSIGNAL", value: signalText, symbol: engine.isRunning ? "waveform.path" : "minus")
            }.padding(.horizontal, 16).padding(.vertical, 13)
        }
        .background(panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(border))
        .shadow(color: .black.opacity(dark ? 0.12 : 0.035), radius: 12, x: 0, y: 5)
    }

    private var orbit: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [accent.opacity(engine.isRunning ? 0.14 : 0.03), .clear],
                                         center: .center, startRadius: 10, endRadius: 64))
            Circle().strokeBorder(muted.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [2, 5])).padding(2)
            Circle().strokeBorder(accent.opacity(0.10), lineWidth: 1).padding(14)
            Circle().trim(from: 0, to: engine.duration == .unlimited ? 0.76 : max(0.002, engine.progress))
                .stroke(engine.isRunning ? accent.opacity(0.8) : muted.opacity(0.3), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(14)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: engine.progress)
            Circle().fill(engine.isRunning ? accent : muted)
                .frame(width: 7, height: 7).offset(y: -50)
                .rotationEffect(.degrees(engine.duration == .unlimited ? 274 : 360 * engine.progress))
            VStack(spacing: 8) {
                Image(systemName: engine.state == .finished ? "checkmark" : "cup.and.saucer.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(engine.isRunning ? accent : muted)
                Text(engine.isRunning ? "ALLES WACH" : (engine.state == .finished ? "GESCHAFFT" : "DURCHATMEN"))
                    .font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(muted)
            }
        }.accessibilityHidden(true)
    }

    private func metric(_ label: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(muted)
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(accent)
                Text(value).font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wie lange darf’s sein?").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Timer beginnt ab Auswahl").font(.system(size: 10)).foregroundStyle(muted)
            }
            HStack(spacing: 6) {
                ForEach(SessionDuration.allCases) { duration in
                    Button { engine.selectDuration(duration) } label: {
                        HStack(spacing: 5) {
                            if duration == .unlimited { Image(systemName: "infinity").font(.system(size: 12)) }
                            Text(duration.title).font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .foregroundStyle(engine.duration == duration ? accent : muted)
                        .background(engine.duration == duration ? accent.opacity(0.11) : panel.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(engine.duration == duration ? accent.opacity(0.65) : border))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(engine.duration == duration ? .isSelected : [])
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = engine.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button { engine.toggle() } label: {
                    Label(actionTitle, systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .foregroundStyle(.white)
                        .background(dark ? Color.chatBlue : Color(rgb: 0x1D4ED8), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .help("\(actionTitle) (⌘P)")
                Button { engine.reset() } label: {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .medium))
                        .frame(width: 40, height: 38)
                        .background(panel, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(engine.state == .idle)
                .opacity(engine.state == .idle ? 0.45 : 1)
                .help("Sitzung stoppen und zurücksetzen")
                .accessibilityLabel("Sitzung stoppen und zurücksetzen")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "menubar.rectangle").font(.system(size: 11))
            Text("Auch in der Menüleiste")
            Spacer()
            Text("Schließen beendet den Wachmodus")
        }.font(.system(size: 10)).foregroundStyle(muted)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Einstellungen").font(.system(size: 18, weight: .semibold))
            Picker("Darstellung", selection: $appearance) {
                Text("System").tag("system")
                Text("Hell").tag("light")
                Text("Dunkel").tag("dark")
            }.pickerStyle(.segmented)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Zusätzlicher Tastaturimpuls", isOn: $engine.keyboardPulse).toggleStyle(.switch)
                    .font(.system(size: 13, weight: .medium))
                Text("Sendet alle 25 Sekunden F15 an macOS. Nur bei Bedarf aktivieren: F15 kann belegte Tastenkürzel auslösen.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if engine.keyboardPulse && !engine.keyboardAvailable {
                    Label("Für F15 fehlt die Freigabe.", systemImage: "info.circle").font(.system(size: 12))
                    Button("Bedienungshilfen öffnen") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            Divider()
            Text("Beim Öffnen startet WachModus automatisch. Eine Pause hält auch den Timer an. Beim Schließen werden alle Wachhalte-Signale beendet.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(22).frame(width: 340)
    }

    private var headline: String {
        switch engine.state {
        case .running: return "Dein Mac\nbleibt wach."
        case .paused: return "Zeit für\neine Pause."
        case .idle: return "Bereit, wenn\ndu es bist."
        case .finished: return "Deine Sitzung\nist geschafft."
        }
    }
    private var stateSymbol: String {
        switch engine.state {
        case .running: return "circle.fill"
        case .paused: return "pause.circle"
        case .idle: return "circle"
        case .finished: return "checkmark.circle"
        }
    }
    private var description: String {
        switch engine.state {
        case .running: return "Für lange Downloads, Präsentationen\nund alles, was noch Zeit braucht."
        case .paused: return "Der Wachmodus pausiert.\nMach weiter, wenn es für dich passt."
        case .idle: return "Wähle deine Laufzeit und starte\nentspannt in die nächste Sitzung."
        case .finished: return "Der Timer ist abgelaufen.\nDein Mac darf wieder zur Ruhe kommen."
        }
    }
    private var actionTitle: String {
        if engine.isRunning { return "Pausieren" }
        return engine.state == .paused ? "Fortsetzen" : "Wachmodus starten"
    }
    private var signalText: String {
        guard engine.isRunning else { return "Inaktiv" }
        guard engine.pulseSucceeded else { return "Nicht gesendet" }
        return engine.nextPulse == Int(KeepAwake.pulseInterval) ? "Gerade eben" : "in \(engine.nextPulse) s"
    }
}
