import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class PreferencesPresenter {
    static let shared = PreferencesPresenter()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: PreferencesRootView())
            let window = NSWindow(contentViewController: host)
            window.title = "Lisse"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 700, height: 540))
            window.isReleasedWhenClosed = false
            self.window = window
        }
        guard let window else { return }
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct PreferencesRootView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ScrollingTab(tuning: scrollBinding)
                .tabItem { Label("Scrolling", systemImage: "computermouse") }
            ExceptionsTab()
                .tabItem { Label("Exceptions", systemImage: "square.stack.3d.up") }
        }
        .padding(18)
        .frame(width: 700, height: 540)
    }

    private var scrollBinding: Binding<ScrollTuning> {
        Binding(
            get: { store.settings.scroll },
            set: { newValue in store.mutate { $0.scroll = newValue } }
        )
    }
}

private struct GeneralTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var trusted = AccessibilityPermission.isTrusted(prompt: false)

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Lisse at login", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Toggle("Show Lisse in the menu bar", isOn: Binding(
                    get: { !store.settings.hideMenuBarIcon },
                    set: { shown in store.mutate { $0.hideMenuBarIcon = !shown } }
                ))
                Text("If the menu bar icon is hidden, open Lisse again to bring it back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Accessibility") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? Color.green : Color.orange)
                    Text(trusted ? "Lisse can smooth mouse-wheel scrolling." : "Lisse needs Accessibility access to read and rewrite mouse-wheel events.")
                }
                HStack {
                    Button("Request Access") {
                        _ = AccessibilityPermission.isTrusted(prompt: true)
                        trusted = AccessibilityPermission.isTrusted(prompt: false)
                    }
                    Button("Open System Settings") {
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            trusted = AccessibilityPermission.isTrusted(prompt: false)
        }
    }
}

private struct ScrollingTab: View {
    @Binding var tuning: ScrollTuning

    var body: some View {
        ScrollControls(tuning: $tuning)
    }
}

struct ScrollControls: View {
    @Binding var tuning: ScrollTuning

    var body: some View {
        Form {
            Section("Smoothing") {
                Toggle("Smooth mouse-wheel scrolling", isOn: $tuning.smooth)
                Toggle("Smooth vertical", isOn: $tuning.smoothVertical)
                    .disabled(!tuning.smooth)
                Toggle("Smooth horizontal", isOn: $tuning.smoothHorizontal)
                    .disabled(!tuning.smooth)
                Toggle("Simulate trackpad", isOn: simulateBinding)
                Text("Step is the smallest distance for one notch. Speed multiplies that distance. Duration is how long the glide lasts.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                slider("Step", value: $tuning.step, range: 0.01...100)
                slider("Speed", value: $tuning.speed, range: 1...10)
                slider("Duration", value: $tuning.duration, range: 1...5)
                    .disabled(tuning.simulateTrackpad)
            }
            Section("Direction") {
                Toggle("Reverse scroll direction", isOn: $tuning.reverse)
                Toggle("Reverse vertical", isOn: $tuning.reverseVertical)
                    .disabled(!tuning.reverse)
                Toggle("Reverse horizontal", isOn: $tuning.reverseHorizontal)
                    .disabled(!tuning.reverse)
            }
            Section("While held") {
                hotkey("Accelerate (5×)", selection: $tuning.accelerate)
                hotkey("Swap vertical and horizontal", selection: $tuning.swapAxes)
                hotkey("Pause smoothing", selection: $tuning.pauseSmoothing)
            }
        }
        .formStyle(.grouped)
    }

    private var simulateBinding: Binding<Bool> {
        Binding(
            get: { tuning.simulateTrackpad },
            set: { tuning = tuning.applyingSimulateTrackpad($0) }
        )
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func hotkey(_ title: String, selection: Binding<ModifierHotkey>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ModifierHotkey.allCases) { hotkey in
                Text(hotkey.title).tag(hotkey)
            }
        }
    }
}

private struct ExceptionsTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var selection: UUID?
    @State private var runningApps: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Change scrolling only in the applications listed below", isOn: Binding(
                get: { store.settings.exceptionsAreAllowlist },
                set: { value in store.mutate { $0.exceptionsAreAllowlist = value } }
            ))
            Text(store.settings.exceptionsAreAllowlist
                 ? "Other applications keep macOS scrolling and direction."
                 : "Every application uses the global settings unless it has its own exception.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading) {
                    List(store.settings.exceptions, selection: $selection) { item in
                        Text(item.displayName.isEmpty ? item.bundleIdentifier : item.displayName)
                            .tag(item.id)
                    }
                    .frame(minWidth: 200, minHeight: 280)
                    HStack {
                        Button("Add Application…", action: addFromPanel)
                        Menu("Add Running") {
                            ForEach(runningApps, id: \.processIdentifier) { app in
                                Button(app.localizedName ?? "Application") {
                                    add(app)
                                }
                            }
                        }
                        .onHover { hovering in
                            if hovering { reloadRunning() }
                        }
                        Button("Remove", action: removeSelected)
                            .disabled(selection == nil)
                    }
                }
                if let binding = selectedException {
                    VStack(alignment: .leading) {
                        Toggle("Use global scrolling settings", isOn: binding.inherit)
                        if !binding.wrappedValue.inherit {
                            ScrollControls(tuning: binding.scroll)
                        } else {
                            Text("\(binding.wrappedValue.displayName) follows the Scrolling tab.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    Text("Select an application to give it its own step, speed, duration, or direction.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .onAppear(perform: reloadRunning)
    }

    private var selectedException: Binding<AppException>? {
        guard let selection else { return nil }
        return Binding(
            get: {
                store.settings.exceptions.first { $0.id == selection }
                    ?? AppException(displayName: "", bundleIdentifier: "", bundlePath: "", executablePath: "")
            },
            set: { newValue in
                store.mutate { settings in
                    guard let index = settings.exceptions.firstIndex(where: { $0.id == selection }) else { return }
                    settings.exceptions[index] = newValue
                }
            }
        )
    }

    private func reloadRunning() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func addFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(url: url, displayName: nil, bundleIdentifier: nil, executablePath: nil)
    }

    private func add(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        add(
            url: url,
            displayName: app.localizedName,
            bundleIdentifier: app.bundleIdentifier,
            executablePath: app.executableURL?.path
        )
    }

    private func add(url: URL, displayName: String?, bundleIdentifier: String?, executablePath: String?) {
        let bundle = Bundle(url: url)
        let name = displayName
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let identifier = bundleIdentifier ?? bundle?.bundleIdentifier ?? ""
        let executable = executablePath ?? bundle?.executableURL?.path ?? ""
        let path = url.path
        var created: UUID?
        store.mutate { settings in
            if let index = settings.exceptions.firstIndex(where: {
                (!identifier.isEmpty && $0.bundleIdentifier == identifier) || $0.bundlePath == path
            }) {
                created = settings.exceptions[index].id
                return
            }
            let item = AppException(
                displayName: name,
                bundleIdentifier: identifier,
                bundlePath: path,
                executablePath: executable
            )
            settings.exceptions.append(item)
            created = item.id
        }
        selection = created
    }

    private func removeSelected() {
        guard let selection else { return }
        store.mutate { settings in
            settings.exceptions.removeAll { $0.id == selection }
        }
        self.selection = nil
    }
}
