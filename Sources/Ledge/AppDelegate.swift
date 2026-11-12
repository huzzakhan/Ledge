import AppKit
import SwiftUI
import Carbon

extension Notification.Name {
    static let ledgeOpenSettings = Notification.Name("ledge.openSettings")
    static let ledgeToggle = Notification.Name("ledge.toggle")
    static let ledgeReposition = Notification.Name("ledge.reposition")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var dock: DockController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var toggleItem: NSMenuItem?
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dock = DockController()
        setupStatusItem()
        registerHotKey()

        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .ledgeOpenSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleDock),
                                               name: .ledgeToggle, object: nil)

        // First launch: show settings so it's obvious how to customise things.
        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.openSettings() }
        }
    }

    // MARK: Menu bar item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Ledge")

        let menu = NSMenu()
        menu.delegate = self

        let toggle = NSMenuItem(title: "Show Ledge  (⌥⌘D)", action: #selector(toggleDock), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleItem = toggle

        let positionMenu = NSMenu()
        for pos in DockPosition.allCases {
            let mi = NSMenuItem(title: pos.title, action: #selector(setPosition(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = pos.rawValue
            positionMenu.addItem(mi)
        }
        let positionItem = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Ledge", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        toggleItem?.state = AppSettings.shared.dockVisible ? .on : .off
        if let positionMenu = menu.items.first(where: { $0.submenu != nil })?.submenu {
            for mi in positionMenu.items {
                mi.state = (mi.representedObject as? String) == AppSettings.shared.position.rawValue ? .on : .off
            }
        }
    }

    @objc private func setPosition(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let pos = DockPosition(rawValue: raw) {
            AppSettings.shared.position = pos
        }
    }

    @objc func toggleDock() {
        AppSettings.shared.dockVisible.toggle()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: host)
            window.title = "Ledge Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Global shortcut ⌥⌘D toggles the bar

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            NotificationCenter.default.post(name: .ledgeToggle, object: nil)
            return OSStatus(noErr)
        }, 1, &spec, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C444745), id: 1) // 'LDGE'
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(cmdKey | optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
