import Cocoa
import Combine

final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        menu.delegate = self
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
            if let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Lisse") {
                image.isTemplate = true
                item.button?.image = image
            } else {
                item.button?.title = "L"
            }
            item.menu = menu
            statusItem = item
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
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
