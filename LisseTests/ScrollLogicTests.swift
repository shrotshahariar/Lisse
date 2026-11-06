import XCTest
@testable import Lisse

final class ScrollLogicTests: XCTestCase {
    func testDurationBlendMatchesTheEasingCurve() {
        XCTAssertEqual(ScrollCurve.frameBlend(duration: 4.35), 0.085, accuracy: 0.0001)
        XCTAssertEqual(ScrollCurve.frameBlend(duration: ScrollCurve.simulateTrackpadDuration), 0.044, accuracy: 0.0001)
        XCTAssertGreaterThan(ScrollCurve.frameBlend(duration: 1), ScrollCurve.frameBlend(duration: 5))
    }

    func testStepRaisesAShortNotchAndLeavesALongOne() {
        XCTAssertEqual(ScrollPlanner.atLeastStep(4, step: 33.6), 33.6, accuracy: 0.0001)
        XCTAssertEqual(ScrollPlanner.atLeastStep(-2, step: 33.6), -33.6, accuracy: 0.0001)
        XCTAssertEqual(ScrollPlanner.atLeastStep(80, step: 33.6), 80, accuracy: 0.0001)
    }

    func testSpeedScalesTheBufferAndAReverseNotchStartsOver() {
        var buffer = SmoothingBuffer()
        buffer.absorb(y: 10, x: 0, speed: 2.7, amplification: 1)
        let first = buffer.advance(blend: 1)
        XCTAssertEqual(first.y, 27, accuracy: 0.0001)
        buffer.absorb(y: 10, x: 0, speed: 2.7, amplification: 1)
        buffer.absorb(y: -10, x: 0, speed: 2, amplification: 5)
        XCTAssertEqual(buffer.residual(), 100, accuracy: 0.0001)
    }

    func testReverseAndAxisSwapUseTheDestinationAxis() {
        let tuning = ScrollTuning.standard
        let plan = ScrollPlanner.plan(
            wheel: IncomingWheel(vertical: 12, horizontal: 0),
            tuning: tuning,
            accelerate: true,
            swapAxes: true,
            pauseSmoothing: false
        )
        XCTAssertEqual(plan.smoothY, 0, accuracy: 0.0001)
        XCTAssertLessThan(plan.smoothX, 0)
        XCTAssertEqual(plan.amplification, 5, accuracy: 0.0001)
        XCTAssertTrue(plan.consumeOriginal)
    }

    func testPauseKeepsDirectionButSkipsSmoothing() {
        var tuning = ScrollTuning.standard
        tuning.reverseVertical = true
        let plan = ScrollPlanner.plan(
            wheel: IncomingWheel(vertical: 8, horizontal: 0),
            tuning: tuning,
            accelerate: false,
            swapAxes: false,
            pauseSmoothing: true
        )
        XCTAssertEqual(plan.smoothY, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.passthroughY, -8, accuracy: 0.0001)
        XCTAssertFalse(plan.consumeOriginal)
        XCTAssertTrue(plan.writeY)
    }

    func testAllowlistMissLeavesTheEventUntouched() {
        var settings = LisseSettings.standard
        settings.exceptionsAreAllowlist = true
        settings.exceptions = [
            AppException(
                displayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                bundlePath: "/Applications/Safari.app",
                executablePath: "/Applications/Safari.app/Contents/MacOS/Safari"
            )
        ]
        let other = AppIdentity(bundleIdentifier: "com.example.Other", bundlePath: "/Applications/Other.app", executablePath: "")
        XCTAssertNil(ScrollResolver.resolve(settings, identity: other))
        let safari = AppIdentity(
            bundleIdentifier: "com.apple.Safari",
            bundlePath: "/Applications/Safari.app",
            executablePath: ""
        )
        XCTAssertEqual(ScrollResolver.resolve(settings, identity: safari), settings.scroll)
    }

    func testExceptionCanReplaceGlobalStepSpeedAndDuration() {
        var settings = LisseSettings.standard
        var custom = ScrollTuning.standard
        custom.step = 10
        custom.speed = 4
        custom.duration = 2
        settings.exceptions = [
            AppException(
                displayName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                bundlePath: "/System/Applications/Notes.app",
                executablePath: "",
                inherit: false,
                scroll: custom
            )
        ]
        let notes = AppIdentity(bundleIdentifier: "com.apple.Notes", bundlePath: "", executablePath: "")
        let resolved = ScrollResolver.resolve(settings, identity: notes)
        XCTAssertEqual(resolved?.step, 10)
        XCTAssertEqual(resolved?.speed, 4)
        XCTAssertEqual(resolved?.duration, 2)
    }

    func testSimulateTrackpadLocksDurationAndCanRestoreIt() {
        var tuning = ScrollTuning.standard
        tuning.duration = 2.5
        tuning = tuning.applyingSimulateTrackpad(true)
        XCTAssertTrue(tuning.simulateTrackpad)
        XCTAssertEqual(tuning.duration, ScrollCurve.simulateTrackpadDuration, accuracy: 0.0001)
        tuning = tuning.applyingSimulateTrackpad(false)
        XCTAssertFalse(tuning.simulateTrackpad)
        XCTAssertEqual(tuning.duration, 2.5, accuracy: 0.0001)
    }
}
