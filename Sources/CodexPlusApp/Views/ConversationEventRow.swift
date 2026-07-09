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

struct ConversationCompressionSnapshotRow: View {
    let snapshot: ConversationContextCompressionSnapshot
    let sourceEvents: [ConversationDisplayEvent]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "archivebox.fill")
                .font(CodexTypography.menuPrimary)
                .foregroundStyle(CodexColors.stateWarning)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("上下文已压缩")
                        .font(CodexTypography.statusBar)
                        .foregroundStyle(CodexColors.stateWarning)

                    Text(sourceDetailText)
                        .font(CodexTypography.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("这段原文已被压缩；发送给模型的是下面的压缩文本，不是你看到的完整原文追溯。原文不可直接修改。")
                    .font(CodexTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                MarkdownMessageText(markdown: snapshot.editedSummary)
                    .font(CodexTypography.messageBody)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var sourceDetailText: String {
        if sourceEvents.isEmpty {
            return "来源待追溯"
        }

        return "来源 \(sourceEvents.count) 条"
    }
}
