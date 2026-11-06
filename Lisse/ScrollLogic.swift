import Foundation

/// Modifier used as a scrolling hotkey. Left and right keys are distinct.
enum ModifierHotkey: String, Codable, CaseIterable, Identifiable, Equatable {
    case none
    case shift
    case option
    case command
    case control
    case rightShift
    case rightOption
    case rightCommand
    case rightControl

    var id: String { rawValue }

    var keyCode: Int? {
        switch self {
        case .none: return nil
        case .shift: return 56
        case .option: return 58
        case .command: return 55
        case .control: return 59
        case .rightShift: return 60
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        }
    }

    var title: String {
        switch self {
        case .none: return "None"
        case .shift: return "Shift"
        case .option: return "Option"
        case .command: return "Command"
        case .control: return "Control"
        case .rightShift: return "Right Shift"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .rightControl: return "Right Control"
        }
    }
}

/// Scrolling preferences shared by the global profile and each app exception.
struct ScrollTuning: Codable, Equatable {
    var smooth: Bool
    var reverse: Bool
    var reverseVertical: Bool
    var reverseHorizontal: Bool
    var smoothVertical: Bool
    var smoothHorizontal: Bool
    var simulateTrackpad: Bool
    var step: Double
    var speed: Double
    var duration: Double
    var accelerate: ModifierHotkey
    var swapAxes: ModifierHotkey
    var pauseSmoothing: ModifierHotkey
    var durationBeforeTrackpadLock: Double?

    static let standard = ScrollTuning(
        smooth: true,
        reverse: true,
        reverseVertical: true,
        reverseHorizontal: true,
        smoothVertical: true,
        smoothHorizontal: true,
        simulateTrackpad: false,
        step: 33.6,
        speed: 2.70,
        duration: 4.35,
        accelerate: .option,
        swapAxes: .shift,
        pauseSmoothing: .command,
        durationBeforeTrackpadLock: nil
    )

    var effectiveReverseVertical: Bool { reverse && reverseVertical }
    var effectiveReverseHorizontal: Bool { reverse && reverseHorizontal }

    func applyingSimulateTrackpad(_ enabled: Bool) -> ScrollTuning {
        var copy = self
        if enabled {
            if copy.durationBeforeTrackpadLock == nil {
                copy.durationBeforeTrackpadLock = copy.duration
            }
            copy.duration = ScrollCurve.simulateTrackpadDuration
            copy.simulateTrackpad = true
        } else {
            copy.simulateTrackpad = false
            if let saved = copy.durationBeforeTrackpadLock {
                copy.duration = saved
            }
            copy.durationBeforeTrackpadLock = nil
        }
        return copy
    }
}

struct AppException: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var bundleIdentifier: String
    var bundlePath: String
    var executablePath: String
    var inherit: Bool
    var scroll: ScrollTuning

    init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String,
        bundlePath: String,
        executablePath: String,
        inherit: Bool = true,
        scroll: ScrollTuning = .standard
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.executablePath = executablePath
        self.inherit = inherit
        self.scroll = scroll
    }
}

struct LisseSettings: Codable, Equatable {
    var launchAtLogin: Bool
    var hideMenuBarIcon: Bool
    var exceptionsAreAllowlist: Bool
    var scroll: ScrollTuning
    var exceptions: [AppException]

    static let standard = LisseSettings(
        launchAtLogin: false,
        hideMenuBarIcon: false,
        exceptionsAreAllowlist: false,
        scroll: .standard,
        exceptions: []
    )
}

struct AppIdentity: Equatable {
    var bundleIdentifier: String
    var bundlePath: String
    var executablePath: String

    static let unknown = AppIdentity(bundleIdentifier: "", bundlePath: "", executablePath: "")
}

enum ScrollResolver {
    static func match(_ settings: LisseSettings, identity: AppIdentity) -> AppException? {
        settings.exceptions.first { item in
            if !identity.bundleIdentifier.isEmpty, item.bundleIdentifier == identity.bundleIdentifier {
                return true
            }
            if !identity.bundlePath.isEmpty, item.bundlePath == identity.bundlePath {
                return true
            }
            if !identity.executablePath.isEmpty, item.executablePath == identity.executablePath {
                return true
            }
            return false
        }
    }

