import CodexPlusCore
import SwiftUI

struct TopProjectStripView: View {
    let cards: [WorkbenchProjectCard]
    let isPinned: Bool
    let onNewConversation: () -> Void
    let onOpenArchive: () -> Void
    let onTogglePin: () -> Void
    let onSelectProject: (UUID) -> Void
    let onSelectConversation: (UUID) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                stripActionButton(title: "新对话", systemName: "square.and.pencil", action: onNewConversation)
                stripActionButton(title: "已归档", systemName: "archivebox", action: onOpenArchive)
                Spacer(minLength: 0)
                pinButton
            }

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

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .compositingGroup()
        .mask(Circle())
        .help(isPinned ? "取消固定" : "固定")
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
    }

    private func projectCard(_ card: WorkbenchProjectCard) -> some View {
        Button(action: {
            if let conversationID = card.conversationID {
                onSelectConversation(conversationID)
            } else {
                onSelectProject(card.id)
            }
        }) {
            LiquidGlassContainer(cornerRadius: 18) {
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
                                    onSelectConversation(conversation.id)
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
                .opacity(card.isActive ? 1 : 0.82)
            }
        }
        .buttonStyle(.plain)
    }
}
