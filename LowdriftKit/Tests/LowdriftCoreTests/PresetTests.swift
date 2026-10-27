import LowdriftCore
import LowdriftDSP
import XCTest

final class PresetTests: XCTestCase {
    func testShippingPresetsMatchTheSpecification() {
        let expected: [(Preset, String, String, SoundControls)] = [
            (.softFan, "Soft Fan", "A gentle, steady flow.", SoundControls(depth: 35, airflow: 35, hum: 10)),
            (.boxFan, "Box Fan", "Classic and consistent.", SoundControls(depth: 55, airflow: 65, hum: 30)),
            (.basementAC, "Basement AC", "Deep and enveloping.", SoundControls(depth: 80, airflow: 70, hum: 35)),
            (.airVent, "Air Vent", "Steady room noise.", SoundControls(depth: 30, airflow: 60, hum: 10)),
            (.towerFan, "Tower Fan", "Smooth and balanced.", SoundControls(depth: 45, airflow: 55, hum: 25)),
            (.deepDrift, "Deep Drift", "Low and airy.", SoundControls(depth: 90, airflow: 55, hum: 8)),
        ]
        XCTAssertEqual(Preset.allCases, expected.map(\.0), "Grid order")
        for (preset, name, subtitle, controls) in expected {
            XCTAssertEqual(preset.name, name)
            XCTAssertEqual(preset.subtitle, subtitle)
            XCTAssertEqual(preset.defaultControls, controls)
            XCTAssertFalse(preset.cardDescription.isEmpty)
        }
        XCTAssertEqual(Preset.launchDefault, .basementAC)
    }

    func testEveryPresetHasItsOwnVoice() {
        XCTAssertEqual(Set(Preset.allCases.map(\.soundProfile)).count, Preset.allCases.count)
    }
}
