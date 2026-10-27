import LowdriftCore
import XCTest

final class PaletteTests: XCTestCase {
    func testTokensMatchTheDesignSystem() {
        let light: [Palette.Role: UInt32] = [
            .background: 0xF5F8F7, .surface: 0xFFFFFF, .elevated: 0xE9F0EF, .primaryText: 0x182B33,
            .secondaryText: 0x526A72, .accent: 0x226F68, .accentSurface: 0xDAEEEA, .border: 0xD4E1DF,
        ]
        let dark: [Palette.Role: UInt32] = [
            .background: 0x101C26, .surface: 0x192A35, .elevated: 0x243944, .primaryText: 0xEDF4F2,
            .secondaryText: 0xA9BEC4, .accent: 0x9BD7CC, .accentSurface: 0x254A4A, .border: 0x35505C,
        ]
        for (role, hex) in light { XCTAssertEqual(Palette.color(role, dark: false).hex, hex, "\(role) light") }
        for (role, hex) in dark { XCTAssertEqual(Palette.color(role, dark: true).hex, hex, "\(role) dark") }
    }

    func testTextAndControlsMeetContrastGuidelines() {
        for dark in [false, true] {
            for highContrast in [false, true] {
                func ratio(_ a: Palette.Role, _ b: Palette.Role) -> Double {
                    Palette.color(a, dark: dark, highContrast: highContrast)
                        .contrastRatio(to: Palette.color(b, dark: dark, highContrast: highContrast))
                }
                let label = "dark: \(dark), high contrast: \(highContrast)"
                for surface in [Palette.Role.background, .surface, .elevated, .accentSurface] {
                    XCTAssertGreaterThanOrEqual(ratio(.primaryText, surface), 7, "Primary text on \(surface), \(label)")
                    XCTAssertGreaterThanOrEqual(ratio(.secondaryText, surface), 4.5, "Secondary text on \(surface), \(label)")
                    XCTAssertGreaterThanOrEqual(ratio(.accent, surface), 4.5, "Accent on \(surface), \(label)")
                }
                XCTAssertGreaterThanOrEqual(ratio(.onAccent, .accent), 4.5, "Play symbol, \(label)")
            }
        }
    }

    func testIncreaseContrastStrengthensBorders() {
        for dark in [false, true] {
            let regular = Palette.color(.border, dark: dark).contrastRatio(to: Palette.color(.surface, dark: dark))
            let strong = Palette.color(.border, dark: dark, highContrast: true)
                .contrastRatio(to: Palette.color(.surface, dark: dark, highContrast: true))
            XCTAssertGreaterThan(strong, regular)
            XCTAssertGreaterThanOrEqual(strong, 3, "Borders must be visible with Increase Contrast")
            XCTAssertGreaterThan(
                Palette.color(.secondaryText, dark: dark, highContrast: true).contrastRatio(to: Palette.color(.background, dark: dark)),
                Palette.color(.secondaryText, dark: dark).contrastRatio(to: Palette.color(.background, dark: dark))
            )
        }
    }

    func testContrastRatioMath() {
        XCTAssertEqual(RGBColor(hex: 0x000000).contrastRatio(to: RGBColor(hex: 0xFFFFFF)), 21, accuracy: 0.01)
        XCTAssertEqual(RGBColor(hex: 0x777777).contrastRatio(to: RGBColor(hex: 0x777777)), 1, accuracy: 1e-9)
    }
}
