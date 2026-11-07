import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let lisseVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"

final class PreferencesPresenter: NSObject, NSWindowDelegate {
    static let shared = PreferencesPresenter()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: PreferencesRootView())
            let window = NSWindow(contentViewController: host)
            window.title = "Lisse"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 940, height: 700))
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        applyAppearance(SettingsStore.shared.settings.appearance.mode)
        guard let window else { return }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }

    func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: window?.appearance = nil
        case .light: window?.appearance = NSAppearance(named: .aqua)
        case .dark: window?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case scrolling, applications, appearance, general
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .scrolling: return "wind"
        case .applications: return "square.stack.3d.up"
        case .appearance: return "paintpalette"
        case .general: return "gearshape"
        }
    }
    var title: String {
        switch self {
        case .scrolling: return "Find your flow."
        case .applications: return "A feel for every app."
        case .appearance: return "Make it yours."
        case .general: return "Right at home."
        }
    }
    var subtitle: String {
        switch self {
        case .scrolling: return "Softer movement. A little more glide."
        case .applications: return "Keep your global feel, or fine-tune individual apps."
        case .appearance: return "Choose the light, the color, and the little details."
        case .general: return "Startup, menu bar, and Accessibility access."
        }
    }
}

struct PreferencesRootView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var page = SettingsPage.scrolling
    @State private var accessReady = AccessibilityPermission.canControlScrolling
    @ObservedObject private var trial = ScrollTrial.shared
    private var accent: Color { Color(hex: store.settings.appearance.accentHex) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(page.title).font(.system(size: 27, weight: .semibold, design: .rounded))
                        Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                    VStack(alignment: .trailing, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { !store.settings.isPaused },
                        set: { enabled in store.mutate { $0.isPaused = !enabled } }
                    )) {
                        Text(store.settings.isPaused ? "Paused" : "Enabled")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel("Enable Lisse")
                    .padding(.top, 5)
                    .disabled(!accessReady && store.settings.isPaused)
                    if trial.remaining > 0 {
                        Text("Auto-pauses in \(trial.remaining)s").font(.system(size: 10)).foregroundStyle(.secondary)
                    } else if store.settings.isPaused {
                        Button("Try for 30 seconds") { trial.start() }
                            .buttonStyle(.borderless).font(.system(size: 10, weight: .medium)).disabled(!accessReady)
                    }
                    }
                }
                .padding(.horizontal, 28).padding(.top, 25).padding(.bottom, 22)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch page {
                        case .scrolling:
                            if !accessReady {
                                HStack(spacing: 10) {
                                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                                    Text("Allow Accessibility to enable scrolling.").font(.system(size: 11))
                                    Spacer()
                                    Button("Set up access") { page = .general }.buttonStyle(.borderless).font(.system(size: 11, weight: .semibold))
                                }.padding(13).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                            }
                            ScrollControls(tuning: scrollBinding)
                        case .applications:
                            ExceptionsTab()
                        case .appearance:
                            AppearanceTab()
                        case .general:
                            GeneralTab()
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 940, height: 700)
        .tint(accent)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in accessReady = AccessibilityPermission.canControlScrolling }
        .environment(\.lisseAccent, accent)
        .preferredColorScheme(store.settings.appearance.mode == .system ? nil : (store.settings.appearance.mode == .dark ? .dark : .light))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lisse").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("A smoother everyday.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 25).padding(.bottom, 34)
            Text("CUSTOMIZE").font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(.secondary).padding(.leading, 12).padding(.bottom, 12)
            ForEach(SettingsPage.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol).font(.system(size: 15, weight: .medium)).frame(width: 20)
                        Text(item.label).font(.system(size: 13, weight: page == item ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.9).layoutPriority(1)
                        Spacer()
                        if page == item { Circle().fill(accent).frame(width: 5, height: 5) }
                    }
                    .foregroundStyle(page == item ? accent : Color.primary.opacity(0.75))
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .background(page == item ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).padding(.bottom, 5)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(store.settings.isPaused ? Color.secondary : accent).frame(width: 6, height: 6)
                    Text(store.settings.isPaused ? "Scrolling paused" : "Lisse is enabled")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(store.settings.isPaused ? "Your mouse uses macOS scrolling." : "Hold your pause shortcut for native scrolling.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            Text("LISSE \(lisseVersion)").font(.system(size: 9, weight: .medium)).tracking(1.2)
                .foregroundStyle(.tertiary).padding(.top, 20).padding(.bottom, 20).padding(.leading, 12)
        }
        .padding(.horizontal, 15).frame(width: 192)
        .background(LinearGradient(colors: [accent.opacity(0.07), Color(nsColor: .controlBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var scrollBinding: Binding<ScrollTuning> {
        Binding(get: { store.settings.scroll }, set: { value in store.mutate { $0.scroll = value } })
    }
}

private struct AccentKey: EnvironmentKey { static let defaultValue = Color(hex: "159B91") }
private extension EnvironmentValues {
    var lisseAccent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !title.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.055)))
    }
}

