import XCTest

/// Acceptance checks for the one-screen experience. These launch the app with a
/// private settings domain and never press Play, so they need no audio hardware.
final class LowdriftUITests: XCTestCase {
    /// The six cards on a fresh install, A to Z.
    private let defaultVisible = ["basementAC", "bedroomFan", "boxFan", "deepDrift", "softFan", "towerFan"]
    private let defaultHidden = ["ceilingFan", "windowAC", "cabinAir", "deskFan"]

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
        for preset in defaultVisible {
            XCTAssertTrue(app.buttons["preset.\(preset)"].exists, "Missing card \(preset)")
        }
        for preset in defaultHidden {
            XCTAssertFalse(app.buttons["preset.\(preset)"].exists, "\(preset) is hidden until chosen in Settings")
        }
        // A to Z with no favorites: Basement AC top left, Bedroom Fan beside it.
        let first = app.buttons["preset.basementAC"].frame
        let second = app.buttons["preset.bedroomFan"].frame
        XCTAssertEqual(first.minY, second.minY, accuracy: 1)
        XCTAssertLessThan(first.minX, second.minX)
        XCTAssertTrue(app.buttons["settings"].exists)
        XCTAssertTrue(app.buttons["preset.basementAC"].isSelected)
        XCTAssertFalse(app.buttons["preset.softFan"].isSelected)
        XCTAssertTrue(app.buttons["customize"].exists)
    }

    func testSelectingASoundWhilePausedStaysPaused() {
        let app = launch(resetSettings: true)
        app.buttons["preset.towerFan"].tap()
        XCTAssertTrue(app.buttons["preset.towerFan"].isSelected)
        XCTAssertFalse(app.buttons["preset.basementAC"].isSelected)
        XCTAssertTrue(selectedSound(app).label.contains("Tower Fan"))
        XCTAssertTrue(selectedSound(app).label.contains("Smooth and balanced."))
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
        XCTAssertTrue(app.sliders["Flutter"].exists)
        XCTAssertTrue(app.sliders["Drift"].exists)
        XCTAssertEqual(app.sliders.count, 5, "Exactly five controls")
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

    // MARK: - Settings and favorites

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["settings"].tap()
        XCTAssertTrue(app.buttons["closeSettings"].waitForExistence(timeout: 5))
    }

    /// Settings → a row of the menu (Sounds or Legal).
    private func openSettings(_ app: XCUIApplication, row: String) {
        openSettings(app)
        let link = app.buttons["settings.\(row)"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
    }

    /// Flips a Settings switch. On recent iOS the row's own center is the label,
    /// so tap the switch itself.
    private func flip(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if inner.exists {
            inner.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
    }

    private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1"
    }

    func testSettingsChoosesSoundsAndFavoritesPinToTop() {
        var app = launch(resetSettings: true)
        openSettings(app, row: "sounds")

        let showCabinAir = app.switches["show.cabinAir"]
        XCTAssertTrue(showCabinAir.waitForExistence(timeout: 5))
        XCTAssertFalse(isOn(showCabinAir))
        XCTAssertTrue(isOn(app.switches["show.bedroomFan"]), "Bedroom Fan is shown by default")
        flip(showCabinAir)
        XCTAssertTrue(isOn(showCabinAir))

        // Favoriting a hidden sound also shows it.
        app.buttons["favorite.ceilingFan"].tap()
        XCTAssertTrue(isOn(app.switches["show.ceilingFan"]))

        flip(app.switches["show.softFan"])
        XCTAssertFalse(isOn(app.switches["show.softFan"]))
        app.buttons["closeSettings"].tap()

        XCTAssertTrue(app.buttons["preset.cabinAir"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["preset.softFan"].exists)
        assertPinnedFirst(app, favorite: "ceilingFan", next: "basementAC", below: "bedroomFan")

        // Everything is still there after a relaunch.
        app.terminate()
        app = launch(resetSettings: false)
        XCTAssertTrue(app.buttons["preset.cabinAir"].exists)
        XCTAssertFalse(app.buttons["preset.softFan"].exists)
        assertPinnedFirst(app, favorite: "ceilingFan", next: "basementAC", below: "bedroomFan")
    }

    func testLongPressFavoritesACard() {
        let app = launch(resetSettings: true)
        let tower = app.buttons["preset.towerFan"]
        tower.press(forDuration: 1.2)
        let add = app.buttons["Add to Favorites"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.buttons["preset.towerFan"].waitForExistence(timeout: 5))
        assertPinnedFirst(app, favorite: "towerFan", next: "basementAC", below: "bedroomFan")
        XCTAssertEqual(app.buttons["playPause"].label, "Play", "Favoriting never starts playback")
    }

    func testTermsAndPrivacyPolicyOpenFromSettings() {
        let app = launch(resetSettings: true)
        openSettings(app, row: "legal")

        XCTAssertTrue(app.buttons["termsOfService"].waitForExistence(timeout: 5))
        app.buttons["termsOfService"].tap()
        XCTAssertTrue(app.navigationBars["Terms of Service"].waitForExistence(timeout: 5))
        app.navigationBars["Terms of Service"].buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["privacyPolicy"].waitForExistence(timeout: 5))
        app.buttons["privacyPolicy"].tap()
        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No network access"].exists)
    }

    /// The favorite's card is top left with a heart, `next` beside it, and `below` on the next row.
    private func assertPinnedFirst(_ app: XCUIApplication, favorite: String, next: String, below: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let card = app.buttons["preset.\(favorite)"]
        XCTAssertTrue((card.value as? String)?.hasPrefix("Favorite") ?? false, "Heart shown", file: file, line: line)
        let first = card.frame
        let second = app.buttons["preset.\(next)"].frame
        let third = app.buttons["preset.\(below)"].frame
        XCTAssertEqual(first.minY, second.minY, accuracy: 1, file: file, line: line)
        XCTAssertLessThan(first.minX, second.minX, file: file, line: line)
        XCTAssertGreaterThan(third.minY, first.minY + 10, file: file, line: line)
    }
}
