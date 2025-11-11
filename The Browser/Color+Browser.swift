import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#endif

extension Color {
    static var browserBackground: Color {
#if os(macOS)
        Color(nsColor: .windowBackgroundColor)
#else
        Color(.systemBackground)
#endif
    }

    static var browserControlBackground: Color {
#if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
#else
        Color(.secondarySystemBackground)
#endif
    }

    static var browserControlBorder: Color {
#if os(macOS)
        Color(nsColor: .separatorColor).opacity(0.25)
#else
        Color(.separator).opacity(0.25)
#endif
    }

    static var browserSidebarBackground: Color {
#if os(macOS)
        Color(nsColor: NSColor.windowBackgroundColor)
#else
        Color(.systemGroupedBackground)
#endif
    }

    static var browserSidebarButtonBackground: Color {
#if os(macOS)
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
#else
        Color(.tertiarySystemGroupedBackground)
#endif
    }

    static var browserSidebarSelection: Color {
        Color.blue.opacity(0.18)
    }

    static var browserAccent: Color {
        Color.blue
    }

    static func fromHex(_ hex: String) -> Color? {
        var formatted = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if formatted.hasPrefix("#") {
            formatted.removeFirst()
        }

        guard formatted.count == 6 || formatted.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: formatted).scanHexInt64(&value) else { return nil }

        let r, g, b, a: Double
        if formatted.count == 8 {
            r = Double((value & 0xFF000000) >> 24)
            g = Double((value & 0x00FF0000) >> 16)
            b = Double((value & 0x0000FF00) >> 8)
            a = Double(value & 0x000000FF)
        } else {
            r = Double((value & 0xFF0000) >> 16)
            g = Double((value & 0x00FF00) >> 8)
            b = Double(value & 0x0000FF)
            a = 255
        }

        return Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a / 255)
    }
}
