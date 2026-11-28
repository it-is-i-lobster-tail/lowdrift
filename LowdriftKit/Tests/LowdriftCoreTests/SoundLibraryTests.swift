import LowdriftCore
import XCTest

@MainActor
final class SoundLibraryTests: XCTestCase {
    private var storage = InMemoryStorage()

    override func setUp() async throws {
        storage = InMemoryStorage()
    }

    private func makeLibrary() -> SoundLibrary {
        SoundLibrary(store: SettingsStore(storage: storage))
    }

    nonisolated func testFreshInstallShowsSixDefaultSoundsIncludingBedroomFan() {
        onMainActor {
            let library = makeLibrary()
            XCTAssertEqual(library.visible.count, 6)
            XCTAssertTrue(library.isVisible(.bedroomFan))
            XCTAssertTrue(library.isVisible(Preset.launchDefault), "The first-launch sound has a card")
            XCTAssertEqual(library.favorites, [])
            XCTAssertEqual(library.mainScreenPresets,
                           [.basementAC, .bedroomFan, .boxFan, .deepDrift, .softFan, .towerFan])
        }
    }

    nonisolated func testFavoritesPinToTopAndTheRestAreAlphabetical() {
        onMainActor {
            let library = makeLibrary()
            library.setFavorite(.towerFan, true)
            library.setFavorite(.boxFan, true)
            XCTAssertEqual(library.mainScreenPresets,
                           [.boxFan, .towerFan, .basementAC, .bedroomFan, .deepDrift, .softFan])
            library.toggleFavorite(.boxFan)
            XCTAssertEqual(library.mainScreenPresets,
                           [.towerFan, .basementAC, .bedroomFan, .boxFan, .deepDrift, .softFan])
        }
    }

    nonisolated func testAllSoundsListedAlphabetically() {
        onMainActor {
            XCTAssertEqual(makeLibrary().allPresets.map(\.name), [
                "Basement AC", "Bedroom Fan", "Box Fan", "Cabin Air", "Ceiling Fan",
                "Deep Drift", "Desk Fan", "Soft Fan", "Tower Fan", "Window AC",
            ])
        }
    }

    nonisolated func testShowingAndHidingPersist() {
        onMainActor {
            let library = makeLibrary()
            library.setVisible(.windowAC, true)
            library.setVisible(.softFan, false)
            library.setFavorite(.cabinAir, true)

            let reopened = makeLibrary()
            XCTAssertTrue(reopened.isVisible(.windowAC))
            XCTAssertFalse(reopened.isVisible(.softFan))
            XCTAssertTrue(reopened.isFavorite(.cabinAir))
            XCTAssertEqual(reopened.mainScreenPresets,
                           [.cabinAir, .basementAC, .bedroomFan, .boxFan, .deepDrift, .towerFan, .windowAC])
        }
    }

    nonisolated func testFavoritingAHiddenSoundShowsIt() {
        onMainActor {
            let library = makeLibrary()
            XCTAssertFalse(library.isVisible(.deskFan))
            library.setFavorite(.deskFan, true)
            XCTAssertTrue(library.isVisible(.deskFan))
            XCTAssertEqual(library.mainScreenPresets.first, .deskFan)
            XCTAssertTrue(makeLibrary().isVisible(.deskFan), "Saved too")
        }
    }

    nonisolated func testHidingAFavoriteUnfavoritesIt() {
        onMainActor {
            let library = makeLibrary()
            library.setFavorite(.boxFan, true)
            library.setVisible(.boxFan, false)
            XCTAssertFalse(library.isVisible(.boxFan))
            XCTAssertFalse(library.isFavorite(.boxFan))
            XCTAssertFalse(makeLibrary().isFavorite(.boxFan), "Saved too")
        }
    }

    nonisolated func testLastVisibleSoundCannotBeHidden() {
        onMainActor {
            let library = makeLibrary()
            for preset in Preset.allCases where preset != .bedroomFan {
                library.setVisible(preset, false)
            }
            XCTAssertEqual(library.visible, [.bedroomFan])
            XCTAssertFalse(library.canHide(.bedroomFan))
            library.setVisible(.bedroomFan, false)
            XCTAssertEqual(library.mainScreenPresets, [.bedroomFan])
            XCTAssertEqual(makeLibrary().visible, [.bedroomFan])
        }
    }

    nonisolated func testDamagedOrEmptySavedListsFallBack() {
        onMainActor {
            storage.set([String](), forKey: SettingsStore.Key.visiblePresets)
            XCTAssertEqual(makeLibrary().visible, Preset.defaultVisible, "An empty screen is never restored")

            storage.set(["airVent", "notASound", 7], forKey: SettingsStore.Key.visiblePresets)
            XCTAssertEqual(makeLibrary().visible, Preset.defaultVisible)

            storage.set(["airVent", "windowAC"], forKey: SettingsStore.Key.visiblePresets)
            XCTAssertEqual(makeLibrary().visible, [.windowAC], "Removed sounds are dropped")

            storage.set("deskFan", forKey: SettingsStore.Key.favoritePresets)
            XCTAssertEqual(makeLibrary().favorites, [], "Wrong type is ignored")
        }
    }

    nonisolated func testSavedFavoriteThatWasHiddenIsShown() {
        onMainActor {
            storage.set(["softFan"], forKey: SettingsStore.Key.visiblePresets)
            storage.set(["deskFan"], forKey: SettingsStore.Key.favoritePresets)
            XCTAssertEqual(makeLibrary().mainScreenPresets, [.deskFan, .softFan])
        }
    }

    nonisolated func testSelectedSoundAlwaysHasACard() {
        onMainActor {
            let library = makeLibrary()
            XCTAssertFalse(library.isVisible(.ceilingFan))
            // Chosen through Shortcuts while hidden: shown in A to Z order.
            XCTAssertEqual(library.mainScreenPresets(selected: .ceilingFan),
                           [.basementAC, .bedroomFan, .boxFan, .ceilingFan, .deepDrift, .softFan, .towerFan])
            XCTAssertFalse(library.isVisible(.ceilingFan), "Showing it for now doesn't change the saved list")

            // Hidden in Settings while selected: it keeps its card until another is chosen.
            library.setVisible(.boxFan, false)
            XCTAssertTrue(library.mainScreenPresets(selected: .boxFan).contains(.boxFan))
            XCTAssertFalse(library.mainScreenPresets(selected: .softFan).contains(.boxFan))

            // A visible selection is not listed twice; a favorite stays pinned.
            library.setFavorite(.softFan, true)
            XCTAssertEqual(library.mainScreenPresets(selected: .softFan),
                           [.softFan, .basementAC, .bedroomFan, .deepDrift, .towerFan])
        }
    }
}
