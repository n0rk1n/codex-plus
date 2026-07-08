import CodexPlusCore
import SwiftUI

struct TopProjectStripView: View {
    let cards: [WorkbenchProjectCard]
    let isPinned: Bool
    let isNewConversationDisabled: Bool
    let isShowingArchiveSearch: Bool
    let actions: ProjectStripActions

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                stripActionButton(
                    title: firstActionTitle,
                    systemName: firstActionSystemName,
                    isDisabled: !isShowingArchiveSearch && isNewConversationDisabled,
                    action: firstAction
                )
                .opacity(!isShowingArchiveSearch && isNewConversationDisabled ? 0.45 : 1)
                stripActionButton(title: WorkbenchStrings.archived, systemName: "archivebox", action: actions.openArchive)
                Spacer(minLength: 0)
                iconActionButton(
                    help: WorkbenchStrings.openSettingsHelp,
                    systemName: "gearshape",
                    accessibilityLabel: WorkbenchStrings.openSettings,
                    action: actions.openSettings
                )
                pinButton
            }

            if WorkbenchInteractionPolicies.shouldShowProjectCardRail(projectCardCount: cards.count) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(cards) { card in
                            projectCard(card)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var firstActionTitle: String {
        isShowingArchiveSearch ? "回到对话" : WorkbenchStrings.newConversation
    }

    private var firstActionSystemName: String {
        isShowingArchiveSearch ? "bubble.left" : "square.and.pencil"
    }

    private var firstAction: () -> Void {
        isShowingArchiveSearch ? actions.returnToConversation : actions.newConversation
    }

    private var pinButton: some View {
        iconActionButton(
            help: isPinned ? WorkbenchStrings.unpinWindow : WorkbenchStrings.pinWindow,
            systemName: isPinned ? "pin.fill" : "pin",
            accessibilityLabel: isPinned ? WorkbenchStrings.unpinWindow : WorkbenchStrings.pinWindow,
            action: actions.togglePin
        )
    }

    private func stripActionButton(
        title: String,
        systemName: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        CodexButton(rule: .toolbarCapsule, isDisabled: isDisabled, action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private func iconActionButton(
        help: String,
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        CodexButton(
            rule: .toolbarIconCircle,
            help: help,
            accessibilityLabel: accessibilityLabel,
            action: action
        ) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
        }
    }

    private func projectCard(_ card: WorkbenchProjectCard) -> some View {
        CodexButton(
            rule: .cardRounded(cornerRadius: WorkbenchMetrics.projectCardCornerRadius),
            action: {
                if let conversationID = card.conversationID {
                    actions.selectConversation(conversationID)
                } else {
                    actions.selectProject(card.id)
                }
            }
        ) {
            LiquidGlassContainer(cornerRadius: WorkbenchMetrics.projectCardCornerRadius) {
                projectCardContent(card)
            }
        }
    }

    private func projectCardContent(_ card: WorkbenchProjectCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                projectCardLine(systemName: "folder", label: "项目：", value: card.projectName)
                projectCardLine(systemName: "text.bubble", label: "对话：", value: card.conversationTitle)

                HStack(spacing: 8) {
                    Text("\(card.visibleConversationCount) 条")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if card.overflowCount != nil, let overflowCount = card.overflowCount {
                projectCardOverflowMenu(card: card, overflowCount: overflowCount)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 280, alignment: .leading)
    }

    private func projectCardLine(systemName: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func projectCardOverflowMenu(card: WorkbenchProjectCard, overflowCount: Int) -> some View {
        Menu {
            ForEach(card.conversationSummaries) { conversation in
                Button {
                    actions.selectConversation(conversation.id)
                } label: {
                    Text(conversation.title)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("\(overflowCount) 条对话")
    }
}
