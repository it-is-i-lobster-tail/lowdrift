import LowdriftCore
import SwiftUI
import UIKit

/// Native sheet with the five sound controls for the selected preset. Changes
/// are heard immediately and saved automatically; there is no Save button.
struct CustomizeSheet: View {
    @Bindable var controller: PlaybackController

    @Environment(\.dismiss) private var dismiss

    private func editingChanged(_ isEditing: Bool) {
        if isEditing {
            controller.beginEditingControls()
        } else {
            controller.endEditingControls()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SoundSlider(
                        title: "Depth", low: "Light", high: "Deep",
                        value: $controller.depth, onEditingChanged: editingChanged
                    )
                    SoundSlider(
                        title: "Airflow", low: "Gentle", high: "Strong",
                        value: $controller.airflow, onEditingChanged: editingChanged
                    )
                    SoundSlider(
                        title: "Hum", low: "None", high: "More",
                        value: $controller.hum, onEditingChanged: editingChanged
                    )
                    SoundSlider(
                        title: "Flutter", low: "Smooth", high: "Choppy",
                        value: $controller.flutter, onEditingChanged: editingChanged
                    )
                    SoundSlider(
                        title: "Drift", low: "Steady", high: "Wandering",
                        value: $controller.drift, onEditingChanged: editingChanged
                    )

                    Button {
                        controller.resetToDefault()
                        UIAccessibility.post(notification: .announcement, argument: "\(controller.selectedPreset.name) restored to default")
                    } label: {
                        Label("Reset to default", systemImage: "arrow.counterclockwise")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Theme.accent)
                    .disabled(!controller.isCustomized)
                    .accessibilityHint("Restores all five controls for \(controller.selectedPreset.name) only.")
                    .accessibilityIdentifier("reset")
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .modifier(SheetBackground())
            .navigationTitle("Customize sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Customize sound")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text(controller.selectedPreset.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("close")
                }
            }
        }
        .tint(Theme.accent)
        // A drag cut short by the sheet closing still gets saved.
        .onDisappear { controller.endEditingControls() }
        // Opens full height so all five controls and Reset to default are in view.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// One control: name above, a native slider, and the two end words below.
private struct SoundSlider: View {
    let title: String
    let low: String
    let high: String
    @Binding var value: Double
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .accessibilityHidden(true)
            Slider(value: $value, in: SoundControls.range) {
                Text(title)
            } onEditingChanged: { isEditing in
                onEditingChanged(isEditing)
            }
            .accessibilityValue(spokenValue)
            HStack {
                Text(low)
                Spacer()
                Text(high)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
        }
    }

    /// Words rather than numbers at the ends; a percentage toward the far end otherwise.
    private var spokenValue: String {
        let percent = Int(value.rounded())
        if percent <= 0 { return low }
        if percent >= 100 { return high }
        return "\(percent) percent toward \(high)"
    }
}

/// Before iOS 26 the sheet uses Lowdrift's own background; on iOS 26 and later
/// the system's Liquid Glass sheet background is kept.
private struct SheetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else {
            content
                .background(Theme.background.ignoresSafeArea())
                .presentationBackground(Theme.background)
        }
    }
}
