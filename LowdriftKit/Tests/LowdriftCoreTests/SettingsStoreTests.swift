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

    func testRemovedPresetFallsBackToLaunchDefault() {
        let storage = InMemoryStorage()
        storage.set("airVent", forKey: "lowdrift.v1.selectedPreset")
        XCTAssertEqual(SettingsStore(storage: storage).selectedPreset, Preset.launchDefault)
    }

    func testResetRestoresOnlyThatPreset() {
        let store = SettingsStore(storage: InMemoryStorage())
        store.setControls(SoundControls(depth: 5, airflow: 5, hum: 5), for: .towerFan)
        store.setControls(SoundControls(depth: 6, airflow: 6, hum: 6), for: .boxFan)
        store.resetControls(for: .towerFan)
        XCTAssertEqual(store.controls(for: .towerFan), Preset.towerFan.defaultControls)
        XCTAssertEqual(store.controls(for: .boxFan), SoundControls(depth: 6, airflow: 6, hum: 6))
    }

    func testCorruptValuesFallBackToDefaults() {
        let storage = InMemoryStorage()
        let store = SettingsStore(storage: storage)
        let defaults = Preset.basementAC.defaultControls

        storage.values[SettingsStore.Key.selectedPreset] = "jetEngine"
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

    func testFlutterAndDriftPersistAndOlderSavesKeepTheirSound() {
        let storage = InMemoryStorage()
        let store = SettingsStore(storage: storage)
        store.setControls(SoundControls(depth: 40, airflow: 60, hum: 10, flutter: 5, drift: 95), for: .bedroomFan)
        XCTAssertEqual(SettingsStore(storage: storage).controls(for: .bedroomFan),
                       SoundControls(depth: 40, airflow: 60, hum: 10, flutter: 5, drift: 95))

        // Saved by a build with only three controls: the new two start at their neutral 50.
        storage.values[SettingsStore.Key.controls(.boxFan)] = ["depth": 10.0, "airflow": 20.0, "hum": 30.0]
        let older = store.controls(for: .boxFan)
        XCTAssertEqual(older, SoundControls(depth: 10, airflow: 20, hum: 30))
        XCTAssertEqual(older.flutter, SoundControls.neutral)
        XCTAssertEqual(older.drift, SoundControls.neutral)

        storage.values[SettingsStore.Key.controls(.boxFan)] = ["depth": 10.0, "airflow": 20.0, "hum": 30.0,
                                                               "flutter": Double.nan, "drift": 300.0]
        XCTAssertEqual(store.controls(for: .boxFan), SoundControls(depth: 10, airflow: 20, hum: 30))
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
        var controls = SoundControls(depth: .nan, airflow: 140, hum: -3, flutter: .infinity, drift: -1)
        XCTAssertEqual(controls, SoundControls(depth: 50, airflow: 100, hum: 0, flutter: 50, drift: 0))
        controls.flutter = 200
        XCTAssertEqual(controls.flutter, 100)
        controls.depth = 30
        controls.depth = .infinity
        XCTAssertEqual(controls.depth, 30, "A non-finite edit keeps the previous value")
    }
}

final class SoundListSettingsTests: XCTestCase {
    func testDefaultsAreSixShownAndNoFavorites() {
        let store = SettingsStore(storage: InMemoryStorage())
        XCTAssertEqual(store.visiblePresets, Preset.defaultVisible)
        XCTAssertEqual(store.visiblePresets.count, 6)
        XCTAssertTrue(store.visiblePresets.contains(.bedroomFan))
        XCTAssertEqual(store.favoritePresets, [])
    }

    func testShownAndFavoritesRoundTripAsSoundNames() {
        let storage = InMemoryStorage()
        let store = SettingsStore(storage: storage)
        store.visiblePresets = [.windowAC, .bedroomFan]
        store.favoritePresets = [.windowAC]
        XCTAssertEqual(storage.values[SettingsStore.Key.visiblePresets] as? [String], ["windowAC", "bedroomFan"])

        let reopened = SettingsStore(storage: storage)
        XCTAssertEqual(reopened.visiblePresets, [.windowAC, .bedroomFan])
        XCTAssertEqual(reopened.favoritePresets, [.windowAC])
    }

    func testUpdatingKeepsTheSelectedSoundOnTheMainScreen() {
        // A version before sound visibility showed every sound: someone listening
        // to one outside the default six must still find its card after updating.
        let storage = InMemoryStorage()
        SettingsStore(storage: storage).selectedPreset = .ceilingFan
        let store = SettingsStore(storage: storage)
        XCTAssertEqual(store.visiblePresets, Preset.defaultVisible.union([.ceilingFan]))

        // A saved choice is used as is, even if it leaves the selection out.
        store.visiblePresets = [.boxFan]
        XCTAssertEqual(SettingsStore(storage: storage).visiblePresets, [.boxFan])
    }
}
