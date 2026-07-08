import SwiftUI

struct CodexPicker<SelectionValue: Hashable, Content: View>: View {
    let rule: CodexPickerRule
    let title: String
    @Binding var selection: SelectionValue
    var isDisabled: Bool = false
    var help: String? = nil
    var accessibilityLabel: String? = nil
    var readOnlyNotice: CodexReadOnlyNoticeHandle?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Picker(title, selection: $selection) {
            content()
        }
        .modifier(CodexPickerRuleModifier(rule: rule))
        .codexReadOnlyControlOverlay(readOnlyNotice)
        .codexOptionalHelp(help)
        .codexOptionalAccessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }
}

private struct CodexPickerRuleModifier: ViewModifier {
    let rule: CodexPickerRule

    @ViewBuilder
    func body(content: Content) -> some View {
        switch rule {
        case .segmentedFilter:
            content
                .pickerStyle(.segmented)
                .labelsHidden()
        case .requiredMenu:
            content
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
