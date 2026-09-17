import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: NSWindow!
    private let engine = KeepAwake()
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var timeItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var sessionToggleItem: NSMenuItem!
    private var durationItems: [NSMenuItem] = []
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = Bundle.main.path(forResource: "WachModus", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) { NSApp.applicationIconImage = image }

        let root = Dashboard(engine: engine)
        let compactSize = NSSize(width: 540, height: 460)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: compactSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "WachModus"
        // Keep a native title bar outside SwiftUI so dragging never competes with controls.
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isMovable = true
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 480, height: 400)
        window.setContentSize(compactSize)
        // New key avoids restoring the oversized window from 2.0.
        window.setFrameAutosaveName("WachModusCompactWindow")
        window.center()
        createMenu()
        engine.onChange = { [weak self] in self?.updateMenu() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.engine.tick()
            }
        engine.start()
        showWindow()
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        timeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        timeItem.isEnabled = false
        menu.addItem(timeItem)
        menu.addItem(.separator())
        toggleItem = item("Pausieren", action: #selector(toggleSession), key: "p")
        menu.addItem(toggleItem)
        menu.addItem(item("Sitzung zurücksetzen", action: #selector(resetSession)))
        let durationMenu = NSMenu()
        for duration in SessionDuration.allCases {
            let entry = item(duration.title, action: #selector(changeDuration(_:)))
            entry.tag = duration.rawValue
            durationMenu.addItem(entry)
            durationItems.append(entry)
        }
        let durationItem = NSMenuItem(title: "Laufzeit ab jetzt", action: nil, keyEquivalent: "")
        durationItem.submenu = durationMenu
        menu.addItem(durationItem)
        menu.addItem(.separator())
        menu.addItem(item("WachModus öffnen", action: #selector(showWindow)))
        menu.addItem(item("WachModus beenden", action: #selector(quit), key: "q"))
        statusItem.menu = menu

        let sessionMenu = NSMenu(title: "Sitzung")
        sessionToggleItem = item("Pausieren", action: #selector(toggleSession), key: "p")
        sessionMenu.addItem(sessionToggleItem)
        sessionMenu.addItem(item("Sitzung zurücksetzen", action: #selector(resetSession), key: "r"))
        let sessionItem = NSMenuItem(title: "Sitzung", action: nil, keyEquivalent: "")
        sessionItem.submenu = sessionMenu
        NSApp.mainMenu?.insertItem(sessionItem, at: 1)
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func updateMenu() {
        stateItem.title = engine.stateTitle
        timeItem.title = engine.duration == .unlimited ? "Aktive Zeit: \(engine.elapsedText)" : "Verbleibend: \(engine.remainingText)"
        toggleItem.title = engine.isRunning ? "Pausieren" : (engine.state == .paused ? "Fortsetzen" : "Wachmodus starten")
        sessionToggleItem.title = toggleItem.title
        for entry in durationItems { entry.state = entry.tag == engine.duration.rawValue ? .on : .off }
        let image = NSImage(systemSymbolName: engine.isRunning ? "cup.and.saucer.fill" : "cup.and.saucer",
                            accessibilityDescription: engine.stateTitle)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "WachModus · \(engine.stateTitle) · \(engine.elapsedText)"
    }

    func menuWillOpen(_ menu: NSMenu) { engine.tick(); updateMenu() }
    @objc private func toggleSession() { engine.toggle() }
    @objc private func resetSession() { engine.reset() }
    @objc private func changeDuration(_ sender: NSMenuItem) {
        if let duration = SessionDuration(rawValue: sender.tag) { engine.selectDuration(duration) }
    }
    @objc private func showWindow() {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}

if CommandLine.arguments.contains("--selftest") {
    exit(runSelfTest(system: CommandLine.arguments.contains("--system")) ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
let mainMenu = NSMenu()
let appItem = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Über WachModus", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "WachModus ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
appMenu.addItem(.separator())
appMenu.addItem(withTitle: "WachModus beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
mainMenu.addItem(appItem)
let windowItem = NSMenuItem()
let windowMenu = NSMenu(title: "Fenster")
windowMenu.addItem(withTitle: "Minimieren", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
windowMenu.addItem(withTitle: "Schließen", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
windowItem.submenu = windowMenu
mainMenu.addItem(windowItem)
app.mainMenu = mainMenu
app.windowsMenu = windowMenu
app.run()
