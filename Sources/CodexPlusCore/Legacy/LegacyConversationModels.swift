import Foundation

public struct ConversationCoordinatorSnapshot: Equatable, Sendable {
    public var workspaces: [WorkspaceSessionGroup]
    public var conversations: [ConversationSession]
    public var activeWorkspaceID: UUID?
    public var activeConversationID: UUID?
    public var draft: ConversationDraft?

    public init(
        workspaces: [WorkspaceSessionGroup],
        conversations: [ConversationSession],
        activeWorkspaceID: UUID?,
        activeConversationID: UUID?,
        draft: ConversationDraft?
    ) {
        self.workspaces = workspaces
        self.conversations = conversations
        self.activeWorkspaceID = activeWorkspaceID
        self.activeConversationID = activeConversationID
        self.draft = draft
    }

    public var activeConversation: ConversationSession? {
        guard let activeConversationID else {
            return nil
        }

        return conversations.first { $0.id == activeConversationID && !$0.isArchived }
    }

    public var hasVisibleConversations: Bool {
        conversations.contains { !$0.isArchived }
    }
}

public enum ShortcutDecision: Equatable, Sendable {
    case recallConversation(UUID)
    case recallDraft
    case openFreshEntry
}
