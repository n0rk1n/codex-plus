import CodexPlusCore
import SwiftUI

struct CodexMultilineTextField: View {
    let rule: CodexMultilineTextRule
    let placeholder: String
    @Binding var text: String
    var isDisabled: Bool = false
    var foregroundColor: Color = .primary
    var placeholderColor: Color = .secondary
    var help: String? = nil
    var accessibilityLabel: String? = nil
    var readOnlyNotice: CodexReadOnlyNoticeHandle?
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(text: $text, axis: .vertical) {
            Text(placeholder)
                .foregroundStyle(placeholderColor)
        }
        .textFieldStyle(.plain)
        .font(rule.font)
        .foregroundStyle(foregroundColor)
        .lineLimit(lineLimit)
        .onSubmit(onSubmit)
        .codexReadOnlyControlOverlay(readOnlyNotice)
        .codexOptionalHelp(help)
        .codexOptionalAccessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }

    private var lineLimit: ClosedRange<Int> {
        switch rule {
        case .multilinePrompt:
            return MultilineInputDefaults.conversationPromptLineLimit
        case .multilineNote:
            return MultilineInputDefaults.promptTemplateNoteLineLimit
        case .compactPrompt:
            return MultilineInputDefaults.compactPromptLineLimit
        case .conversationFollowUpPrompt:
            return MultilineInputDefaults.conversationPromptLineLimit
        case .longPromptEditor:
            return 1...1
        }
    }
}
