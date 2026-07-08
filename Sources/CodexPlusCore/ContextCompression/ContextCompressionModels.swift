import Foundation

public enum CompressionSegmentKind: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
}

public enum CompressionVersionScopeKind: String, Codable, CaseIterable, Sendable {
    case round
    case range
    case assembled
}

public enum CompressionVersionOperation: String, Codable, CaseIterable, Sendable {
    case original
    case manualEdit = "manual_edit"
    case defaultCompression = "default_compression"
    case customCompression = "custom_compression"
    case systemCompression = "system_compression"
    case exclude
    case failedCompression = "failed_compression"
    case tombstone

    public var requiresInputRecord: Bool {
        switch self {
        case .defaultCompression, .customCompression, .systemCompression, .failedCompression:
            return true
        case .original, .manualEdit, .exclude, .tombstone:
            return false
        }
    }
}

public enum CompressionVersionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case historical
    case failed
    case tombstoned
}

public enum CompressionVersionSourceKind: String, Codable, CaseIterable, Sendable {
    case round
    case version
    case range
}

public enum CompressionLineageEdgeKind: String, Codable, CaseIterable, Sendable {
    case edit
    case compress
    case join
    case exclude
    case rollback
    case systemCompress = "system_compress"
}

public enum CompressionInputMode: String, Codable, CaseIterable, Sendable {
    case defaultTemplate = "default_template"
    case customTemplate = "custom_template"
    case system
}

public struct CompressionRound: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: UUID
    public var roundIndex: Int
    public var userEventID: UUID
    public var firstAssistantEventID: UUID?
    public var lastAssistantEventID: UUID?
    public var runState: String
    public var runStartedAt: Date?
    public var runFinishedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct CompressionRoundEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var roundID: UUID
    public var eventID: UUID
    public var segmentKind: CompressionSegmentKind
    public var ordinal: Int
}

public struct CompressionVersion: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: UUID
    public var scopeKind: CompressionVersionScopeKind
    public var operation: CompressionVersionOperation
    public var status: CompressionVersionStatus
    public var content: String
    public var templateID: UUID?
    public var compressionInputID: UUID?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public var canBecomeActive: Bool {
        status != .failed
            && status != .tombstoned
            && operation != .failedCompression
            && operation != .tombstone
    }

    public var emitsModelInput: Bool {
        canBecomeActive && operation != .exclude
    }

    public var isReplacement: Bool {
        switch operation {
        case .manualEdit, .defaultCompression, .customCompression, .systemCompression, .exclude:
            return true
        case .original, .failedCompression, .tombstone:
            return false
        }
    }

    public var isVisibleInNormalHistory: Bool {
        status != .tombstoned && operation != .tombstone
    }
}

public struct CompressionVersionSource: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var versionID: UUID
    public var sourceKind: CompressionVersionSourceKind
    public var sourceID: UUID
    public var ordinal: Int
}

public struct CompressionLineageEdge: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var parentVersionID: UUID
    public var childVersionID: UUID
    public var edgeKind: CompressionLineageEdgeKind
    public var createdAt: Date
}

public struct CompressionActiveVersion: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: UUID
    public var roundID: UUID?
    public var rangeID: UUID?
    public var activeVersionID: UUID
}

public struct CompressionInputRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: UUID
    public var mode: CompressionInputMode
    public var templateID: UUID?
    public var userInstruction: String
    public var inputSnapshot: String
    public var providerName: String
    public var providerModel: String
    public var createdAt: Date
}

public struct CompressionTombstone: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var versionID: UUID
    public var reason: String
    public var replacedByVersionID: UUID?
    public var createdAt: Date
}

public struct ConversationCompressionState: Equatable, Sendable {
    public var rounds: [CompressionRound]
    public var roundEvents: [CompressionRoundEvent]
    public var versions: [CompressionVersion]
    public var versionSources: [CompressionVersionSource]
    public var lineageEdges: [CompressionLineageEdge]
    public var activeVersions: [CompressionActiveVersion]
    public var inputs: [CompressionInputRecord]
    public var tombstones: [CompressionTombstone]

    public init(
        rounds: [CompressionRound] = [],
        roundEvents: [CompressionRoundEvent] = [],
        versions: [CompressionVersion] = [],
        versionSources: [CompressionVersionSource] = [],
        lineageEdges: [CompressionLineageEdge] = [],
        activeVersions: [CompressionActiveVersion] = [],
        inputs: [CompressionInputRecord] = [],
        tombstones: [CompressionTombstone] = []
    ) {
        self.rounds = rounds
        self.roundEvents = roundEvents
        self.versions = versions
        self.versionSources = versionSources
        self.lineageEdges = lineageEdges
        self.activeVersions = activeVersions
        self.inputs = inputs
        self.tombstones = tombstones
    }
}

public enum AssembledModelInputComponent: Equatable, Sendable {
    case sourceRound(roundID: UUID, text: String)
    case version(versionID: UUID, text: String)
    case excluded(roundID: UUID)
    case pendingUserPrompt(String)

    public var emittedText: String? {
        switch self {
        case let .sourceRound(_, text), let .version(_, text), let .pendingUserPrompt(text):
            return text
        case .excluded:
            return nil
        }
    }
}

public struct AssembledModelInput: Equatable, Sendable {
    public var components: [AssembledModelInputComponent]

    public init(components: [AssembledModelInputComponent]) {
        self.components = components
    }

    public var text: String {
        components
            .compactMap(\.emittedText)
            .joined(separator: "\n\n")
    }
}
