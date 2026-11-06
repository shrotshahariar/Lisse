import Cocoa

final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        menu.delegate = self
        menu.autoenablesItems = false
        refresh()
    }

    func refresh() {
        if SettingsStore.shared.settings.hideMenuBarIcon {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                if let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Lisse") {
                    image.isTemplate = true
                    image.size = NSSize(width: 18, height: 18)
                    button.image = image
                } else {
                    button.title = "Lisse"
                }
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            // Leave item.menu unset. An empty status-item menu swallows the click,
            // and menuWillOpen never runs, so the icon appears to do nothing.
            statusItem = item
        }
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        rebuild()
        PreferencesPresenter.shared.show()
        guard let button = statusItem?.button else { return }
        button.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        button.highlight(false)
    }

    private func rebuild() {
        menu.removeAllItems()
        let trusted = AccessibilityPermission.isTrusted(prompt: false)
        if !trusted {
            let grant = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantAccess), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
            menu.addItem(.separator())
        }

        let settings = SettingsStore.shared.settings
        let smooth = NSMenuItem(title: "Smooth Scrolling", action: #selector(toggleSmooth), keyEquivalent: "")
        smooth.target = self
        smooth.state = settings.scroll.smooth ? .on : .off
        menu.addItem(smooth)

        let reverse = NSMenuItem(title: "Reverse Scroll Direction", action: #selector(toggleReverse), keyEquivalent: "")
        reverse.target = self
        reverse.state = settings.scroll.reverse ? .on : .off
        menu.addItem(reverse)

        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
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
