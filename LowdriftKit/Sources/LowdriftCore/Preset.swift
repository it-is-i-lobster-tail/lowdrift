import LowdriftDSP

/// The six built-in sounds, in the order they appear on the main screen
/// (two columns, three rows).
public enum Preset: String, CaseIterable, Identifiable, Sendable {
    case softFan
    case boxFan
    case basementAC
    case airVent
    case towerFan
    case deepDrift

    /// First-launch selection.
    public static let launchDefault: Preset = .basementAC

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .softFan: return "Soft Fan"
        case .boxFan: return "Box Fan"
        case .basementAC: return "Basement AC"
        case .airVent: return "Air Vent"
        case .towerFan: return "Tower Fan"
        case .deepDrift: return "Deep Drift"
        }
    }

    /// One-line description shown under the title of the selected sound.
    public var subtitle: String {
        switch self {
        case .softFan: return "A gentle, steady flow."
        case .boxFan: return "Classic and consistent."
        case .basementAC: return "Deep and enveloping."
        case .airVent: return "Steady room noise."
        case .towerFan: return "Smooth and balanced."
        case .deepDrift: return "Low and airy."
        }
    }

    /// Short descriptor shown on the preset card.
    public var cardDescription: String {
        switch self {
        case .softFan: return "Gentle"
        case .boxFan: return "Classic"
        case .basementAC: return "Deep, rumbling"
        case .airVent: return "Airy"
        case .towerFan: return "Balanced"
        case .deepDrift: return "Low, smooth"
        }
    }

    /// Shipping values of the three controls (0–100).
    public var defaultControls: SoundControls {
        switch self {
        case .softFan: return SoundControls(depth: 35, airflow: 35, hum: 10)
        case .boxFan: return SoundControls(depth: 55, airflow: 65, hum: 30)
        case .basementAC: return SoundControls(depth: 80, airflow: 70, hum: 35)
        case .airVent: return SoundControls(depth: 30, airflow: 60, hum: 10)
        case .towerFan: return SoundControls(depth: 45, airflow: 55, hum: 25)
        case .deepDrift: return SoundControls(depth: 90, airflow: 55, hum: 8)
        }
    }

    /// The engine voice that generates this preset.
    public var soundProfile: SoundProfile {
        switch self {
        case .softFan: return .softFan
        case .boxFan: return .boxFan
        case .basementAC: return .basementAC
        case .airVent: return .airVent
        case .towerFan: return .towerFan
        case .deepDrift: return .deepDrift
        }
    }
}

/// The three user-facing controls, each 0–100.
public struct SoundControls: Equatable, Sendable {
    public static let range: ClosedRange<Double> = 0 ... 100

    public var depth: Double { didSet { depth = Self.clamped(depth, fallback: oldValue) } }
    public var airflow: Double { didSet { airflow = Self.clamped(airflow, fallback: oldValue) } }
    public var hum: Double { didSet { hum = Self.clamped(hum, fallback: oldValue) } }

    public init(depth: Double, airflow: Double, hum: Double) {
        self.depth = Self.clamped(depth, fallback: 50)
        self.airflow = Self.clamped(airflow, fallback: 50)
        self.hum = Self.clamped(hum, fallback: 0)
    }

    /// True when every control is within half a step of `other`.
    public func isApproximatelyEqual(to other: SoundControls) -> Bool {
        abs(depth - other.depth) < 0.5 && abs(airflow - other.airflow) < 0.5 && abs(hum - other.hum) < 0.5
    }

    static func clamped(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
