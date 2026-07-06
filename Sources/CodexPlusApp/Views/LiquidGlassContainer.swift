import SwiftUI

struct LiquidGlassScene<Content: View>: View {
    let padding: CGFloat
    let minWidth: CGFloat?
    let minHeight: CGFloat?
    private let content: Content

    init(
        padding: CGFloat,
        minWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer {
            content
                .padding(padding)
                .frame(minWidth: minWidth, minHeight: minHeight)
        }
        .environment(\.colorScheme, .dark)
    }
}

struct LiquidGlassContainer<Content: View>: View {
    let cornerRadius: CGFloat
    private let content: Content

    init(
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .glassEffect(
                .regular,
                in: glassShape
            )
            .compositingGroup()
            .mask(glassShape)
    }

    private var glassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}
