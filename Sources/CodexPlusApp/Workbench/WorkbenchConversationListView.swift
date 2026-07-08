import CodexPlusCore
import SwiftUI

struct WorkbenchConversationListView: View {
    let cards: [WorkbenchProjectCard]
    let actions: ProjectStripActions

    var body: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.conversationCornerRadius) {
            Group {
                if cards.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(cards) { card in
                                ForEach(card.conversationSummaries) { conversation in
                                    conversationRow(conversation, in: card)
                                }
                            }
                        }
                        .padding(CodexSpacing.contentInline)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: WorkbenchMetrics.conversationListWidth)
        .frame(maxHeight: .infinity)
    }

    private func conversationRow(
        _ conversation: WorkbenchConversationSummary,
        in card: WorkbenchProjectCard
    ) -> some View {
        let isActive = card.isActive && card.conversationID == conversation.id

        return CodexButton(
            rule: .rowRounded(cornerRadius: WorkbenchMetrics.conversationListRowCornerRadius),
            accessibilityLabel: conversation.title,
            action: {
                actions.selectConversation(conversation.id)
            }
        ) {
            HStack(alignment: .top, spacing: 10) {
                statusDot(for: conversation.state)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 5) {
                    Text(conversation.title)
                        .font(CodexTypography.menuPrimary.weight(isActive ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(card.projectName)
                        .font(CodexTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, CodexSpacing.contentInline)
            .padding(.vertical, CodexSpacing.tightInline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(isActive: isActive), in: rowShape)
            .overlay {
                if isActive {
                    rowShape.stroke(.white.opacity(0.16), lineWidth: 1)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            Image(systemName: "text.bubble")
                .font(CodexTypography.listEmptyStateTitle)
                .foregroundStyle(.secondary)

            Text("暂无对话")
                .font(CodexTypography.statusBar)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WorkbenchMetrics.conversationListRowCornerRadius, style: .continuous)
    }

    private func rowBackground(isActive: Bool) -> Color {
        isActive ? CodexColors.surfaceSubtleStrong : CodexColors.surfaceSubtleWeak
    }

    private func statusDot(for state: ConversationRunState) -> some View {
        Circle()
            .fill(state.tabDotTint)
            .frame(width: 7, height: 7)
    }
}
