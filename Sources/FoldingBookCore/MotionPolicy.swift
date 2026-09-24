import Foundation

/// Filter small hinge vibrations while tracking accumulated lid motion.
public struct LidMotionFilter {
    public private(set) var angle: Double?

    public init() {}

    public mutating func reset(to angle: Double) {
        self.angle = angle
    }

    public mutating func update(_ sample: Double, tolerance: Double) -> Double {
        guard sample.isFinite else { return angle ?? 0 }
        if angle == nil || abs(sample - angle!) > max(0, tolerance) {
            angle = sample
        }
        return angle!
    }
}

/// Gate execution based on the user's maximum activation angle.
public enum AngleActivation {
    public static func allows(angle: Double, limit: Double, enabled: Bool) -> Bool {
        angle.isFinite && (!enabled || angle <= limit)
    }
}

/// Determine if the current angular deflection requires screen capture and rendering.
public enum CaptureDemand {
    public static func needsCapture(delta: Float, blur: Bool, warp: Bool) -> Bool {
        delta.isFinite && abs(delta) > 0.002 && (blur || warp)
    }
}

/// Handles safety states when lid is closed, display is off, or recovering from sleep.
public struct DisplaySafetyGate {
    public enum State: String {
        case closed = "Paused · Lid closed"
        case noDisplay = "Paused · Built-in display unavailable"
        case noSensor = "Paused · Lid angle sensor unavailable"
        case recovering = "Waiting for built-in display…"
        case ready = "Ready"
    }

    public private(set) var state: State = .recovering
    public var recoveryDelay: TimeInterval = 0.5
    private var readySince: TimeInterval?

    public init() {}

    public mutating func reset() {
        readySince = nil
        state = .recovering
    }

    @discardableResult
    public mutating func update(lidClosed: Bool, builtInAvailable: Bool, sensorAvailable: Bool, now: TimeInterval) -> Bool {
        if lidClosed {
            state = .closed
        } else if !builtInAvailable {
            state = .noDisplay
        } else if !sensorAvailable {
            state = .noSensor
        } else {
            if readySince == nil { readySince = now }
            state = (now - readySince!) >= recoveryDelay ? .ready : .recovering
            return state == .ready
        }
        readySince = nil
        return false
    }
}
