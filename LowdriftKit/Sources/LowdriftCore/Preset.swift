import LowdriftDSP

/// The built-in sounds, in the order they appear on the main screen
/// (two columns, five rows).
public enum Preset: String, CaseIterable, Identifiable, Sendable {
    case softFan
    case boxFan
    case basementAC
    case airVent
    case towerFan
    case deepDrift
    case ceilingFan
    case windowAC
    case cabinAir
    case deskFan
    case bedroomFan

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
        case .ceilingFan: return "Ceiling Fan"
        case .windowAC: return "Window AC"
        case .cabinAir: return "Cabin Air"
        case .deskFan: return "Desk Fan"
        case .bedroomFan: return "Bedroom Fan"
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
        case .ceilingFan: return "Slow, lazy circles of air."
        case .windowAC: return "A steady blower and low hum."
        case .cabinAir: return "A wide, even roar."
        case .deskFan: return "A small fan close by."
        case .bedroomFan: return "A warm, familiar whoosh."
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
        case .ceilingFan: return "Slow, soft"
        case .windowAC: return "Steady hum"
        case .cabinAir: return "Smooth roar"
        case .deskFan: return "Close, bright"
        case .bedroomFan: return "Warm, low"
        }
    }

    /// Shipping values of Depth, Airflow and Hum (0–100); Flutter and Drift start at 50.
    public var defaultControls: SoundControls {
        switch self {
        case .softFan: return SoundControls(depth: 35, airflow: 35, hum: 10)
        case .boxFan: return SoundControls(depth: 55, airflow: 65, hum: 30)
        case .basementAC: return SoundControls(depth: 80, airflow: 70, hum: 35)
        case .airVent: return SoundControls(depth: 30, airflow: 60, hum: 10)
        case .towerFan: return SoundControls(depth: 45, airflow: 55, hum: 25)
        case .deepDrift: return SoundControls(depth: 90, airflow: 55, hum: 8)
        case .ceilingFan: return SoundControls(depth: 50, airflow: 40, hum: 6)
        case .windowAC: return SoundControls(depth: 55, airflow: 60, hum: 40)
        case .cabinAir: return SoundControls(depth: 65, airflow: 60, hum: 12)
        case .deskFan: return SoundControls(depth: 35, airflow: 55, hum: 25)
        case .bedroomFan: return SoundControls(depth: 50, airflow: 50, hum: 0)
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
        case .ceilingFan: return .ceilingFan
        case .windowAC: return .windowAC
        case .cabinAir: return .cabinAir
        case .deskFan: return .deskFan
        case .bedroomFan: return .bedroomFan
        }
    }
}

/// The five user-facing controls, each 0–100.
///
/// Flutter and Drift sit at 50 for every sound by default, which means "this
/// sound's own amount"; the sound's identity lives in its character, not here.
public struct SoundControls: Equatable, Sendable {
    public static let range: ClosedRange<Double> = 0 ... 100
    /// Default position of Flutter and Drift.
    public static let neutral: Double = 50

    public var depth: Double { didSet { depth = Self.clamped(depth, fallback: oldValue) } }
    public var airflow: Double { didSet { airflow = Self.clamped(airflow, fallback: oldValue) } }
    public var hum: Double { didSet { hum = Self.clamped(hum, fallback: oldValue) } }
    /// Blade texture: Smooth ↔ Choppy.
    public var flutter: Double { didSet { flutter = Self.clamped(flutter, fallback: oldValue) } }
    /// Slow natural variation: Steady ↔ Wandering.
    public var drift: Double { didSet { drift = Self.clamped(drift, fallback: oldValue) } }

    public init(depth: Double, airflow: Double, hum: Double, flutter: Double = neutral, drift: Double = neutral) {
        self.depth = Self.clamped(depth, fallback: 50)
        self.airflow = Self.clamped(airflow, fallback: 50)
        self.hum = Self.clamped(hum, fallback: 0)
        self.flutter = Self.clamped(flutter, fallback: Self.neutral)
        self.drift = Self.clamped(drift, fallback: Self.neutral)
    }

    /// True when every control is within half a step of `other`.
    public func isApproximatelyEqual(to other: SoundControls) -> Bool {
        abs(depth - other.depth) < 0.5 && abs(airflow - other.airflow) < 0.5 && abs(hum - other.hum) < 0.5
            && abs(flutter - other.flutter) < 0.5 && abs(drift - other.drift) < 0.5
    }

    static func clamped(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
