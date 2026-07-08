import SwiftUI

struct CodexToggleSelector<Label: View>: View {
    let rule: CodexToggleSelectorRule
    @Binding var isOn: Bool
    var help: String?
    @ViewBuilder let label: () -> Label

    var body: some View {
        Toggle(isOn: $isOn) {
            label()
        }
        .modifier(CodexToggleSelectorRuleModifier(rule: rule))
        .codexOptionalHelp(help)
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
