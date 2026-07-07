import SwiftUI

private struct CodexButtonHitAreaModifier<HitShape: Shape>: ViewModifier {
    let shape: HitShape

    func body(content: Content) -> some View {
        content.contentShape(shape)
    }
}

extension View {
    func codexRectangleButtonHitArea() -> some View {
        modifier(CodexButtonHitAreaModifier(shape: Rectangle()))
    }

    func codexCapsuleButtonHitArea() -> some View {
        modifier(CodexButtonHitAreaModifier(shape: Capsule(style: .continuous)))
    }

    func codexCircularButtonHitArea() -> some View {
        modifier(CodexButtonHitAreaModifier(shape: Circle()))
    }

    func codexRoundedButtonHitArea(cornerRadius: CGFloat) -> some View {
        modifier(
            CodexButtonHitAreaModifier(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        )
    }
}
