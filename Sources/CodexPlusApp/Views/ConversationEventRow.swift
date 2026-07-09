import CodexPlusCore
import SwiftUI

struct ConversationEventRow: View {
    let event: ConversationDisplayEvent
    var compressionPresentation: ConversationTimelineRowCompressionPresentation? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.timelineIconName)
                .font(CodexTypography.menuPrimary)
                .foregroundStyle(event.timelineTint)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.timelineTitle)
                        .font(CodexTypography.statusBar)
                        .foregroundStyle(event.timelineTint)

                    if let detail = event.timelineDetailText {
                        Text(detail)
                            .font(CodexTypography.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 150, alignment: .leading)
                    }
                }

                messageBody
                    .font(CodexTypography.messageBody)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .opacity(compressionPresentation?.isDimmed == true ? 0.48 : 1)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        event.timelineMessage
    }

    @ViewBuilder
    private var messageBody: some View {
        if event.shouldRenderTimelineMarkdown {
            MarkdownMessageText(markdown: message)
        } else {
            Text(message)
        }
    }

}
