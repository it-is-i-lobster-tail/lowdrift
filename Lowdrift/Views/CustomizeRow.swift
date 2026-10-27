import SwiftUI

/// Full-width row that opens the Customize sound sheet. No chevron: it opens a
/// sheet, not a new page.
struct CustomizeRow: View {
    let presetName: String
    let isCustomized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("Customize sound")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                if isCustomized {
                    Text("Customized")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Customize sound")
        .accessibilityValue(isCustomized ? "Customized" : "")
        .accessibilityHint("Adjust Depth, Airflow and Hum for \(presetName).")
        .accessibilityIdentifier("customize")
    }
}
