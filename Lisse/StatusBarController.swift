import Cocoa

final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        menu.delegate = self
        menu.autoenablesItems = false
        refresh()
    }

    func refresh(settings: LisseSettings? = nil) {
        if (settings ?? SettingsStore.shared.settings).hideMenuBarIcon {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        rebuild(settings: settings)
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                if let image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Lisse")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .medium, scale: .medium)) {
                    image.isTemplate = true
                    image.size = NSSize(width: 18, height: 18)
                    button.image = image
                } else {
                    button.title = "Lisse"
                }
                button.setAccessibilityLabel("Lisse")
                button.toolTip = "Lisse"
            }
            item.menu = menu
            statusItem = item
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild(settings snapshot: LisseSettings? = nil) {
        menu.removeAllItems()
        let trusted = AccessibilityPermission.canControlScrolling
        if !trusted {
            let grant = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let settings = snapshot ?? SettingsStore.shared.settings
        let pause = NSMenuItem(title: settings.isPaused ? "Resume Lisse" : "Pause Lisse", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.isEnabled = !settings.isPaused || trusted
        menu.addItem(pause)
        menu.addItem(.separator())
        let smooth = NSMenuItem(title: "Smooth Scrolling", action: #selector(toggleSmooth), keyEquivalent: "")
        smooth.target = self
        smooth.state = settings.scroll.smooth ? .on : .off
        menu.addItem(smooth)

        let reverse = NSMenuItem(title: "Reverse Scroll Direction", action: #selector(toggleReverse), keyEquivalent: "")
        reverse.target = self
        reverse.state = settings.scroll.reverse ? .on : .off
        menu.addItem(reverse)

        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Open Settings…", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        let about = NSMenuItem(title: "About Lisse", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Lisse", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func grantAccess() {
        _ = AccessibilityPermission.isTrusted(prompt: true)
        AccessibilityPermission.openSystemSettings()
    }

    @objc private func togglePause() {
        guard !SettingsStore.shared.settings.isPaused || AccessibilityPermission.canControlScrolling else { return }
        SettingsStore.shared.mutate { $0.isPaused.toggle() }
    }

    @objc private func toggleSmooth() {
        SettingsStore.shared.mutate { $0.scroll.smooth.toggle() }
    }

    @objc private func toggleReverse() {
        SettingsStore.shared.mutate { $0.scroll.reverse.toggle() }
    }

    @objc private func showPreferences() {
        PreferencesPresenter.shared.show()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
