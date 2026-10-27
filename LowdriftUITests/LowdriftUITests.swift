import XCTest

/// Acceptance checks for the one-screen experience. These launch the app with a
/// private settings domain and never press Play, so they need no audio hardware.
final class LowdriftUITests: XCTestCase {
    private let presets = ["softFan", "boxFan", "basementAC", "airVent", "towerFan", "deepDrift"]

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(resetSettings: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-LowdriftUITesting"] + (resetSettings ? ["-LowdriftResetSettings"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["playPause"].waitForExistence(timeout: 10))
        return app
    }

    /// The title and subtitle of the selected sound, read as one element.
    private func selectedSound(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["selectedSound"].firstMatch
    }

    func testFreshInstallOpensOnBasementACPaused() {
        let app = launch(resetSettings: true)
        XCTAssertEqual(app.buttons["playPause"].label, "Play", "Opening the app never starts playback")
        XCTAssertTrue(selectedSound(app).label.contains("Basement AC"))
        XCTAssertTrue(selectedSound(app).label.contains("Deep and enveloping."))
        for preset in presets {
            XCTAssertTrue(app.buttons["preset.\(preset)"].exists, "Missing card \(preset)")
        }
        XCTAssertTrue(app.buttons["preset.basementAC"].isSelected)
        XCTAssertFalse(app.buttons["preset.softFan"].isSelected)
        XCTAssertTrue(app.buttons["customize"].exists)
    }

    func testSelectingASoundWhilePausedStaysPaused() {
        let app = launch(resetSettings: true)
        app.buttons["preset.airVent"].tap()
        XCTAssertTrue(app.buttons["preset.airVent"].isSelected)
        XCTAssertFalse(app.buttons["preset.basementAC"].isSelected)
        XCTAssertTrue(selectedSound(app).label.contains("Air Vent"))
        XCTAssertTrue(selectedSound(app).label.contains("Steady room noise."))
        XCTAssertEqual(app.buttons["playPause"].label, "Play")
    }

    func testCustomizeSheetEditsPersistAndResetRestoresDefaults() {
        var app = launch(resetSettings: true)
        app.buttons["preset.towerFan"].tap()
        app.buttons["customize"].tap()

        let depth = app.sliders["Depth"]
        XCTAssertTrue(depth.waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["Airflow"].exists)
        XCTAssertTrue(app.sliders["Hum"].exists)
        XCTAssertEqual(app.sliders.count, 3, "Exactly three controls")
        XCTAssertFalse(app.buttons["reset"].isEnabled, "Nothing to reset yet")

        let original = depth.value as? String
        depth.adjust(toNormalizedSliderPosition: 0.05)
        let edited = depth.value as? String
        XCTAssertNotEqual(edited, original)
        XCTAssertTrue(app.buttons["reset"].isEnabled)
        app.buttons["close"].tap()

        // Relaunch: the same preset is selected, still paused, and the edit is kept.
        app.terminate()
        app = launch(resetSettings: false)
        XCTAssertTrue(app.buttons["preset.towerFan"].isSelected)
        XCTAssertEqual(app.buttons["playPause"].label, "Play")
        app.buttons["customize"].tap()
        XCTAssertTrue(app.sliders["Depth"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders["Depth"].value as? String, edited)

        app.buttons["reset"].tap()
        XCTAssertEqual(app.sliders["Depth"].value as? String, original)
        app.buttons["close"].tap()

        // Other presets were never touched.
        app.buttons["preset.softFan"].tap()
        app.buttons["customize"].tap()
        XCTAssertFalse(app.buttons["reset"].waitForExistence(timeout: 5) && app.buttons["reset"].isEnabled)
    }
}
