import Foundation

public enum WorkbenchProjection {
    public static func projectCards(
        workspaces: [WorkspaceSessionGroup],
        conversations: [ConversationSession],
        activeWorkspaceID: UUID?,
        activeConversationID: UUID?
    ) -> [WorkbenchProjectCard] {
        workspaces.compactMap { workspace in
            let visibleConversations = workspace.conversationIDs.compactMap { id in
                conversations.first { $0.id == id && !$0.isArchived }
            }
            guard !visibleConversations.isEmpty else {
                return nil
            }

            let selectedConversation = visibleConversations.first { $0.id == activeConversationID } ?? visibleConversations.first
            let count = visibleConversations.count
            let conversationSummaries = visibleConversations.map { conversation in
                WorkbenchConversationSummary(
                    id: conversation.id,
                    title: conversation.title,
                    state: conversation.state
                )
            }

            return WorkbenchProjectCard(
                id: workspace.id,
                projectName: workspace.displayName,
                projectPath: workspace.path,
                conversationID: selectedConversation?.id,
                conversationTitle: selectedConversation?.title ?? "",
                conversationState: selectedConversation?.state,
                conversationSummaries: conversationSummaries,
                visibleConversationCount: count,
                overflowCount: count > 1 ? count : nil,
                isActive: workspace.id == activeWorkspaceID
            )
        }
    }
}