    /// `nil` means the event should pass through untouched (allowlist miss).
    static func resolve(_ settings: LisseSettings, identity: AppIdentity) -> ScrollTuning? {
        if let item = match(settings, identity: identity) {
            return item.inherit ? settings.scroll : item.scroll
        }
        if settings.exceptionsAreAllowlist {
            return nil
        }
        return settings.scroll
    }
}

struct IncomingWheel: Equatable {
    var vertical: Double
    var horizontal: Double
}

struct WheelPlan: Equatable {
    var passthroughY: Double
    var passthroughX: Double
    var smoothY: Double
    var smoothX: Double
    var amplification: Double
    var consumeOriginal: Bool
    var writeY: Bool
    var writeX: Bool
}

enum ScrollPlanner {
    static func plan(
        wheel: IncomingWheel,
        tuning: ScrollTuning,
        accelerate: Bool,
        swapAxes: Bool,
        pauseSmoothing: Bool
    ) -> WheelPlan {
        var y = wheel.vertical
        var x = wheel.horizontal
        let moveVerticalOntoHorizontal = swapAxes && y != 0 && x == 0
        if y != 0 {
            let reverseY = moveVerticalOntoHorizontal ? tuning.effectiveReverseHorizontal : tuning.effectiveReverseVertical
            if reverseY { y = -y }
        }
        if x != 0, tuning.effectiveReverseHorizontal {
            x = -x
        }
        if moveVerticalOntoHorizontal {
            x = y
            y = 0
        }

        let smoothY = !pauseSmoothing && tuning.smooth && tuning.smoothVertical && y != 0
        let smoothX = !pauseSmoothing && tuning.smooth && tuning.smoothHorizontal && x != 0
        let queuedY = smoothY ? atLeastStep(y, step: tuning.step) : 0
        let queuedX = smoothX ? atLeastStep(x, step: tuning.step) : 0
        let passY = smoothY ? 0 : y
        let passX = smoothX ? 0 : x
        let consume = (queuedY != 0 || queuedX != 0) && passY == 0 && passX == 0
        return WheelPlan(
            passthroughY: passY,
            passthroughX: passX,
            smoothY: queuedY,
            smoothX: queuedX,
            amplification: accelerate ? 5 : 1,
            consumeOriginal: consume,
            writeY: queuedY != 0 || passY != wheel.vertical,
            writeX: queuedX != 0 || passX != wheel.horizontal
        )
    }

    static func atLeastStep(_ value: Double, step: Double) -> Double {
        if value == 0 { return 0 }
        let floor = max(step, 0.01)
        if abs(value) >= floor { return value }
        return copysign(floor, value)
    }
}

enum ScrollCurve {
    /// Slider upper bound is 5. The extra 0.2 keeps the blend from reaching zero.
    static let durationUpperBound = 5.2
    static let simulateTrackpadDuration = 4.75

    static func frameBlend(duration: Double) -> Double {
        let clamped = min(max(duration, 0.01), durationUpperBound - 0.0001)
        let raw = 1 - (clamped / durationUpperBound).squareRoot()
        return (raw * 1000).rounded() / 1000
    }
}

struct SmoothingBuffer: Equatable {
    private(set) var targetY = 0.0
    private(set) var targetX = 0.0
    private(set) var deliveredY = 0.0
    private(set) var deliveredX = 0.0
    private var previousY = 0.0
    private var previousX = 0.0

    mutating func absorb(y: Double, x: Double, speed: Double, amplification: Double) {
        let gain = max(speed, 0.01) * amplification
        if y != 0 {
            let scaled = y * gain
            if y * previousY > 0 {
                targetY += scaled
            } else {
                targetY = scaled
                deliveredY = 0
            }
            previousY = y
        }
        if x != 0 {
            let scaled = x * gain
            if x * previousX > 0 {
                targetX += scaled
            } else {
                targetX = scaled
                deliveredX = 0
            }
            previousX = x
        }
    }

    mutating func advance(blend: Double) -> (y: Double, x: Double) {
        let dy = (targetY - deliveredY) * blend
        let dx = (targetX - deliveredX) * blend
        deliveredY += dy
        deliveredX += dx
        return (dy, dx)
    }

    func residual() -> Double {
        max(abs(targetY - deliveredY), abs(targetX - deliveredX))
    }

    mutating func reset() {
        self = SmoothingBuffer()
    }
}
