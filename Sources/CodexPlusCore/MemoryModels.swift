import Foundation

public struct MemoryCard: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var scope: String
    public var type: String
    public var title: String
    public var summary: String
    public var body: String
    public var contentShape: String
    public var status: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sourceMetadataJSON: String

    public init(
        id: UUID = UUID(),
        scope: String,
        type: String,
        title: String,
        summary: String,
        body: String,
        contentShape: String,
        status: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceMetadataJSON: String
    ) {
        self.id = id
        self.scope = scope
        self.type = type
        self.title = title
        self.summary = summary
        self.body = body
        self.contentShape = contentShape
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceMetadataJSON = sourceMetadataJSON
    }
}

public struct MemorySource: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var memoryCardID: UUID
    public var sourceKind: String
    public var sourceID: String
    public var sourcePath: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        memoryCardID: UUID,
        sourceKind: String,
        sourceID: String,
        sourcePath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.memoryCardID = memoryCardID
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.sourcePath = sourcePath
        self.createdAt = createdAt
    }
}

public struct CodexPlusAttachment: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var ownerKind: String
    public var ownerID: UUID
    public var filePath: String
    public var originalFilePath: String?
    public var contentType: String
    public var byteCount: Int64
    public var checksum: String
    public var isSnapshot: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        ownerKind: String,
        ownerID: UUID,
        filePath: String,
        originalFilePath: String? = nil,
        contentType: String,
        byteCount: Int64,
        checksum: String,
        isSnapshot: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.filePath = filePath
        self.originalFilePath = originalFilePath
        self.contentType = contentType
        self.byteCount = byteCount
        self.checksum = checksum
        self.isSnapshot = isSnapshot
        self.createdAt = createdAt
    }
}
