import Cocoa
import CoreVideo

/// Installs a session event tap and turns discrete mouse-wheel notches into a short glide.
final class ScrollEngine {
    static let shared = ScrollEngine()

    private let lock = NSLock()
    private var buffer = SmoothingBuffer()
    private var displayLink: CVDisplayLink?
    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var heldKeys = Set<Int>()
    private var lastWheelTime = 0.0
    private var inputEnded = true
    private var sentBegan = false
    private var linkArmed = false
    private var activeDuration = ScrollTuning.standard.duration
    private var lastFrameTime = 0.0
    private var activeSimulate = false
    private var carryY = 0.0
    private var carryX = 0.0
    private let settleThreshold = 1.0
    private let inputGap = 0.12
    private let marker: Int64 = 0x4C4953534501
    private var launchpadCache = (at: 0.0, active: false)
    private var eventTemplate: CGEvent?
    private var targetPID: pid_t = 0
    private var generation: UInt64 = 0
    private let settingsProvider: () -> LisseSettings
    private let postingAllowed: () -> Bool
    private let frameStarter: (() -> Bool)?
    private let eventPoster: (CGEvent, pid_t) -> Void
    private let clock: () -> CFAbsoluteTime

    init(
        settings: @escaping () -> LisseSettings = { SettingsStore.shared.box.read() },
        postingAllowed: @escaping () -> Bool = { AXIsProcessTrusted() && CGPreflightPostEventAccess() },
        frameStarter: (() -> Bool)? = nil,
        eventPoster: @escaping (CGEvent, pid_t) -> Void = { $0.postToPid($1) },
        clock: @escaping () -> CFAbsoluteTime = CFAbsoluteTimeGetCurrent
    ) {
        settingsProvider = settings
        self.postingAllowed = postingAllowed
        self.frameStarter = frameStarter
        self.eventPoster = eventPoster
        self.clock = clock
    }

