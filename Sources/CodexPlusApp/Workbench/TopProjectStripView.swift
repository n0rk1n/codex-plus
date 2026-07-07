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
                stripActionButton(title: firstActionTitle, systemName: firstActionSystemName, action: firstAction)
                    .disabled(!isShowingArchiveSearch && isNewConversationDisabled)
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

    private func stripActionButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .compositingGroup()
        .mask(Capsule(style: .continuous))
        .codexCapsuleButtonHitArea()
    }

    private func iconActionButton(
        help: String,
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .compositingGroup()
        .mask(Circle())
        .codexCircularButtonHitArea()
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }

    private func projectCard(_ card: WorkbenchProjectCard) -> some View {
        Button(action: {
            if let conversationID = card.conversationID {
                actions.selectConversation(conversationID)
            } else {
                actions.selectProject(card.id)
            }
        }) {
            LiquidGlassContainer(cornerRadius: WorkbenchMetrics.projectCardCornerRadius) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Text("项目：")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(card.projectName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            Text("对话：")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(card.conversationTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        HStack(spacing: 8) {
                            Text("\(card.visibleConversationCount) 条")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    if card.overflowCount != nil, let overflowCount = card.overflowCount {
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
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: 280, alignment: .leading)
                .codexRoundedButtonHitArea(cornerRadius: WorkbenchMetrics.projectCardCornerRadius)
            }
        }
        .buttonStyle(.plain)
        .codexRoundedButtonHitArea(cornerRadius: WorkbenchMetrics.projectCardCornerRadius)
    }
}
