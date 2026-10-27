import Foundation

/// An sRGB color from a hex token.
public struct RGBColor: Equatable, Hashable, Sendable {
    public let hex: UInt32

    public init(hex: UInt32) {
        self.hex = hex & 0xFF_FFFF
    }

    public var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(hex & 0xFF) / 255 }

    /// WCAG 2 relative luminance.
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, 1…21.
    public func contrastRatio(to other: RGBColor) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Lowdrift's semantic colors. Light mode is the primary reference; dark mode is
/// midnight blue. High-contrast variants are used when Increase Contrast is on.
public enum Palette {
    public enum Role: CaseIterable, Sendable {
        case background
        case surface
        case elevated
        case primaryText
        case secondaryText
        case accent
        case accentSurface
        case border
        /// Glyphs drawn on an accent fill (the Play/Pause symbol).
        case onAccent
    }

    public static func color(_ role: Role, dark: Bool, highContrast: Bool = false) -> RGBColor {
        if highContrast, let strong = highContrastColor(role, dark: dark) {
            return strong
        }
        return RGBColor(hex: dark ? darkHex(role) : lightHex(role))
    }

    private static func lightHex(_ role: Role) -> UInt32 {
        switch role {
        case .background: return 0xF5F8F7
        case .surface: return 0xFFFFFF
        case .elevated: return 0xE9F0EF
        case .primaryText: return 0x182B33
        case .secondaryText: return 0x526A72
        case .accent: return 0x226F68
        case .accentSurface: return 0xDAEEEA
        case .border: return 0xD4E1DF
        case .onAccent: return 0xFFFFFF
        }
    }

    private static func darkHex(_ role: Role) -> UInt32 {
        switch role {
        case .background: return 0x101C26
        case .surface: return 0x192A35
        case .elevated: return 0x243944
        case .primaryText: return 0xEDF4F2
        case .secondaryText: return 0xA9BEC4
        case .accent: return 0x9BD7CC
        case .accentSurface: return 0x254A4A
        case .border: return 0x35505C
        case .onAccent: return 0x101C26
        }
    }

    /// Stronger text, accent and borders for Increase Contrast; other roles keep
    /// their regular values.
    private static func highContrastColor(_ role: Role, dark: Bool) -> RGBColor? {
        switch (role, dark) {
        case (.secondaryText, false): return RGBColor(hex: 0x3B5158)
        case (.secondaryText, true): return RGBColor(hex: 0xCAD9DD)
        case (.accent, false): return RGBColor(hex: 0x195650)
        case (.accent, true): return RGBColor(hex: 0xB6E6DD)
        case (.border, false): return RGBColor(hex: 0x7F9794)
        case (.border, true): return RGBColor(hex: 0x7896A1)
        default: return nil
        }
    }
}
