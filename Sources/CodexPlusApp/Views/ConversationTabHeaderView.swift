import CodexPlusCore
import SwiftUI
import UniformTypeIdentifiers

struct ConversationTabHeaderView: View {
    let snapshot: ConversationCoordinatorSnapshot
    let onSelectWorkspace: (UUID) -> Void
    let onSelectConversation: (UUID) -> Void
    let onNewDraft: () -> Void
    let onArchiveConversation: (UUID) -> Void
    let onReorderWorkspace: (UUID, Int) -> Void
    let onReorderConversation: (UUID, Int) -> Void

    @State private var draggedWorkspaceID: UUID?
    @State private var draggedConversationID: UUID?

    private var activeWorkspace: WorkspaceSessionGroup? {
        guard let activeWorkspaceID = snapshot.activeWorkspaceID else {
            return nil
        }

        return snapshot.workspaces.first { $0.id == activeWorkspaceID }
    }

    private var activeWorkspaceConversations: [ConversationSession] {
        guard let activeWorkspace else {
            return []
        }

        return activeWorkspace.conversationIDs.compactMap(conversation(for:))
    }

    var body: some View {
        VStack(spacing: 6) {
            tabScrollRow {
                ForEach(Array(snapshot.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    workspaceTab(workspace, index: index)
                }
            }

            tabScrollRow {
                ForEach(Array(activeWorkspaceConversations.enumerated()), id: \.element.id) { index, conversation in
                    conversationTab(conversation, index: index)
                }

                Button(action: onNewDraft) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .help("New Conversation")
                .accessibilityLabel("New Conversation")
            }
        }
    }

    private func tabScrollRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                content()
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workspaceTab(_ workspace: WorkspaceSessionGroup, index: Int) -> some View {
        Button {
            onSelectWorkspace(workspace.id)
        } label: {
            HStack(spacing: 6) {
                statusDot(isRunning: workspaceHasRunningConversation(workspace))

                Text(workspace.displayName)
                    .font(.caption.weight(snapshot.activeWorkspaceID == workspace.id ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tabBackground(isActive: snapshot.activeWorkspaceID == workspace.id))
        }
        .buttonStyle(.plain)
        .help(workspace.path)
        .contentShape(Rectangle())
        .onDrag {
            draggedWorkspaceID = workspace.id
            return NSItemProvider(object: workspace.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { _, _ in
            handleWorkspaceDrop(targetIndex: index)
        }
    }

    private func conversationTab(_ conversation: ConversationSession, index: Int) -> some View {
        HStack(spacing: 2) {
            Button {
                onArchiveConversation(conversation.id)
            } label: {
                Image(systemName: "archivebox")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 24)
            }
            .buttonStyle(.plain)
            .help("Archive")
            .accessibilityLabel("Archive Conversation")

            Button {
                onSelectConversation(conversation.id)
            } label: {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.caption2.weight(snapshot.activeConversationID == conversation.id ? .semibold : .regular))
                        .lineLimit(1)

                    statusDot(isRunning: conversation.state == .running)
                }
                .padding(.leading, 2)
                .padding(.trailing, 9)
                .frame(height: 24)
            }
            .buttonStyle(.plain)
            .help(conversation.title)
            .accessibilityLabel(conversation.title)
        }
        .padding(.leading, 4)
        .background(tabBackground(isActive: snapshot.activeConversationID == conversation.id))
        .contentShape(Rectangle())
        .onDrag {
            draggedConversationID = conversation.id
            return NSItemProvider(object: conversation.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { _, _ in
            handleConversationDrop(targetIndex: index)
        }
    }

    private func workspaceHasRunningConversation(_ workspace: WorkspaceSessionGroup) -> Bool {
        workspace.conversationIDs.contains { id in
            conversation(for: id)?.state == .running
        }
    }

    private func conversation(for id: UUID) -> ConversationSession? {
        snapshot.conversations.first { $0.id == id && !$0.isArchived }
    }

    private func handleWorkspaceDrop(targetIndex: Int) -> Bool {
        guard let draggedWorkspaceID else {
            return false
        }

        onReorderWorkspace(draggedWorkspaceID, targetIndex)
        self.draggedWorkspaceID = nil
        return true
    }

    private func handleConversationDrop(targetIndex: Int) -> Bool {
        guard let draggedConversationID else {
            return false
        }

        onReorderConversation(draggedConversationID, targetIndex)
        self.draggedConversationID = nil
        return true
    }

    private func tabBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
    }

    private func statusDot(isRunning: Bool) -> some View {
        Circle()
            .fill(isRunning ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 6, height: 6)
    }
}
