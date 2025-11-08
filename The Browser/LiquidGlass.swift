import SwiftUI

struct LiquidGlassBackgroundModifier: ViewModifier {
    var tint: Color
    var cornerRadius: CGFloat
    var includeShadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            .blendMode(.overlay)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .shadow(
                color: Color.black.opacity(includeShadow ? 0.08 : 0),
                radius: includeShadow ? 10 : 0,
                x: 0,
                y: includeShadow ? 6 : 0
            )
    }
}

extension View {
    func liquidGlassBackground(tint: Color, cornerRadius: CGFloat = 14, includeShadow: Bool = true) -> some View {
        modifier(LiquidGlassBackgroundModifier(tint: tint, cornerRadius: cornerRadius, includeShadow: includeShadow))
    }
}
