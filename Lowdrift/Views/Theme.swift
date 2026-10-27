import LowdriftCore
import SwiftUI
import UIKit

/// Lowdrift's semantic colors. Values come from `Palette` (unit-tested for
/// contrast) and follow the system Light/Dark setting and Increase Contrast.
enum Theme {
    static let background = color(.background)
    static let surface = color(.surface)
    static let elevated = color(.elevated)
    static let primaryText = color(.primaryText)
    static let secondaryText = color(.secondaryText)
    static let accent = color(.accent)
    static let accentSurface = color(.accentSurface)
    static let border = color(.border)
    static let onAccent = color(.onAccent)

    static let cornerRadius: CGFloat = 18

    private static func color(_ role: Palette.Role) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = Palette.color(
                role,
                dark: traits.userInterfaceStyle == .dark,
                highContrast: traits.accessibilityContrast == .high
            )
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
}

/// A gentle press response for the large custom buttons.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