    func start() {
        guard tapPort == nil else { return }
        let mask = (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: ScrollEngine.tapCallback,
            userInfo: context
        ) else {
            scheduleRetry()
            return
        }
        retryTimer?.invalidate()
        retryTimer = nil
        tapPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        cancelSmoothing()
        if let tapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes)
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
        }
        tapSource = nil
        tapPort = nil
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.start()
        }
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, user in
        guard let user else { return Unmanaged.passUnretained(event) }
        let engine = Unmanaged<ScrollEngine>.fromOpaque(user).takeUnretainedValue()
        return engine.handle(type: type, event: event)
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tapPort {
                CGEvent.tapEnable(tap: tapPort, enable: true)
            }
            return nil
        }
        if type == .flagsChanged {
            noteModifiers(event)
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        if event.getIntegerValueField(.eventSourceUserData) == marker {
            return Unmanaged.passUnretained(event)
        }
        if Self.looksLikeTrackpad(event) || Self.remoteDesktopAlreadySmoothed(event) {
            return Unmanaged.passUnretained(event)
        }

        let identity = Self.identity(of: event)
        let settings = settingsProvider()
        guard var tuning = ScrollResolver.resolve(settings, identity: identity) else {
            return Unmanaged.passUnretained(event)
        }
        if launchpadIsActive(identity) {
            tuning.smooth = false
        }
        let plan = ScrollPlanner.plan(
            wheel: IncomingWheel(
                vertical: Self.usableDelta(event, vertical: true),
                horizontal: Self.usableDelta(event, vertical: false)
            ),
            tuning: tuning,
            accelerate: isHeld(tuning.accelerate),
            swapAxes: isHeld(tuning.swapAxes),
            pauseSmoothing: isHeld(tuning.pauseSmoothing)
        )

        if plan.smoothY != 0 || plan.smoothX != 0 {
            // Never swallow the wheel unless we can deliver its replacement.
            let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
            guard postingAllowed(), pid > 1, let template = event.copy() else {
                cancelSmoothing()
                return Unmanaged.passUnretained(event)
            }
            let duration = tuning.simulateTrackpad ? ScrollCurve.simulateTrackpadDuration : tuning.duration
            lock.lock()
            if targetPID != pid {
                buffer.reset()
                carryY = 0
                carryX = 0
                sentBegan = false
            }
            eventTemplate = template
            targetPID = pid
            generation &+= 1
            let wasIdle = buffer.residual() <= settleThreshold
            buffer.absorb(
                y: plan.smoothY,
                x: plan.smoothX,
                speed: tuning.speed,
                amplification: plan.amplification
            )
            activeDuration = duration
            activeSimulate = tuning.simulateTrackpad
            lastWheelTime = clock()
            inputEnded = false
            if wasIdle {
                lastFrameTime = clock()
                sentBegan = false
                carryY = 0
                carryX = 0
            }
            linkArmed = true
            lock.unlock()
            // Queue the input before starting the display callback. A callback
            // can run immediately, including before CVDisplayLinkStart returns.
            guard ensureDisplayLink() else {
                cancelSmoothing()
                return Unmanaged.passUnretained(event)
            }
        }

        if plan.consumeOriginal {
            return nil
        }
        if plan.writeY || plan.writeX {
            Self.write(event, plan: plan)
        }
        return Unmanaged.passUnretained(event)
    }

    private func noteModifiers(_ event: CGEvent) {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if flags.intersection([.maskShift, .maskAlternate, .maskCommand, .maskControl]).isEmpty {
            heldKeys.removeAll()
            return
        }
        let pressed: Bool?
        switch code {
        case 56, 60: pressed = flags.contains(.maskShift)
        case 58, 61: pressed = flags.contains(.maskAlternate)
        case 55, 54: pressed = flags.contains(.maskCommand)
        case 59, 62: pressed = flags.contains(.maskControl)
        default: pressed = nil
        }
        guard let pressed else { return }
        if pressed {
            heldKeys.insert(code)
        } else {
            heldKeys.remove(code)
        }
    }

    private func isHeld(_ hotkey: ModifierHotkey) -> Bool {
        guard let code = hotkey.keyCode else { return false }
        return heldKeys.contains(code)
    }

    private func ensureDisplayLink() -> Bool {
        if let frameStarter { return frameStarter() }
        if let displayLink {
            return CVDisplayLinkIsRunning(displayLink)
                || CVDisplayLinkStart(displayLink) == kCVReturnSuccess
        }
        var link: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess, let link else {
            return false
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callbackResult = CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, user in
            guard let user else { return kCVReturnSuccess }
            Unmanaged<ScrollEngine>.fromOpaque(user).takeUnretainedValue().displayFrame()
            return kCVReturnSuccess
        }, context)
        guard callbackResult == kCVReturnSuccess else { return false }
        displayLink = link
        guard CVDisplayLinkStart(link) == kCVReturnSuccess else {
            displayLink = nil
            return false
        }
        return true
    }

    private func stopDisplayLink() {
        if let displayLink, CVDisplayLinkIsRunning(displayLink) {
            CVDisplayLinkStop(displayLink)
        }
    }

    private func cancelSmoothing() {
        lock.lock()
        generation &+= 1
        linkArmed = false
        buffer.reset()
        eventTemplate = nil
        targetPID = 0
        carryY = 0
        carryX = 0
        sentBegan = false
        lastWheelTime = 0
        inputEnded = true
        lastFrameTime = 0
        lock.unlock()
        stopDisplayLink()
    }

    func displayFrame() {
        var deltaY = 0.0
        var deltaX = 0.0
        var phase = PostedPhase.plain
        var simulate = false
        var shouldPost = false
        var shouldEnd = false
        var shouldStop = false

        lock.lock()
        guard linkArmed else {
            lock.unlock()
            return
        }
        let now = clock()
        if !inputEnded, lastWheelTime > 0, now - lastWheelTime > inputGap {
            inputEnded = true
        }
        let frameGeneration = generation
        let template = eventTemplate?.copy()
        let pid = targetPID
        let elapsed = lastFrameTime > 0 ? max(0, now - lastFrameTime) : 1.0 / 60
        lastFrameTime = now
        let blend = ScrollCurve.frameBlend(duration: activeDuration, elapsed: elapsed)
        let step = buffer.advance(blend: blend)
        carryY += step.y
        carryX += step.x
        // Point deltas are integer pixels. Keep fractions for later frames.
        deltaY = carryY.rounded(.towardZero)
        deltaX = carryX.rounded(.towardZero)
        simulate = activeSimulate
        shouldPost = deltaY != 0 || deltaX != 0
        carryY -= deltaY
        carryX -= deltaX
        if simulate {
            if inputEnded {
                phase = .momentum
            } else if !sentBegan {
                phase = .began
                sentBegan = true
            } else {
                phase = .changed
            }
        }
        if inputEnded, buffer.residual() <= settleThreshold {
            shouldStop = true
            shouldEnd = simulate && sentBegan
            deltaY += carryY.rounded()
            deltaX += carryX.rounded()
            shouldPost = deltaY != 0 || deltaX != 0
            carryY = 0
            carryX = 0
            buffer.reset()
            sentBegan = false
            lastWheelTime = 0
            linkArmed = false
        }
        lock.unlock()

        if let template, pid > 1 {
            if shouldPost {
                post(template: template, pid: pid, y: deltaY, x: deltaX, simulate: simulate, phase: phase)
            }
            if shouldEnd {
                post(template: template, pid: pid, y: 0, x: 0, simulate: true, phase: .ended)
            }
        }
        if shouldStop {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let stillFinished = self.generation == frameGeneration && !self.linkArmed
                self.lock.unlock()
                // A previous gesture must never stop a newly queued gesture.
                if stillFinished { self.stopDisplayLink() }
            }
        }
    }

    private func post(template: CGEvent, pid: pid_t, y: Double, x: Double, simulate: Bool, phase: PostedPhase) {
        guard postingAllowed(),
              let event = template.copy(),
              let deltas = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(clamping: Int64(y.rounded())),
                wheel2: Int32(clamping: Int64(x.rounded())),
                wheel3: 0
              ) else { return }
        // Keep the original target window, position and modifiers. Fresh HID
        // events lose this routing context and may never reach the scroll view.
        for field: CGEventField in [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2
        ] {
            event.setIntegerValueField(field, value: deltas.getIntegerValueField(field))
        }
        for field: CGEventField in [.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2] {
            event.setDoubleValueField(field, value: deltas.getDoubleValueField(field))
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        event.timestamp = DispatchTime.now().uptimeNanoseconds
        if simulate {
            switch phase {
            case .began:
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1)
            case .changed:
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
            case .momentum:
                event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
            case .ended:
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
                event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 3)
            case .plain:
                break
            }
        }
        eventPoster(event, pid)
    }

    private func launchpadIsActive(_ identity: AppIdentity) -> Bool {
        guard identity.executablePath.hasSuffix("/Dock.app/Contents/MacOS/Dock") else { return false }
        if #available(macOS 26.0, *) { return false }
        let now = CFAbsoluteTimeGetCurrent()
        if now - launchpadCache.at < 0.5 { return launchpadCache.active }
        var active = false
        if let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
            active = windows.contains { ($0[kCGWindowName as String] as? String) == "LPSpringboard" }
        }
        launchpadCache = (now, active)
        return active
    }

    private static func looksLikeTrackpad(_ event: CGEvent) -> Bool {
        let phased = event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0
            || event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0
            || event.getDoubleValueField(.scrollWheelEventScrollCount) != 0
        guard phased else { return false }
        let sourcePID = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        if sourcePID > 0,
           NSRunningApplication(processIdentifier: sourcePID)?.bundleIdentifier == "com.logitech.manager.daemon" {
            return false
        }
        return true
    }

    private static func remoteDesktopAlreadySmoothed(_ event: CGEvent) -> Bool {
        guard event.getDoubleValueField(.scrollWheelEventIsContinuous) == 1 else { return false }
        let sourcePID = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard sourcePID > 0, let app = NSRunningApplication(processIdentifier: sourcePID) else { return false }
        let remoteBundles: Set<String> = [
            "com.teamviewer.TeamViewer",
            "com.teamviewer.TeamViewerHost",
            "com.anydesk.anydesk",
            "com.parsec.www",
            "com.rustdesk.RustDesk",
            "com.microsoft.rdc.macos",
            "com.realvnc.vncviewer"
        ]
        if let bundleID = app.bundleIdentifier, remoteBundles.contains(bundleID) { return true }
        let path = app.executableURL?.path ?? ""
        return path.contains("screensharingd") || path.contains("ScreensharingAgent")
    }

    private static func identity(of event: CGEvent) -> AppIdentity {
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard pid > 1, let app = NSRunningApplication(processIdentifier: pid) else { return .unknown }
        return AppIdentity(
            bundleIdentifier: app.bundleIdentifier ?? "",
            bundlePath: app.bundleURL?.path ?? "",
            executablePath: app.executableURL?.path ?? ""
        )
    }

    private static func usableDelta(_ event: CGEvent, vertical: Bool) -> Double {
        let point: CGEventField = vertical ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2
        let fixed: CGEventField = vertical ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2
        let line: CGEventField = vertical ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
        let points = event.getDoubleValueField(point)
        if points != 0 { return points }
        let fixedPoints = event.getDoubleValueField(fixed)
        if fixedPoints != 0 { return fixedPoints }
        return Double(event.getIntegerValueField(line))
    }

    private static func write(_ event: CGEvent, plan: WheelPlan) {
        if plan.writeY {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(plan.passthroughY.rounded()))
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: plan.passthroughY)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: plan.passthroughY)
        }
        if plan.writeX {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(plan.passthroughX.rounded()))
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: plan.passthroughX)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: plan.passthroughX)
        }
    }
}

private enum PostedPhase {
    case plain, began, changed, momentum, ended
}
