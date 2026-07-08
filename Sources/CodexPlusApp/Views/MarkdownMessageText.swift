import SwiftUI

struct MarkdownMessageText: View {
    let markdown: String

    var body: some View {
        if let attributedMarkdown {
            Text(attributedMarkdown)
        } else {
            Text(markdown)
        }
    }

    private var attributedMarkdown: AttributedString? {
        try? AttributedString(markdown: markdown)
    }
}
