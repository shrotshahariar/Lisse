import Cocoa

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}
func wheel(pid: pid_t = 4242, value: Int32 = 1) -> CGEvent {
    let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: value, wheel2: 0, wheel3: 0)!
    event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
    event.setIntegerValueField(.scrollWheelEventScrollCount, value: 0)
    event.location = CGPoint(x: 321, y: 654)
    event.flags = .maskControl
    return event
}
var settings = LisseSettings.standard
var now = 100.0
var permitted = true
var frames: [(CGEvent, pid_t)] = []
var engine: ScrollEngine!
engine = ScrollEngine(
    settings: { settings },
    postingAllowed: { permitted },
    // Simulate a display callback firing inside start, before it returns.
    frameStarter: { engine.displayFrame(); return true },
    eventPoster: { frames.append(($0, $1)) },
    clock: { now }
)
let original = wheel()
expect(engine.handle(type: .scrollWheel, event: original) == nil, "A deliverable smooth event should queue")
now += 1.0 / 60
engine.displayFrame()
expect(!frames.isEmpty, "An immediate zero-time callback must not erase queued input")
expect(frames[0].1 == 4242, "Frames must go to the original target process")
expect(frames[0].0.location == original.location, "Frames must preserve the original target location")
expect(frames[0].0.flags == original.flags, "Frames must preserve modifiers")
expect(NSEvent(cgEvent: frames[0].0)!.scrollingDeltaY < 0, "The replacement must contain a real nonzero delta")
expect(frames[0].0.getIntegerValueField(.eventTargetUnixProcessID) == 4242, "Frames must retain routing metadata")
let synthetic = frames[0].0
expect(engine.handle(type: .scrollWheel, event: synthetic) != nil, "Synthetic frames must bypass the smoother")

now += 2
for _ in 0..<480 { now += 1.0 / 120; engine.displayFrame() }
let sum = frames.reduce(0.0) { $0 + NSEvent(cgEvent: $1.0)!.scrollingDeltaY }
expect(abs(sum + 64.4) < 2, "Fractional deltas must accumulate instead of being discarded: \(sum)")
let settledCount = frames.count
engine.displayFrame()
expect(frames.count == settledCount, "A settled gesture must not keep posting")

// An old queued stop must not cancel the next gesture.
now += 1
_ = engine.handle(type: .scrollWheel, event: wheel())
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
let beforeNextFrame = frames.count
now += 1.0 / 60
engine.displayFrame()
expect(frames.count > beforeNextFrame, "A stale stop must not shut down a new gesture")

permitted = false
let untrusted = wheel()
expect(engine.handle(type: .scrollWheel, event: untrusted)?.takeUnretainedValue() === untrusted, "Lost posting permission must preserve the original event")
let deniedCount = frames.count
engine.displayFrame()
expect(frames.count == deniedCount, "Lost permission must clear pending frames")
permitted = true
let unknownTarget = wheel(pid: 0)
expect(engine.handle(type: .scrollWheel, event: unknownTarget)?.takeUnretainedValue() === unknownTarget, "Unknown targets must pass through")

let failedEngine = ScrollEngine(settings: { settings }, postingAllowed: { true }, frameStarter: { false }, eventPoster: { _, _ in fatalError("Failed frame source must never post") })
let untouched = wheel()
let originalDelta = untouched.getIntegerValueField(.scrollWheelEventDeltaAxis1)
expect(failedEngine.handle(type: .scrollWheel, event: untouched)?.takeUnretainedValue() === untouched, "Frame startup failure must preserve original input")
expect(untouched.getIntegerValueField(.scrollWheelEventDeltaAxis1) == originalDelta, "Fallback must not zero the original delta")
failedEngine.displayFrame()
settings.scroll.smooth = false
settings.scroll.reverse = false
let disabled = wheel()
expect(engine.handle(type: .scrollWheel, event: disabled)?.takeUnretainedValue() === disabled, "Disabled smoothing must pass through")

engine.stop()
failedEngine.stop()
// Timing must describe wall-clock motion, independent of refresh rate.
func delivered(after seconds: Double, hz: Double) -> Double {
    var buffer = SmoothingBuffer()
    buffer.absorb(y: 100, x: 0, speed: 1, amplification: 1)
    for _ in 0..<Int((seconds * hz).rounded()) {
        _ = buffer.advance(blend: ScrollCurve.frameBlend(duration: 4.8, elapsed: 1 / hz))
    }
    return buffer.deliveredY
}
for rate in [60.0, 100, 120, 144] {
    expect(abs(delivered(after: 0.5, hz: rate) - delivered(after: 0.5, hz: 60)) < 0.00001, "Glide duration must stay consistent at \(rate) Hz")
}
expect(ScrollCurve.approximateGlideTime(duration: 4.8) > ScrollCurve.approximateGlideTime(duration: 4.35) * 1.8, "Soft glide should have a meaningfully longer tail")
expect(ScrollCurve.frameBlend(duration: 5.2) > 0, "The glide must never stall at the upper limit")

var oldSettings = LisseSettings.standard
oldSettings.launchAtLogin = true
oldSettings.scroll.reverse = false
var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldSettings)) as! [String: Any]
legacyJSON.removeValue(forKey: "appearance")
legacyJSON.removeValue(forKey: "isPaused")
let migrated = try JSONDecoder().decode(LisseSettings.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
expect(migrated.launchAtLogin && !migrated.scroll.reverse, "Upgrading must preserve existing preferences")
expect(migrated.appearance == .standard && !migrated.isPaused, "New customization fields must have backward-compatible defaults")
var custom = migrated
custom.appearance.mode = .dark
custom.appearance.accentHex = "8462D5"
custom.isPaused = true
let decoded = try JSONDecoder().decode(LisseSettings.self, from: JSONEncoder().encode(custom))
expect(decoded == custom, "Theme, accent and pause controls must persist")
expect(ScrollResolver.resolve(custom, identity: .unknown) == nil, "Pause must bypass every scroll rule")
for preset in ScrollPreset.allCases {
    let applied = preset.applying(to: custom.scroll)
    expect(preset.matches(applied), "Preset matching must recognize \(preset.title)")
    expect(applied.reverse == custom.scroll.reverse, "Presets must preserve direction")
}
print("PASS: \(checks) scroll delivery checks; no event taps installed and no events posted to macOS")
