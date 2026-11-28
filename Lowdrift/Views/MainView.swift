import LowdriftCore
import SwiftUI

/// Lowdrift's one screen: wordmark and Settings, waves, the selected sound,
/// Play/Pause, the chosen sound cards and the Customize sound row.
struct MainView: View {
    let controller: PlaybackController
    let library: SoundLibrary

    @State private var isCustomizing = false
    @State private var isShowingSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("lowdrift")
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityLabel("Lowdrift")
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.trailing, -10)
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings")
                }
                .padding(.top, 2)

                WaveDecoration(isAnimating: controller.isPlaying && scenePhase == .active && !reduceMotion)
                    .frame(height: 112)
                    .padding(.horizontal, -20)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(controller.selectedPreset.name)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(controller.selectedPreset.subtitle)
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("selectedSound")

                PlayPauseButton(isPlaying: controller.isPlaying, presetName: controller.selectedPreset.name) {
                    controller.togglePlayback()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                if let failure = controller.failure {
                    FailureBanner(message: failure.message) {
                        controller.retry()
                    }
                    .padding(.top, 20)
                    .transition(.opacity)
                }

                Text("Sounds")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 36)
                    .padding(.bottom, 12)

                PresetGrid(
                    presets: library.mainScreenPresets(selected: controller.selectedPreset),
                    favorites: library.favorites,
                    selected: controller.selectedPreset,
                    select: { controller.select($0) },
                    toggleFavorite: { preset in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                            library.toggleFavorite(preset)
                        }
                    }
                )

                CustomizeRow(presetName: controller.selectedPreset.name, isCustomized: controller.isCustomized) {
                    isCustomizing = true
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: controller.failure)
        .sheet(isPresented: $isCustomizing) {
            CustomizeSheet(controller: controller)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(library: library)
        }
    }
}
