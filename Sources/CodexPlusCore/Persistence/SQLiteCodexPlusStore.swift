import Foundation

public final class SQLiteCodexPlusStore: CodexPlusRepository, @unchecked Sendable {
    private let repository: SQLiteCodexPlusRepository

    public init(database: SQLiteDatabase) {
        self.repository = SQLiteCodexPlusRepository(database: database)
    }

    public func saveProject(_ project: WorkspaceSessionGroup) throws {
        try repository.saveProject(project)
    }

    public func loadProjects() throws -> [WorkspaceSessionGroup] {
        try repository.loadProjects()
    }

    public func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws {
        try repository.saveConversation(conversation, projectID: projectID)
    }

    public func loadConversations() throws -> [ConversationSession] {
        try repository.loadConversations()
    }

    public func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws {
        try repository.markConversationArchived(id, archiveMarkdownPath: archiveMarkdownPath, archivedAt: archivedAt)
    }

    public func saveArchiveRecord(_ record: ConversationArchiveRecord) throws {
        try repository.saveArchiveRecord(record)
    }

    public func searchArchiveRecords(query: String) throws -> [ConversationArchiveRecord] {
        try repository.searchArchiveRecords(query: query)
    }

    public func archiveConversation(
        record: ConversationArchiveRecord,
        archiveMarkdownPath: String,
        archivedAt: Date
    ) throws {
        try repository.archiveConversation(
            record: record,
            archiveMarkdownPath: archiveMarkdownPath,
            archivedAt: archivedAt
        )
    }

    public func saveMemoryCard(_ card: MemoryCard) throws {
        try repository.saveMemoryCard(card)
    }

    public func loadMemoryCards(scope: String?) throws -> [MemoryCard] {
        try repository.loadMemoryCards(scope: scope)
    }

    public func deleteMemoryCard(_ id: UUID) throws {
        try repository.deleteMemoryCard(id)
    }

    public func saveMemorySource(_ source: MemorySource) throws {
        try repository.saveMemorySource(source)
    }

    public func loadMemorySources(memoryCardID: UUID) throws -> [MemorySource] {
        try repository.loadMemorySources(memoryCardID: memoryCardID)
    }

    public func deleteMemorySource(_ id: UUID) throws {
        try repository.deleteMemorySource(id)
    }

    public func saveAttachment(_ attachment: CodexPlusAttachment) throws {
        try repository.saveAttachment(attachment)
    }

    public func loadAttachments(ownerKind: String, ownerID: UUID?) throws -> [CodexPlusAttachment] {
        try repository.loadAttachments(ownerKind: ownerKind, ownerID: ownerID)
    }

    public func deleteAttachment(_ id: UUID) throws {
        try repository.deleteAttachment(id)
    }

    public func savePromptTemplate(_ template: PromptTemplate) throws {
        try repository.savePromptTemplate(template)
    }

    public func loadPromptTemplates() throws -> [PromptTemplate] {
        try repository.loadPromptTemplates()
    }

    public func deletePromptTemplate(_ id: UUID) throws {
        try repository.deletePromptTemplate(id)
    }
}
