import Combine
import Foundation
import ServiceManagement

/// Thread-safe copy of the settings the scroll engine reads off the main thread.
final class SettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: LisseSettings

    init(_ settings: LisseSettings) {
        self.settings = settings
    }

    func read() -> LisseSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func write(_ settings: LisseSettings) {
        lock.lock()
        self.settings = settings
        lock.unlock()
    }
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    static let defaultsKey = "LisseSettings"

    @Published private(set) var settings: LisseSettings
    let box: SettingsBox

    private init() {
        let loaded = SettingsStore.load() ?? .standard
        settings = loaded
        box = SettingsBox(loaded)
    }

    func mutate(_ body: (inout LisseSettings) -> Void) {
        var copy = settings
        body(&copy)
        box.write(copy)
        settings = copy
        persist()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        mutate { $0.launchAtLogin = enabled }
        LoginItemController.apply(enabled)
    }

    func binding<Value>(_ keyPath: WritableKeyPath<LisseSettings, Value>) -> BindingBox<Value> {
        BindingBox(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                self.mutate { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func load() -> LisseSettings? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(LisseSettings.self, from: data)
    }
}

/// Tiny getter/setter pair so SwiftUI bindings can be built without importing SwiftUI here.
struct BindingBox<Value> {
    var get: () -> Value
    var set: (Value) -> Void
}

enum LoginItemController {
    static func apply(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Lisse could not update launch at login: \(error.localizedDescription)")
        }
    }

    static func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}

/// A short trial always returns to paused, even if the user leaves Settings.
final class ScrollTrial: ObservableObject {
    static let shared = ScrollTrial()
    @Published private(set) var remaining = 0
    private var timer: Timer?

    func start() {
        cancel()
        remaining = 30
        SettingsStore.shared.mutate { $0.isPaused = false }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remaining -= 1
            if self.remaining <= 0 {
                self.cancel()
                SettingsStore.shared.mutate { $0.isPaused = true }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        if remaining != 0 { remaining = 0 }
    }
}
