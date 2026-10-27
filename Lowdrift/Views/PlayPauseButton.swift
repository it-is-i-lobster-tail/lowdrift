import SwiftUI

/// The large round teal Play/Pause control.
struct PlayPauseButton: View {
    let isPlaying: Bool
    let presetName: String
    let action: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var scaledDiameter: CGFloat = 96

    private var diameter: CGFloat { min(max(scaledDiameter, 88), 132) }

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                // The play triangle looks centred when nudged right a little.
                .offset(x: isPlaying ? 0 : diameter * 0.03)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Theme.accent))
                .shadow(color: Theme.accent.opacity(0.28), radius: 18, y: 8)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: isPlaying)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityValue(presetName)
        .accessibilityIdentifier("playPause")
    }
}
