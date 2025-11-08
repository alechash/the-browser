import SwiftUI
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
}
