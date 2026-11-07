import Cocoa
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    // This app has no storyboard or nib to create and connect its delegate.
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    private let statusBar = StatusBarController()
    private var settingsObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let settingsOnly = CommandLine.arguments.contains("--settings-only")
        if settingsOnly {
            SettingsStore.shared.mutate { $0.isPaused = true }
        } else {
            _ = AccessibilityPermission.isTrusted(prompt: true)
            if SettingsStore.shared.settings.launchAtLogin { LoginItemController.apply(true) }
        }
        statusBar.install()
        settingsObserver = SettingsStore.shared.$settings.sink { [weak self] settings in
            self?.statusBar.refresh(settings: settings)
            PreferencesPresenter.shared.applyAppearance(settings.appearance.mode)
            if settings.isPaused { ScrollTrial.shared.cancel(); ScrollEngine.shared.stop() }
            else { ScrollEngine.shared.start() }
        }
        if settingsOnly || CommandLine.arguments.contains("--show-preferences") {
            PreferencesPresenter.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if ScrollTrial.shared.remaining > 0 {
            ScrollTrial.shared.cancel()
            SettingsStore.shared.mutate { $0.isPaused = true }
        }
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
    static var canControlScrolling: Bool {
        AXIsProcessTrusted() && CGPreflightPostEventAccess()
    }

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
