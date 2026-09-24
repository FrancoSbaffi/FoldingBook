import Foundation
import FoldingBookCore

enum MotionPolicyTests {
    static func run() {
        precondition(!CaptureDemand.needsCapture(delta: 0, blur: true, warp: true))
        precondition(!CaptureDemand.needsCapture(delta: 0.002, blur: true, warp: true))
        precondition(CaptureDemand.needsCapture(delta: 0.01, blur: true, warp: false))
        precondition(CaptureDemand.needsCapture(delta: -0.01, blur: false, warp: true))
        precondition(!CaptureDemand.needsCapture(delta: 0.1, blur: false, warp: false))
        precondition(!CaptureDemand.needsCapture(delta: .nan, blur: true, warp: true))
        print("PASS: capture demand only while a visible effect is needed")

        XCTAssertEqual(EffectDefaults.activationAngle, 100)
        XCTAssertEqual(EffectDefaults.jitterTolerance, 0)
        precondition(AngleActivation.allows(angle: 100, limit: EffectDefaults.activationAngle, enabled: true))
        precondition(!AngleActivation.allows(angle: 100.01, limit: EffectDefaults.activationAngle, enabled: true))

        var unfiltered = LidMotionFilter()
        unfiltered.reset(to: 100)
        XCTAssertEqual(unfiltered.update(99.9, tolerance: EffectDefaults.jitterTolerance), 99.9)
        XCTAssertEqual(unfiltered.update(99.8, tolerance: EffectDefaults.jitterTolerance), 99.8)

        precondition(AngleActivation.allows(angle: 90, limit: 90, enabled: true))
        precondition(AngleActivation.allows(angle: 45, limit: 90, enabled: true))
        precondition(!AngleActivation.allows(angle: 90.01, limit: 90, enabled: true))
        precondition(AngleActivation.allows(angle: 120, limit: 90, enabled: false))
        precondition(!AngleActivation.allows(angle: .nan, limit: 90, enabled: false))

        var filter = LidMotionFilter()
        filter.reset(to: 110)
        for value in [109.0, 111, 108, 112, 109, 111] {
            XCTAssertEqual(filter.update(value, tolerance: 2), 110)
        }

        XCTAssertEqual(filter.update(107, tolerance: 2), 107)
        XCTAssertEqual(filter.update(106, tolerance: 1), 107)
        XCTAssertEqual(filter.update(105, tolerance: 1), 105)
        XCTAssertEqual(filter.update(104.5, tolerance: 0), 104.5)

        filter.reset(to: 90)
        for value in [90.0, 89, 90, 88, 89] {
            XCTAssertEqual(filter.update(value, tolerance: 2), 90)
        }
        XCTAssertEqual(filter.update(87, tolerance: 2), 87)
        precondition(!AngleActivation.allows(angle: 91, limit: 90, enabled: true))

        var safety = DisplaySafetyGate()
        precondition(!safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 0))
        precondition(safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 0.51))
        precondition(!safety.update(lidClosed: true, builtInAvailable: true, sensorAvailable: true, now: 1))
        precondition(safety.state == .closed)
        precondition(!safety.update(lidClosed: false, builtInAvailable: false, sensorAvailable: true, now: 2))
        precondition(safety.state == .noDisplay)
        precondition(!safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: false, now: 3))
        precondition(safety.state == .noSensor)
        precondition(!safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 4))
        precondition(!safety.update(lidClosed: false, builtInAvailable: false, sensorAvailable: true, now: 4.3))
        precondition(!safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 4.4))
        precondition(!safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 4.8))
        precondition(safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 4.91))
        safety.reset()
        precondition(!safety.update(lidClosed: false, builtInAvailable: true, sensorAvailable: true, now: 5))
        print("PASS: absolute activation, 0–2° jitter, slow movement, lid-close, external-only, sensor loss and stable recovery")
    }
}
