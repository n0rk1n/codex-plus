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
                .modifier(CodexButtonRuleModifier(rule: rule))
        }
        .buttonStyle(.plain)
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
                .font(CodexTypography.menuPrimary)
                .padding(.horizontal, CodexSpacing.contentInline)
                .padding(.vertical, CodexSpacing.tightVertical)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .compositingGroup()
                .mask(Capsule(style: .continuous))
                .codexControlHitArea(.capsule)
        case .toolbarIconCircle:
            content
                .font(CodexTypography.menuPrimary)
                .frame(width: 32, height: 32)
                .glassEffect(.regular, in: Circle())
                .compositingGroup()
                .mask(Circle())
                .codexControlHitArea(.circle)
        case .composerIconCircle:
            content
                .font(CodexTypography.controlLabel)
                .frame(width: WorkbenchMetrics.composerControlHeight, height: WorkbenchMetrics.composerControlHeight)
                .codexControlHitArea(.circle)
        case .workspaceCapsule:
            content
                .codexControlHitArea(.capsule)
        case .workspaceClear:
            content
                .font(CodexTypography.controlLabel)
                .frame(width: 24, height: WorkbenchMetrics.composerControlHeight)
                .codexControlHitArea(.rectangle)
        case .rowRectangle:
            content
                .codexControlHitArea(.rectangle)
        case let .rowRounded(cornerRadius):
            content
                .codexControlHitArea(.rounded(cornerRadius: cornerRadius))
        case let .cardRounded(cornerRadius):
            content
                .codexControlHitArea(.rounded(cornerRadius: cornerRadius))
        case .formHeaderCapsule:
            content
                .font(CodexTypography.microControl)
                .padding(.horizontal, CodexSpacing.contentInline)
                .padding(.vertical, CodexSpacing.compactVertical)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .compositingGroup()
                .mask(Capsule(style: .continuous))
                .codexControlHitArea(.capsule)
        case .formFooterCapsule:
            content
                .font(CodexTypography.microControl)
                .padding(.horizontal, CodexSpacing.contentInline)
                .padding(.vertical, CodexSpacing.compactVertical)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .compositingGroup()
                .mask(Capsule(style: .continuous))
                .codexControlHitArea(.capsule)
        case .inlineTextLink:
            content
                .codexControlHitArea(.rectangle)
        }
    }
}
