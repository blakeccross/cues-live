import SwiftUI

extension View {
    /// Liquid Glass behind the view when built with the 26+ SDK and running on 26+,
    /// otherwise a bordered material so earlier systems get a similar floating surface.
    @ViewBuilder
    func appGlassBackground<S: Shape>(in shape: S) -> some View {
#if CUESLIVE_TOOLBAR_GLASS_SDK26
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            materialBackground(in: shape)
        }
#else
        materialBackground(in: shape)
#endif
    }

    /// Pins `bar` to the bottom edge as a safe-area bar. Scroll views inset their content
    /// and scroll underneath it; non-scrolling content, such as the mixer, is laid out above it.
    @ViewBuilder
    func appFloatingBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
#if CUESLIVE_TOOLBAR_GLASS_SDK26
        if #available(iOS 26.0, macOS 26.0, *) {
            safeAreaBar(edge: .bottom, spacing: 0, content: bar)
        } else {
            safeAreaInset(edge: .bottom, spacing: 0, content: bar)
        }
#else
        safeAreaInset(edge: .bottom, spacing: 0, content: bar)
#endif
    }

    /// Turns off the scroll edge effect under a bottom bar. The system draws a blurred
    /// gradient band there by default; the bar's own glass already separates it from rows.
    @ViewBuilder
    func appClearBottomScrollEdge() -> some View {
#if CUESLIVE_TOOLBAR_GLASS_SDK26
        if #available(iOS 26.0, macOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            self
        }
#else
        self
#endif
    }

    private func materialBackground<S: Shape>(in shape: S) -> some View {
        background {
            shape
                .fill(.regularMaterial)
                .overlay { shape.stroke(AppColors.separator, lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
    }
}
