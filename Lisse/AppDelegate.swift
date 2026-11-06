import Cocoa
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBar = StatusBarController()
    private var settingsObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = AccessibilityPermission.isTrusted(prompt: true)
        if SettingsStore.shared.settings.launchAtLogin {
            LoginItemController.apply(true)
        }
        statusBar.install()
        ScrollEngine.shared.start()
        settingsObserver = SettingsStore.shared.$settings.sink { [weak self] _ in
            self?.statusBar.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScrollEngine.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsStore.shared.mutate { $0.hideMenuBarIcon = false }
        statusBar.refresh()
        PreferencesPresenter.shared.show()
        return true
    }
}

enum AccessibilityPermission {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }
}
