import SwiftUI

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
                .regular.tint(.white.opacity(0.62)),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
