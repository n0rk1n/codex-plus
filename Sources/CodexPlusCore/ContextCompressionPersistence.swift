import Foundation

public enum ConversationContextCompressionReason: String, Equatable, Sendable {
    case manual
    case threshold
    case retry
}

public struct ConversationContextCompressionSnapshot: Equatable, Sendable {
    public let id: UUID
    public let conversationID: UUID
    public var sourcePrompt: String
    public var editedSummary: String
    public let generatedSummary: String
    public let sourceEventIDs: [UUID]
    public let sourceSnapshotIDs: [UUID]
    public let templateID: UUID?
    public let reason: ConversationContextCompressionReason
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        conversationID: UUID,
        sourcePrompt: String,
        editedSummary: String,
        generatedSummary: String,
        sourceEventIDs: [UUID],
        sourceSnapshotIDs: [UUID] = [],
        templateID: UUID? = nil,
        reason: ConversationContextCompressionReason = .manual,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.conversationID = conversationID
        self.sourcePrompt = sourcePrompt
        self.editedSummary = editedSummary
        self.generatedSummary = generatedSummary
        self.sourceEventIDs = sourceEventIDs
        self.sourceSnapshotIDs = sourceSnapshotIDs
        self.templateID = templateID
        self.reason = reason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public final class ConversationContextCompressionRepository {
    private enum Keys {
        static let storageScopePrefix = "conversation-context-compression"
        static let storageType = "context_compression_snapshot"
        static let storageShape = "context-compression-v1"
        static let status = "active"
        static let sourceKind = "conversation_event"
    }

    private let memoryRepository: any MemoryRepository

    public init(memoryRepository: any MemoryRepository) {
        self.memoryRepository = memoryRepository
    }

    public func save(_ snapshot: ConversationContextCompressionSnapshot) throws {
        try replaceSnapshot(snapshot)
    }

    public func load(for conversationID: UUID) throws -> [ConversationContextCompressionSnapshot] {
        let cards = try memoryRepository.loadMemoryCards(scope: storageScope(for: conversationID))
        return cards.compactMap { decodeSnapshot(from: $0) }
    }

    public func delete(_ snapshotID: UUID) throws {
        try memoryRepository.deleteMemoryCard(snapshotID)
    }

    private func replaceSnapshot(_ snapshot: ConversationContextCompressionSnapshot) throws {
        let metadata = ContextCompressionSnapshotMetadata(
            schemaVersion: 1,
            reason: snapshot.reason.rawValue,
            conversationID: snapshot.conversationID.uuidString.lowercased(),
            sourceEventIDs: snapshot.sourceEventIDs.map { $0.uuidString.lowercased() },
            sourceSnapshotIDs: snapshot.sourceSnapshotIDs.map { $0.uuidString.lowercased() },
            templateID: snapshot.templateID?.uuidString.lowercased(),
            sourcePrompt: snapshot.sourcePrompt
        )
        let card = MemoryCard(
            id: snapshot.id,
            scope: storageScope(for: snapshot.conversationID),
            type: Keys.storageType,
            title: "上下文压缩快照",
            summary: snapshot.editedSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            body: snapshot.generatedSummary,
            contentShape: Keys.storageShape,
            status: Keys.status,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt,
            sourceMetadataJSON: encodedMetadata(metadata)
        )

        let existingSources = (try? memoryRepository.loadMemorySources(memoryCardID: snapshot.id)) ?? []
        for source in existingSources {
            try? memoryRepository.deleteMemorySource(source.id)
        }
        try memoryRepository.deleteMemoryCard(snapshot.id)
        try memoryRepository.saveMemoryCard(card)
        for eventID in snapshot.sourceEventIDs {
            let source = MemorySource(
                id: UUID(),
                memoryCardID: snapshot.id,
                sourceKind: Keys.sourceKind,
                sourceID: eventID.uuidString.lowercased(),
                sourcePath: nil,
                createdAt: snapshot.updatedAt
            )
            try memoryRepository.saveMemorySource(source)
        }
    }

    private func decodeSnapshot(from card: MemoryCard) -> ConversationContextCompressionSnapshot? {
        guard
            card.type == Keys.storageType,
            let metadata = decodeMetadata(from: card.sourceMetadataJSON),
            let conversationID = UUID(uuidString: metadata.conversationID),
            let reason = ConversationContextCompressionReason(rawValue: metadata.reason)
        else {
            return nil
        }

        let sourceEvents = (try? memoryRepository.loadMemorySources(memoryCardID: UUID(uuidString: card.id.uuidString) ?? card.id)
            .compactMap { source in
                guard source.sourceKind == Keys.sourceKind,
                      let eventID = UUID(uuidString: source.sourceID.lowercased()) else {
                    return nil
                }
                return eventID
            }) ?? metadata.sourceEventIDs.compactMap { UUID(uuidString: $0) }

        return ConversationContextCompressionSnapshot(
            id: card.id,
            conversationID: conversationID,
            sourcePrompt: metadata.sourcePrompt ?? "",
            editedSummary: card.summary,
            generatedSummary: card.body,
            sourceEventIDs: sourceEvents,
            sourceSnapshotIDs: metadata.sourceSnapshotIDs.compactMap(UUID.init(uuidString:)),
            templateID: metadata.templateID.flatMap(UUID.init(uuidString:)),
            reason: reason,
            createdAt: card.createdAt,
            updatedAt: card.updatedAt
        )
    }

    private func encodedMetadata(_ metadata: ContextCompressionSnapshotMetadata) -> String {
        guard let data = try? JSONEncoder().encode(metadata),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func decodeMetadata(from text: String) -> ContextCompressionSnapshotMetadata? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ContextCompressionSnapshotMetadata.self, from: data)
    }

    private func storageScope(for conversationID: UUID) -> String {
        "\(Keys.storageScopePrefix):\(conversationID.uuidString.lowercased())"
    }
}

private struct ContextCompressionSnapshotMetadata: Codable {
    var schemaVersion: Int
    var reason: String
    var conversationID: String
    var sourceEventIDs: [String]
    var sourceSnapshotIDs: [String]
    var templateID: String?
    var sourcePrompt: String?
}
