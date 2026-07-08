import AppKit
import CodexPlusCore
import SwiftUI

struct CodexMultilineTextEditor: View {
    let rule: CodexMultilineTextRule
    @Binding var text: String
    var isDisabled: Bool = false
    var help: String? = nil
    var accessibilityLabel: String? = nil

    var body: some View {
        CodexMultilineTextEditorRepresentable(
            rule: rule,
            text: $text
        )
        .codexOptionalHelp(help)
        .codexOptionalAccessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
    }
}

private struct CodexMultilineTextEditorRepresentable: NSViewRepresentable {
    let rule: CodexMultilineTextRule
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled

    var fontSize: CGFloat = 13
    var insetWidth: Double = MultilineInputDefaults.promptTemplateEditorInsetWidth
    var insetHeight: Double = MultilineInputDefaults.promptTemplateEditorInsetHeight

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: insetWidth, height: insetHeight)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text

        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        textView.font = .systemFont(ofSize: fontSize)
        textView.textContainerInset = NSSize(width: insetWidth, height: insetHeight)
        textView.isEditable = isEnabled
        textView.isSelectable = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}
