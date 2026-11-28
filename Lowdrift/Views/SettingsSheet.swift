import LowdriftCore
import SwiftUI

/// Native Settings sheet: a short grouped menu that leads to the sound list
/// (which sounds appear on the main screen, and favorites) and the legal pages.
/// Changes save automatically.
struct SettingsSheet: View {
    let library: SoundLibrary

    @Environment(\.dismiss) private var dismiss

    /// Closes the whole sheet from any page (a pushed page's own `dismiss` would only go back).
    private func close() { dismiss() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SoundsSettingsView(library: library, close: close)
                    } label: {
                        SettingsRowLabel(title: "Sounds", systemImage: "fan") {
                            Text("\(library.visible.count) shown")
                        }
                    }
                    .accessibilityIdentifier("settings.sounds")
                }

                Section {
                    NavigationLink {
                        LegalSettingsView(close: close)
                    } label: {
                        SettingsRowLabel(title: "Legal", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("settings.legal")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .closesSettings(close)
        }
        .tint(Theme.accent)
        .presentationDragIndicator(.visible)
    }

    /// "1.0.0 (12)": marketing version and build number.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return short }
        return "\(short) (\(build))"
    }
}

/// A menu row: a teal outline icon, the title, and an optional trailing value.
private struct SettingsRowLabel<Value: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let value: () -> Value

    init(title: String, systemImage: String, @ViewBuilder value: @escaping () -> Value) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            value()
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 6)
    }
}

extension SettingsRowLabel where Value == EmptyView {
    init(title: String, systemImage: String) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

/// Every sound A to Z: a switch to show it on the main screen and a heart to
/// pin it to the top.
private struct SoundsSettingsView: View {
    let library: SoundLibrary
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
                Text("Show on main screen")
            } footer: {
                Text("Turn on the sounds you want to see. Tap the heart to make a sound a favorite: favorites are pinned to the top, and the rest are sorted A to Z.")
            }
        }
        .navigationTitle("Sounds")
        .navigationBarTitleDisplayMode(.inline)
        .closesSettings(close)
    }

    private func change(_ body: () -> Void) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25), body)
    }
}

/// Terms of Service and Privacy Policy, both bundled with the app.
private struct LegalSettingsView: View {
    let close: () -> Void

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    LegalDocumentView(document: .termsOfService, close: close)
                } label: {
                    SettingsRowLabel(title: "Terms of Service", systemImage: "doc.plaintext")
                }
                .accessibilityIdentifier("termsOfService")

                NavigationLink {
                    LegalDocumentView(document: .privacyPolicy, close: close)
                } label: {
                    SettingsRowLabel(title: "Privacy Policy", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("privacyPolicy")
            } footer: {
                Text("Lowdrift collects no data and never connects to the internet.")
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
        .closesSettings(close)
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

extension View {
    /// The Close button at the top right of every Settings page.
    func closesSettings(_ close: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("closeSettings")
            }
        }
    }
}
