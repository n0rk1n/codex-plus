import SwiftUI

struct CodexButton<Label: View>: View {
    let rule: CodexButtonRule
    var role: ButtonRole?
    var isDisabled: Bool = false
    var help: String? = nil
    var accessibilityLabel: String? = nil
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(role: role, action: action) {
            label()
        }
        .modifier(CodexButtonRuleModifier(rule: rule))
        .codexOptionalHelp(help)
        .codexOptionalAccessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }
}

private struct CodexButtonRuleModifier: ViewModifier {
    let rule: CodexButtonRule

    @ViewBuilder
    func body(content: Content) -> some View {
        switch rule {
        case .toolbarCapsule:
            content
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .compositingGroup()
                .mask(Capsule(style: .continuous))
                .codexControlHitArea(.capsule)
        case .toolbarIconCircle:
            content
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Circle())
                .compositingGroup()
                .mask(Circle())
                .codexControlHitArea(.circle)
        case .composerIconCircle:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.circle)
        case .workspaceCapsule:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.capsule)
        case .workspaceClear:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rectangle)
        case .rowRectangle:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rectangle)
        case let .rowRounded(cornerRadius):
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rounded(cornerRadius: cornerRadius))
        case let .cardRounded(cornerRadius):
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rounded(cornerRadius: cornerRadius))
        case .formHeaderCapsule:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.capsule)
        case .formFooterCapsule:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.capsule)
        case .inlineTextLink:
            content
                .buttonStyle(.plain)
                .codexControlHitArea(.rectangle)
        }
    }
}
