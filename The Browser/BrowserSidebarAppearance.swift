import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BrowserSidebarAppearance: Equatable {
    var background: Color
    var primary: Color
    var secondary: Color
    var controlTint: Color

    static let `default` = BrowserSidebarAppearance(
        background: Color.browserSidebarBackground,
        primary: Color.primary,
        secondary: Color.primary.opacity(0.65),
        controlTint: Color.browserSidebarBackground.opacity(0.75)
    )
}

#if os(macOS)
extension BrowserSidebarAppearance {
    static func make(from color: NSColor) -> BrowserSidebarAppearance {
        let working = color.usingColorSpace(.extendedSRGB) ?? color.usingColorSpace(.sRGB) ?? color
        let luminance = working.relativeLuminance

        let primaryBase: NSColor = luminance > 0.6
            ? NSColor.black.withAlphaComponent(0.85)
            : NSColor.white.withAlphaComponent(0.95)

        let secondaryBase = primaryBase.withAlphaComponent(primaryBase.alphaComponent * 0.65)

        let controlFraction: CGFloat = luminance > 0.6 ? 0.18 : 0.28
        let controlColor = working.blended(withFraction: controlFraction, of: .white) ?? working
        let controlTint = controlColor.withAlphaComponent(0.58)

        return BrowserSidebarAppearance(
            background: Color(nsColor: working.withAlphaComponent(1)),
            primary: Color(nsColor: primaryBase),
            secondary: Color(nsColor: secondaryBase),
            controlTint: Color(nsColor: controlTint)
        )
    }
}

private extension NSColor {
    var relativeLuminance: CGFloat {
        let converted = usingColorSpace(.extendedSRGB) ?? usingColorSpace(.sRGB) ?? self
        let r = converted.redComponent
        let g = converted.greenComponent
        let b = converted.blueComponent

        func transform(_ value: CGFloat) -> CGFloat {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        let linearR = transform(r)
        let linearG = transform(g)
        let linearB = transform(b)

        return 0.2126 * linearR + 0.7152 * linearG + 0.0722 * linearB
    }
}
#endif
