import Foundation

public protocol MemoryRepository: Sendable {
    func saveMemoryCard(_ card: MemoryCard) throws
    func loadMemoryCards(scope: String?) throws -> [MemoryCard]
    func deleteMemoryCard(_ id: UUID) throws
    func saveMemorySource(_ source: MemorySource) throws
    func loadMemorySources(memoryCardID: UUID) throws -> [MemorySource]
    func deleteMemorySource(_ id: UUID) throws
}
