import LowdriftCore
import SwiftUI

/// The two-column grid of the sounds chosen in Settings, favorites first (one
/// column at accessibility text sizes). Long-press a card to favorite it.
struct PresetGrid: View {
    let presets: [Preset]
    let favorites: Set<Preset>
    let selected: Preset
    let select: (Preset) -> Void
    let toggleFavorite: (Preset) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        VStack(spacing: 12) {
            ForEach(Array(stride(from: 0, to: presets.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(presets[start ..< min(start + columns, presets.count)]) { preset in
                        PresetCard(
                            preset: preset,
                            isSelected: preset == selected,
                            isFavorite: favorites.contains(preset),
                            action: { select(preset) },
                            toggleFavorite: { toggleFavorite(preset) }
                        )
                    }
                }
                // Cards in a row share the height of the tallest one.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct PresetCard: View {
    let preset: Preset
    let isSelected: Bool
    let isFavorite: Bool
    let action: () -> Void
    let toggleFavorite: () -> Void

    private var favoriteActionName: String {
        isFavorite ? "Remove from Favorites" : "Add to Favorites"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    WaveMotif(lines: preset.motif)
                        .frame(width: 44, height: 18)
                    Spacer(minLength: 8)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.bottom, 4)
                Text(preset.name)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(preset.cardDescription)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(isSelected ? Theme.accentSurface : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.border, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0 : 0.04), radius: 8, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            Button(action: toggleFavorite) {
                Label(favoriteActionName, systemImage: isFavorite ? "heart.slash" : "heart")
            }
        }
        .accessibilityLabel(preset.name)
        .accessibilityValue(isFavorite ? "Favorite, \(preset.cardDescription)" : preset.cardDescription)
        .accessibilityHint(isSelected ? "" : "Selects this sound.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: Text(favoriteActionName), toggleFavorite)
        .accessibilityIdentifier("preset.\(preset.rawValue)")
    }
}

extension Preset {
    /// Card glyph: long slow swells for deep sounds, short quick ripples for airy ones.
    var motif: [WaveLine] {
        switch self {
        case .softFan:
            return [WaveLine(baseline: 0.5, amplitude: 0.18, wavelength: 0.9),
                    WaveLine(baseline: 0.75, amplitude: 0.1, wavelength: 0.9, phase: 1.5)]
        case .boxFan:
            return [WaveLine(baseline: 0.45, amplitude: 0.26, wavelength: 0.5),
                    WaveLine(baseline: 0.75, amplitude: 0.14, wavelength: 0.5, phase: 1.2)]
        case .basementAC:
            return [WaveLine(baseline: 0.45, amplitude: 0.32, wavelength: 0.8),
                    WaveLine(baseline: 0.8, amplitude: 0.14, wavelength: 1.1, phase: 2)]
        case .towerFan:
            return [WaveLine(baseline: 0.45, amplitude: 0.22, wavelength: 0.42),
                    WaveLine(baseline: 0.75, amplitude: 0.12, wavelength: 0.6, phase: 2.4)]
        case .deepDrift:
            return [WaveLine(baseline: 0.5, amplitude: 0.3, wavelength: 1.3),
                    WaveLine(baseline: 0.82, amplitude: 0.12, wavelength: 1.6, phase: 2.8)]
        case .ceilingFan:
            return [WaveLine(baseline: 0.5, amplitude: 0.2, wavelength: 1.1),
                    WaveLine(baseline: 0.78, amplitude: 0.1, wavelength: 1.2, phase: 2.2)]
        case .windowAC:
            return [WaveLine(baseline: 0.45, amplitude: 0.24, wavelength: 0.6),
                    WaveLine(baseline: 0.78, amplitude: 0.16, wavelength: 0.45, phase: 0.8)]
        case .cabinAir:
            return [WaveLine(baseline: 0.48, amplitude: 0.22, wavelength: 1.0),
                    WaveLine(baseline: 0.78, amplitude: 0.16, wavelength: 1.0, phase: 1.6)]
        case .deskFan:
            return [WaveLine(baseline: 0.42, amplitude: 0.18, wavelength: 0.36),
                    WaveLine(baseline: 0.72, amplitude: 0.12, wavelength: 0.28, phase: 1.9)]
        case .bedroomFan:
            return [WaveLine(baseline: 0.48, amplitude: 0.26, wavelength: 0.75),
                    WaveLine(baseline: 0.8, amplitude: 0.1, wavelength: 0.7, phase: 2.6)]
        }
    }
}
