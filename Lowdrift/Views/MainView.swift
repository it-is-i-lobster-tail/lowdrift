import LowdriftCore
import SwiftUI

/// Lowdrift's one screen: wordmark, waves, the selected sound, Play/Pause, the
/// six sounds and the Customize sound row.
struct MainView: View {
    let controller: PlaybackController

    @State private var isCustomizing = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("lowdrift")
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityLabel("Lowdrift")
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)

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

                PresetGrid(selected: controller.selectedPreset) { preset in
                    controller.select(preset)
                }

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
    }
}
