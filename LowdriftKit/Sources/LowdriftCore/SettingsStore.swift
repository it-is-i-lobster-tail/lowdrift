import Foundation

/// The few key-value calls the settings store needs. `UserDefaults` conforms;
/// tests use an in-memory dictionary.
public protocol KeyValueStorage: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: KeyValueStorage {}

/// On-device settings: the last selected preset and each preset's three
/// control values. Nothing else is stored, and nothing leaves the device.
///
/// Missing, corrupt or out-of-range values fall back to the shipping defaults,
/// field by field, so a damaged entry can never break launch or playback.
public final class SettingsStore {
    public enum Key {
        public static let selectedPreset = "lowdrift.v1.selectedPreset"

        public static func controls(_ preset: Preset) -> String {
            "lowdrift.v1.controls.\(preset.rawValue)"
        }
    }

    private enum Field {
        static let depth = "depth"
        static let airflow = "airflow"
        static let hum = "hum"
    }

    private let storage: KeyValueStorage

    public init(storage: KeyValueStorage = UserDefaults.standard) {
        self.storage = storage
    }

    /// The preset to show at launch. Basement AC on first launch.
    public var selectedPreset: Preset {
        get {
            guard let raw = storage.object(forKey: Key.selectedPreset) as? String,
                  let preset = Preset(rawValue: raw)
            else { return .launchDefault }
            return preset
        }
        set { storage.set(newValue.rawValue, forKey: Key.selectedPreset) }
    }

    public func controls(for preset: Preset) -> SoundControls {
        let defaults = preset.defaultControls
        guard let stored = storage.object(forKey: Key.controls(preset)) as? [String: Any] else { return defaults }
        return SoundControls(
            depth: Self.validated(stored[Field.depth]) ?? defaults.depth,
            airflow: Self.validated(stored[Field.airflow]) ?? defaults.airflow,
            hum: Self.validated(stored[Field.hum]) ?? defaults.hum
        )
    }

    public func setControls(_ controls: SoundControls, for preset: Preset) {
        let values: [String: Double] = [
            Field.depth: controls.depth,
            Field.airflow: controls.airflow,
            Field.hum: controls.hum,
        ]
        storage.set(values, forKey: Key.controls(preset))
    }

    /// Restores one preset's shipping values; other presets are untouched.
    public func resetControls(for preset: Preset) {
        storage.removeObject(forKey: Key.controls(preset))
    }

    /// A stored number is accepted only if it is finite and within the control
    /// range (with a little tolerance for rounding); anything else is discarded.
    private static func validated(_ value: Any?) -> Double? {
        let number: Double
        switch value {
        case let v as Double: number = v
        case let v as Float: number = Double(v)
        case let v as Int: number = Double(v)
        case let v as NSNumber: number = v.doubleValue
        default: return nil
        }
        let range = SoundControls.range
        guard number.isFinite, number >= range.lowerBound - 0.5, number <= range.upperBound + 0.5 else { return nil }
        return min(max(number, range.lowerBound), range.upperBound)
    }
}
