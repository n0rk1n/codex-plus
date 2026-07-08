import SwiftUI

struct CodexToggleSelector<Label: View>: View {
    let rule: CodexToggleSelectorRule
    @Binding var isOn: Bool
    var isDisabled: Bool = false
    var help: String? = nil
    var accessibilityLabel: String? = nil
    @ViewBuilder let label: () -> Label

    var body: some View {
        Toggle(isOn: $isOn) {
            label()
        }
        .modifier(CodexToggleSelectorRuleModifier(rule: rule))
        .codexOptionalHelp(help)
        .codexOptionalAccessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }
}

private struct CodexToggleSelectorRuleModifier: ViewModifier {
    let rule: CodexToggleSelectorRule

    @ViewBuilder
    func body(content: Content) -> some View {
        switch rule {
        case .filterToggle:
            content
                .toggleStyle(.button)
        }
    }
}
