import Foundation

public protocol ConversationRepository: Sendable {
    func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws
    func loadConversations() throws -> [ConversationSession]
    func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws
}
