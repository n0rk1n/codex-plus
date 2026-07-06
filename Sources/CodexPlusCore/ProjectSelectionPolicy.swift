import Foundation

public enum ProjectSelectionPolicy {
    public static func firstVisibleConversationID(
        in workspaceID: UUID,
        workspaces: [WorkspaceSessionGroup],
        conversations: [ConversationSession]
    ) -> UUID? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return nil
        }

        return workspace.conversationIDs.first { id in
            conversations.contains { $0.id == id && !$0.isArchived }
        }
    }

    public static func repairActiveSelection(in state: WorkbenchState) -> WorkbenchState {
        var updated = state

        if let activeConversationID = updated.activeConversationID,
           updated.conversations.contains(where: { $0.id == activeConversationID && !$0.isArchived }) {
            return updated
        }

        if let activeWorkspaceID = updated.activeWorkspaceID {
            updated.activeConversationID = firstVisibleConversationID(
                in: activeWorkspaceID,
                workspaces: updated.workspaces,
                conversations: updated.conversations
            )
            return updated
        }

        if let workspace = updated.workspaces.max(by: { $0.lastActivityAt < $1.lastActivityAt }) {
            updated.activeWorkspaceID = workspace.id
            updated.activeConversationID = firstVisibleConversationID(
                in: workspace.id,
                workspaces: updated.workspaces,
                conversations: updated.conversations
            )
        }

        return updated
    }
}
