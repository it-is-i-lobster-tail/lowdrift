import Foundation
import Observation

/// Which sounds appear on the main screen, which are favorites, and the order
/// they are shown in. Every change is saved on the device straight away.
///
/// Two rules keep the screen sensible:
/// - A favorite is always shown: favoriting a hidden sound shows it, and hiding
///   a favorite also unfavorites it.
/// - At least one sound stays on the main screen.
@MainActor
@Observable
public final class SoundLibrary {
    public private(set) var visible: Set<Preset>
    public private(set) var favorites: Set<Preset>

    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
        let visible = store.visiblePresets
        let favorites = store.favoritePresets
        self.favorites = favorites
        // Repair a saved state that broke the "favorites are shown" rule.
        self.visible = visible.union(favorites)
    }

    /// The main screen's cards: favorites first, then the rest, each group A to Z.
    public var mainScreenPresets: [Preset] {
        Preset.alphabetical(visible.intersection(favorites))
            + Preset.alphabetical(visible.subtracting(favorites))
    }

    /// Every sound A to Z, for the list in Settings.
    public var allPresets: [Preset] { Preset.alphabetical(Preset.allCases) }

    public func isVisible(_ preset: Preset) -> Bool { visible.contains(preset) }

    public func isFavorite(_ preset: Preset) -> Bool { favorites.contains(preset) }

    /// False for the last sound left on the main screen.
    public func canHide(_ preset: Preset) -> Bool {
        !(visible.count == 1 && visible.contains(preset))
    }

    public func setVisible(_ preset: Preset, _ isVisible: Bool) {
        if isVisible {
            guard !visible.contains(preset) else { return }
            visible.insert(preset)
        } else {
            guard visible.contains(preset), canHide(preset) else { return }
            visible.remove(preset)
            if favorites.remove(preset) != nil { store.favoritePresets = favorites }
        }
        store.visiblePresets = visible
    }

    public func setFavorite(_ preset: Preset, _ isFavorite: Bool) {
        if isFavorite {
            guard !favorites.contains(preset) else { return }
            favorites.insert(preset)
            if !visible.contains(preset) {
                visible.insert(preset)
                store.visiblePresets = visible
            }
        } else {
            guard favorites.remove(preset) != nil else { return }
        }
        store.favoritePresets = favorites
    }

    public func toggleFavorite(_ preset: Preset) {
        setFavorite(preset, !isFavorite(preset))
    }
}