struct ScrollControls: View {
    @Binding var tuning: ScrollTuning
    @Environment(\.lisseAccent) private var accent
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !compact {
                HStack(spacing: 10) {
                    ForEach(ScrollPreset.allCases) { preset in
                        Button { tuning = preset.applying(to: tuning) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Image(systemName: preset.symbol).font(.system(size: 19, weight: .medium))
                                    Spacer()
                                    if preset.matches(tuning) { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)) }
                                }
                                Text(preset.title).font(.system(size: 13, weight: .semibold))
                                Text(preset.subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .foregroundStyle(preset.matches(tuning) ? accent : Color.primary)
                            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(preset.matches(tuning) ? accent.opacity(0.10) : Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(preset.matches(tuning) ? accent.opacity(0.55) : Color.primary.opacity(0.06), lineWidth: preset.matches(tuning) ? 1.5 : 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                GlidePreview(duration: tuning.duration)
            }
            SettingsCard("Tune the feel", subtitle: "Changes save automatically.") {
                Toggle("Smooth mouse-wheel scrolling", isOn: $tuning.smooth).toggleStyle(.switch)
                Divider().opacity(0.5)
                slider("Wheel distance", detail: "Movement from a light wheel notch", value: $tuning.step, range: 1...100, text: String(format: "%.0f px", tuning.step))
                slider("Speed", detail: "How far each movement travels", value: $tuning.speed, range: 1...6, text: String(format: "%.2f×", tuning.speed))
                slider("Glide length", detail: "Longer feels softer and eases out slowly", value: $tuning.duration, range: 2...5, text: String(format: "≈ %.2f s", ScrollCurve.approximateGlideTime(duration: tuning.duration)))
                    .disabled(tuning.simulateTrackpad)
                if !tuning.smooth { Text("Smoothing is off. Direction controls still apply when Lisse is enabled.").font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard("Axes & direction") {
                HStack {
                    Toggle("Vertical smoothing", isOn: $tuning.smoothVertical)
                    Spacer()
                    Toggle("Horizontal smoothing", isOn: $tuning.smoothHorizontal)
                }.font(.system(size: 12)).disabled(!tuning.smooth)
                Divider().opacity(0.5)
                Toggle("Reverse mouse-wheel direction", isOn: $tuning.reverse).toggleStyle(.switch)
                HStack {
                    Toggle("Vertical", isOn: $tuning.reverseVertical)
                    Spacer()
                    Toggle("Horizontal", isOn: $tuning.reverseHorizontal)
                }.font(.system(size: 12)).disabled(!tuning.reverse)
            }
            SettingsCard("Shortcuts", subtitle: "Use these keys while moving the wheel.") {
                hotkey("Accelerate · 5×", selection: $tuning.accelerate)
                hotkey("Scroll sideways", selection: $tuning.swapAxes)
                hotkey("Temporarily skip smoothing", selection: $tuning.pauseSmoothing)
            }
            SettingsCard("Advanced") {
                Toggle("Simulate trackpad gestures", isOn: Binding(get: { tuning.simulateTrackpad }, set: { tuning = tuning.applyingSimulateTrackpad($0) })).toggleStyle(.switch)
                Text("Adds gesture phases for apps that expect a trackpad. Uses a fixed glide length.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func slider(_ title: String, detail: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accent.opacity(0.08), in: Capsule())
            }
            Slider(value: value, in: range).accessibilityLabel(title)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private func hotkey(_ title: String, selection: Binding<ModifierHotkey>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Picker(title, selection: selection) {
                ForEach(ModifierHotkey.allCases) { Text($0.title).tag($0) }
            }.labelsHidden().frame(width: 135)
        }
    }
}

private struct GlidePreview: View {
    let duration: Double
    @ObservedObject private var store = SettingsStore.shared
    @Environment(\.lisseAccent) private var accent
    @State private var progress = 0.0
    @State private var running = false
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Feel the glide", systemImage: "sparkle").font(.system(size: 11, weight: .medium))
                Spacer()
                Button(running ? "Gliding…" : "Preview") {
                    progress = 0
                    running = true
                    let length = max(0.2, ScrollCurve.approximateGlideTime(duration: duration))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                        withAnimation(store.settings.appearance.animatePreview ? .timingCurve(0.15, 0.7, 0.2, 1, duration: length) : nil) { progress = 1 }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.1) { running = false }
                }.buttonStyle(.borderless).font(.system(size: 11, weight: .semibold)).disabled(running)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.12)).frame(height: 3)
                    ForEach(0..<14) { index in
                        Circle().fill(accent.opacity(0.14)).frame(width: 4, height: 4)
                            .offset(x: CGFloat(index) / 13 * (geometry.size.width - 12))
                    }
                    Circle().fill(accent.gradient).frame(width: 14, height: 14)
                        .shadow(color: accent.opacity(0.2), radius: 5, y: 2)
                        .offset(x: progress * (geometry.size.width - 14))
                }.frame(height: 18)
            }.frame(height: 18)
        }
        .padding(16).background(accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct AppearanceTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @Environment(\.lisseAccent) private var accent
    private let swatches = [("Mint", "159B91"), ("Ocean", "277BE9"), ("Violet", "8462D5"), ("Rose", "D85988"), ("Amber", "C18A2B"), ("Graphite", "737C8C")]
    var body: some View {
        SettingsCard("Theme", subtitle: "A comfortable space, morning or night.") {
            HStack(spacing: 12) {
                ForEach(AppearanceMode.allCases) { mode in
                    Button { store.mutate { $0.appearance.mode = mode } } label: {
                        VStack(spacing: 10) {
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Circle().fill(accent).frame(width: 9, height: 9)
                                    RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.5)).frame(width: 26, height: 4)
                                    RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.35)).frame(width: 20, height: 4)
                                    Spacer()
                                }.padding(10).frame(width: 52).background(accent.opacity(0.13))
                                VStack(alignment: .leading, spacing: 7) {
                                    RoundedRectangle(cornerRadius: 3).fill(mode == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.2)).frame(width: 55, height: 5)
                                    RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.22)).frame(height: 18)
                                    RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.12)).frame(height: 18)
                                }.padding(10)
                            }
                            .frame(height: 89).background(mode == .dark ? Color(white: 0.13) : mode == .light ? Color.white : Color(nsColor: .windowBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            HStack {
                                Text(mode.title).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Image(systemName: store.settings.appearance.mode == mode ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.settings.appearance.mode == mode ? accent : Color.secondary.opacity(0.4))
                            }
                        }.padding(12).frame(maxWidth: .infinity)
                            .background(store.settings.appearance.mode == mode ? accent.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(store.settings.appearance.mode == mode ? accent.opacity(0.5) : Color.primary.opacity(0.08)))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        SettingsCard("Accent color", subtitle: "A little color, throughout Lisse.") {
            HStack(spacing: 17) {
                ForEach(swatches, id: \.1) { name, hex in
                    Button { store.mutate { $0.appearance.accentHex = hex } } label: {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                                if store.settings.appearance.accentHex == hex { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                            }
                            Text(name).font(.system(size: 9)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(name + " accent")
                }
            }
            Divider().opacity(0.5)
            ColorPicker("Custom color", selection: Binding(get: { accent }, set: { color in store.mutate { $0.appearance.accentHex = color.hexRGB } }), supportsOpacity: false)
                .font(.system(size: 12))
        }
        SettingsCard("Motion") {
            Toggle("Animate the glide preview", isOn: Binding(get: { store.settings.appearance.animatePreview }, set: { value in store.mutate { $0.appearance.animatePreview = value } })).toggleStyle(.switch)
            Text("This only changes the preview animation. Your scrolling settings stay the same.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var trusted = AccessibilityPermission.canControlScrolling
    var body: some View {
        VStack(spacing: 18) {
            SettingsCard("Everyday essentials") {
                Toggle("Launch Lisse at login", isOn: Binding(get: { store.settings.launchAtLogin }, set: { store.setLaunchAtLogin($0) })).toggleStyle(.switch)
                Divider().opacity(0.5)
                Toggle("Show Lisse in the menu bar", isOn: Binding(get: { !store.settings.hideMenuBarIcon }, set: { value in store.mutate { $0.hideMenuBarIcon = !value } })).toggleStyle(.switch)
                Text("Open Lisse again to bring its icon and settings back.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SettingsCard("Accessibility") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: trusted ? "checkmark.shield.fill" : "hand.raised.fill")
                        .font(.system(size: 24)).foregroundStyle(trusted ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(trusted ? "Access is ready" : "One permission to get started").font(.system(size: 13, weight: .semibold))
                        Text("Lisse uses Accessibility access to adjust mouse-wheel scrolling. Trackpad scrolling stays with macOS.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Open System Settings", action: AccessibilityPermission.openSystemSettings)
                    if !trusted { Button("Request Access") { _ = AccessibilityPermission.isTrusted(prompt: true) } }
                }
            }
            SettingsCard("") {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Lisse \(lisseVersion)").font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("A smoother everyday.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text("Made for your mouse. Designed for your Mac.").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            }
        }.onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in trusted = AccessibilityPermission.canControlScrolling }
    }
}

private struct ExceptionsTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var selection: UUID?
    @State private var runningApps: [NSRunningApplication] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Application rules") {
                Toggle("Only customize the apps listed here", isOn: Binding(get: { store.settings.exceptionsAreAllowlist }, set: { value in store.mutate { $0.exceptionsAreAllowlist = value } })).toggleStyle(.switch)
                Text(store.settings.exceptionsAreAllowlist ? "All other apps keep their normal macOS scrolling." : "Other apps use your global settings.").font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Button("Add Application…", action: addFromPanel)
                    Menu("Add Running") {
                        ForEach(runningApps, id: \.processIdentifier) { app in Button(app.localizedName ?? "Application") { add(app) } }
                    }.onHover { if $0 { reloadRunning() } }
                    Spacer()
                    Button("Remove", action: removeSelected).disabled(selection == nil)
                }
                if store.settings.exceptions.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("One feel. Or one for every app.").font(.system(size: 13, weight: .medium))
                        Text("Add an app to customize its scrolling.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    Picker("Application", selection: $selection) {
                        Text("Select an application").tag(Optional<UUID>.none)
                        ForEach(store.settings.exceptions) { item in Text(item.displayName).tag(Optional(item.id)) }
                    }
                }
            }
            if let binding = selectedException {
                SettingsCard(binding.wrappedValue.displayName) {
                    Toggle("Use global scrolling settings", isOn: binding.inherit).toggleStyle(.switch)
                    if binding.wrappedValue.inherit { Text("This app follows the Scrolling page.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                if !binding.wrappedValue.inherit { ScrollControls(tuning: binding.scroll, compact: true) }
            }
        }.onAppear(perform: reloadRunning)
    }

    private var selectedException: Binding<AppException>? {
        guard let selection else { return nil }
        return Binding(get: { store.settings.exceptions.first { $0.id == selection } ?? AppException(displayName: "", bundleIdentifier: "", bundlePath: "", executablePath: "") }, set: { value in
            store.mutate { settings in
                guard let index = settings.exceptions.firstIndex(where: { $0.id == selection }) else { return }
                settings.exceptions[index] = value
            }
        })
    }
    private func reloadRunning() {
        runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    private func addFromPanel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false; panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(url: url, displayName: nil, bundleIdentifier: nil, executablePath: nil)
    }
    private func add(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { return }
        add(url: url, displayName: app.localizedName, bundleIdentifier: app.bundleIdentifier, executablePath: app.executableURL?.path)
    }
    private func add(url: URL, displayName: String?, bundleIdentifier: String?, executablePath: String?) {
        let bundle = Bundle(url: url)
        let name = displayName ?? (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
        let identifier = bundleIdentifier ?? bundle?.bundleIdentifier ?? ""
        let executable = executablePath ?? bundle?.executableURL?.path ?? ""
        var created: UUID?
        store.mutate { settings in
            if let found = settings.exceptions.first(where: { (!identifier.isEmpty && $0.bundleIdentifier == identifier) || $0.bundlePath == url.path }) { created = found.id; return }
            let item = AppException(displayName: name, bundleIdentifier: identifier, bundlePath: url.path, executablePath: executable)
            settings.exceptions.append(item); created = item.id
        }
        selection = created
    }
    private func removeSelected() {
        guard let selection else { return }
        store.mutate { $0.exceptions.removeAll { $0.id == selection } }
        self.selection = nil
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x159B91
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var hexRGB: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "159B91" }
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
