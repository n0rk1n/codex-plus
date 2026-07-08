import CodexPlusCore
import SwiftUI

struct CodexMultilineTextField: View {
    let rule: CodexMultilineTextRule
    let placeholder: String
    @Binding var text: String
    var foregroundColor: Color = .primary
    var placeholderColor: Color = .secondary
    var readOnlyNotice: CodexReadOnlyNoticeHandle?
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(text: $text, axis: .vertical) {
            Text(placeholder)
                .foregroundStyle(placeholderColor)
        }
        .textFieldStyle(.plain)
        .font(.system(size: fontSize))
        .foregroundStyle(foregroundColor)
        .lineLimit(lineLimit)
        .onSubmit(onSubmit)
        .codexReadOnlyControlOverlay(readOnlyNotice)
    }

    private var fontSize: CGFloat {
        switch rule {
        case .multilinePrompt:
            return 15
        case .multilineNote:
            return 14
        case .longPromptEditor:
            return 13
        }
    }

    private var lineLimit: ClosedRange<Int> {
        switch rule {
        case .multilinePrompt:
            return MultilineInputDefaults.conversationPromptLineLimit
        case .multilineNote:
            return MultilineInputDefaults.promptTemplateNoteLineLimit
        case .longPromptEditor:
            return 1...1
        }
    }
}
