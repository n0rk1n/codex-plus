import Foundation

public protocol ArchiveRepository: Sendable {
    func saveArchiveRecord(_ record: ConversationArchiveRecord) throws
    func searchArchiveRecords(query: String) throws -> [ConversationArchiveRecord]
    func archiveConversation(record: ConversationArchiveRecord, archiveMarkdownPath: String, archivedAt: Date) throws
}
