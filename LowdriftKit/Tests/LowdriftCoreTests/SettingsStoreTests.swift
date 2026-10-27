import Foundation
import LowdriftCore
import XCTest

final class InMemoryStorage: KeyValueStorage {
    var values: [String: Any] = [:]
    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    func removeObject(forKey defaultName: String) { values[defaultName] = nil }
}

final class SettingsStoreTests: XCTestCase {
    func testFirstLaunchSelectsBasementACWithShippingValues() {
        let store = SettingsStore(storage: InMemoryStorage())
        XCTAssertEqual(store.selectedPreset, .basementAC)
        for preset in Preset.allCases {
            XCTAssertEqual(store.controls(for: preset), preset.defaultControls)
        }
    }

    func testSelectionAndControlsRoundTrip() {
        let storage = InMemoryStorage()
        let store = SettingsStore(storage: storage)
        store.selectedPreset = .towerFan
        store.setControls(SoundControls(depth: 12, airflow: 88.5, hum: 0), for: .towerFan)

        let reopened = SettingsStore(storage: storage)
        XCTAssertEqual(reopened.selectedPreset, .towerFan)
        XCTAssertEqual(reopened.controls(for: .towerFan), SoundControls(depth: 12, airflow: 88.5, hum: 0))
    }

    func testEachPresetKeepsItsOwnValues() {
        let store = SettingsStore(storage: InMemoryStorage())
        store.setControls(SoundControls(depth: 1, airflow: 2, hum: 3), for: .softFan)
        store.setControls(SoundControls(depth: 97, airflow: 98, hum: 99), for: .deepDrift)
        XCTAssertEqual(store.controls(for: .softFan), SoundControls(depth: 1, airflow: 2, hum: 3))
        XCTAssertEqual(store.controls(for: .deepDrift), SoundControls(depth: 97, airflow: 98, hum: 99))
        XCTAssertEqual(store.controls(for: .boxFan), Preset.boxFan.defaultControls)
    }

    func testResetRestoresOnlyThatPreset() {
        let store = SettingsStore(storage: InMemoryStorage())
        store.setControls(SoundControls(depth: 5, airflow: 5, hum: 5), for: .airVent)
        store.setControls(SoundControls(depth: 6, airflow: 6, hum: 6), for: .boxFan)
        store.resetControls(for: .airVent)
        XCTAssertEqual(store.controls(for: .airVent), Preset.airVent.defaultControls)
        XCTAssertEqual(store.controls(for: .boxFan), SoundControls(depth: 6, airflow: 6, hum: 6))
    }

    func testCorruptValuesFallBackToDefaults() {
        let storage = InMemoryStorage()
        let store = SettingsStore(storage: storage)
        let defaults = Preset.basementAC.defaultControls

        storage.values[SettingsStore.Key.selectedPreset] = "ceilingFan"
        XCTAssertEqual(store.selectedPreset, .basementAC, "Unknown preset ids fall back to the launch default")
        storage.values[SettingsStore.Key.selectedPreset] = 42
        XCTAssertEqual(store.selectedPreset, .basementAC)

        let key = SettingsStore.Key.controls(.basementAC)
        storage.values[key] = "not a dictionary"
        XCTAssertEqual(store.controls(for: .basementAC), defaults)

        storage.values[key] = ["depth": Double.nan, "airflow": Double.infinity, "hum": -40.0]
        XCTAssertEqual(store.controls(for: .basementAC), defaults)

        // Valid fields survive; damaged ones fall back individually.
        storage.values[key] = ["depth": 20.0, "airflow": "loud", "hum": 400.0]
        XCTAssertEqual(store.controls(for: .basementAC), SoundControls(depth: 20, airflow: defaults.airflow, hum: defaults.hum))

        // Integers (e.g. written by an older build or by `defaults write`) are accepted.
        storage.values[key] = ["depth": 10, "airflow": 20, "hum": 30]
        XCTAssertEqual(store.controls(for: .basementAC), SoundControls(depth: 10, airflow: 20, hum: 30))

        // Tiny rounding outside the range is clamped rather than discarded.
        storage.values[key] = ["depth": 100.2, "airflow": -0.1, "hum": 50.0]
        XCTAssertEqual(store.controls(for: .basementAC), SoundControls(depth: 100, airflow: 0, hum: 50))
    }

    func testPersistsThroughUserDefaults() throws {
        let suite = "lowdrift.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(storage: defaults)
        store.selectedPreset = .deepDrift
        store.setControls(SoundControls(depth: 70, airflow: 40, hum: 20), for: .deepDrift)

        let reopened = SettingsStore(storage: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(reopened.selectedPreset, .deepDrift)
        XCTAssertEqual(reopened.controls(for: .deepDrift), SoundControls(depth: 70, airflow: 40, hum: 20))
        XCTAssertEqual(reopened.controls(for: .softFan), Preset.softFan.defaultControls)
    }

    func testSoundControlsClampAndRejectInvalidValues() {
        var controls = SoundControls(depth: .nan, airflow: 140, hum: -3)
        XCTAssertEqual(controls, SoundControls(depth: 50, airflow: 100, hum: 0))
        controls.depth = 30
        controls.depth = .infinity
        XCTAssertEqual(controls.depth, 30, "A non-finite edit keeps the previous value")
    }
}
