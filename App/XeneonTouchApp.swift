// Xeneon Touch — menu-bar wrapper around the touchd driver.
// Lives in the status bar, registers itself as a login item, and asks for the
// two permissions it needs. Delete the app and everything goes with it.

import AppKit
import ServiceManagement
import IOKit.hid

@main
final class App: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = App()
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem!
    private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let restoreItem = NSMenuItem(title: "Restore cursor after touch", action: #selector(toggleRestore), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
    private let permItem = NSMenuItem(title: "Open Privacy & Security…", action: #selector(openPrivacy), keyEquivalent: "")
    private var retryTimer: Timer?
    private var attached = false
    private var running = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreCursor = UserDefaults.standard.object(forKey: "restoreCursor") as? Bool ?? true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "Xeneon Touch")

        let menu = NSMenu()
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())
        for item in [restoreItem, loginItem, permItem] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Xeneon Touch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        onAttachChange = { [weak self] on in self?.attached = on; self?.refresh() }

        // Register as login item on first launch (user can turn it off in the menu).
        if UserDefaults.standard.object(forKey: "loginRegistered") == nil {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginRegistered")
        }

        // Prompt for Accessibility; Input Monitoring is prompted by the HID open itself.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)

        start()
        // Permissions are granted asynchronously in System Settings: keep retrying until the seize works.
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, !self.running else { return }
            self.start()
        }
    }

    private func start() {
        running = startDriver() == kIOReturnSuccess
        refresh()
    }

    private func refresh() {
        let ax = AXIsProcessTrusted()
        if !running {
            stateItem.title = "⚠️ Waiting for Input Monitoring permission"
        } else if !ax {
            stateItem.title = "⚠️ Waiting for Accessibility permission"
        } else {
            stateItem.title = attached ? "● Xeneon Edge connected" : "○ Xeneon Edge not connected"
        }
        restoreItem.state = restoreCursor ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        statusItem.button?.appearsDisabled = !(running && ax && attached)
    }

    @objc private func toggleRestore() {
        restoreCursor.toggle()
        UserDefaults.standard.set(restoreCursor, forKey: "restoreCursor")
        refresh()
    }

    @objc private func toggleLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
        refresh()
    }

    @objc private func openPrivacy() {
        let pane = running ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    func applicationWillTerminate(_ notification: Notification) { stopDriver() }
}
