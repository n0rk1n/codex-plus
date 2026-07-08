import SwiftUI

struct CodexTextField: View {
    let rule: CodexTextFieldRule
    let placeholder: String
    @Binding var text: String
    var readOnlyNotice: CodexReadOnlyNoticeHandle?
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .modifier(CodexTextFieldRuleModifier(rule: rule))
            .onSubmit(onSubmit)
            .codexReadOnlyControlOverlay(readOnlyNotice)
    }
}

private struct CodexTextFieldRuleModifier: ViewModifier {
    let rule: CodexTextFieldRule

    @ViewBuilder
    func body(content: Content) -> some View {
        switch rule {
        case .composerInline:
            content
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1)
                .submitLabel(.send)
        case .searchField:
            content
                .textFieldStyle(.roundedBorder)
        case .formField:
            content
                .textFieldStyle(.roundedBorder)
        }
    }
}
