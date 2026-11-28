import LowdriftCore
import SwiftUI

/// Native Settings sheet: which sounds appear on the main screen, favorites,
/// and the Terms of Service and Privacy Policy. Changes save automatically.
struct SettingsSheet: View {
    let library: SoundLibrary

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(library.allPresets) { preset in
                        SoundRow(
                            preset: preset,
                            isFavorite: library.isFavorite(preset),
                            isVisible: Binding(
                                get: { library.isVisible(preset) },
                                set: { shown in change { library.setVisible(preset, shown) } }
                            ),
                            canHide: library.canHide(preset),
                            toggleFavorite: { change { library.toggleFavorite(preset) } }
                        )
                    }
                } header: {
                    Text("Sounds on main screen")
                } footer: {
                    Text("Turn on the sounds you want to see. Tap the heart to make a sound a favorite: favorites are pinned to the top, and the rest are sorted A to Z.")
                }

                Section("About") {
                    NavigationLink {
                        LegalDocumentView(document: .termsOfService)
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("termsOfService")

                    NavigationLink {
                        LegalDocumentView(document: .privacyPolicy)
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("privacyPolicy")

                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("closeSettings")
                }
            }
        }
        .tint(Theme.accent)
        .presentationDragIndicator(.visible)
    }

    private func change(_ body: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25), body)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// One sound: a favorite heart, its name, and a switch for the main screen.
private struct SoundRow: View {
    let preset: Preset
    let isFavorite: Bool
    @Binding var isVisible: Bool
    let canHide: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isFavorite ? Theme.accent : Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.leading, -10)
            .accessibilityLabel("Favorite \(preset.name)")
            .accessibilityValue(isFavorite ? "On" : "Off")
            .accessibilityAddTraits(isFavorite ? .isSelected : [])
            .accessibilityHint(isFavorite ? "Unpins it from the top." : "Pins it to the top of the main screen.")
            .accessibilityIdentifier("favorite.\(preset.rawValue)")

            Toggle(isOn: $isVisible) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .foregroundStyle(Theme.primaryText)
                    Text(preset.cardDescription)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)
            .disabled(isVisible && !canHide)
            .accessibilityLabel("Show \(preset.name) on main screen")
            .accessibilityHint(isVisible && !canHide ? "At least one sound stays on the main screen." : "")
            .accessibilityIdentifier("show.\(preset.rawValue)")
        }
    }
}
