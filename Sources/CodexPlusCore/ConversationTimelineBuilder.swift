import Foundation

public enum ConversationTimelineItem: Equatable, Identifiable, Sendable {
    case event(ConversationDisplayEvent)
    case technicalGroup(id: UUID, events: [ConversationDisplayEvent])

    public var id: UUID {
        switch self {
        case let .event(event):
            return event.id
        case let .technicalGroup(id, _):
            return id
        }
    }
}

public struct ConversationTimelineCompressionPresentation: Equatable, Sendable {
    public var rounds: [ConversationRoundPresentation]
    public var rowsByEventID: [UUID: ConversationTimelineRowCompressionPresentation]
    public var versionHistory: [CompressionVersionHistoryPresentation]
    public var versionHistoryByRoundID: [UUID: [CompressionVersionHistoryPresentation]]

    public init(
        rounds: [ConversationRoundPresentation] = [],
        rowsByEventID: [UUID: ConversationTimelineRowCompressionPresentation] = [:],
        versionHistory: [CompressionVersionHistoryPresentation] = [],
        versionHistoryByRoundID: [UUID: [CompressionVersionHistoryPresentation]] = [:]
    ) {
        self.rounds = rounds
        self.rowsByEventID = rowsByEventID
        self.versionHistory = versionHistory
        self.versionHistoryByRoundID = versionHistoryByRoundID
    }
}

public struct ConversationRoundPresentation: Equatable, Identifiable, Sendable {
    public var id: UUID { roundID }
    public var roundID: UUID
    public var eventIDs: [UUID]
    public var boundary: CompressionBoundaryPresentation?
    public var status: CompressionStatusPresentation?
    public var joinedRelationship: CompressionJoinedRelationshipPresentation?
    public var isDimmed: Bool

    public init(
        roundID: UUID,
        eventIDs: [UUID],
        boundary: CompressionBoundaryPresentation? = nil,
        status: CompressionStatusPresentation? = nil,
        joinedRelationship: CompressionJoinedRelationshipPresentation? = nil,
        isDimmed: Bool = false
    ) {
        self.roundID = roundID
        self.eventIDs = eventIDs
        self.boundary = boundary
        self.status = status
        self.joinedRelationship = joinedRelationship
        self.isDimmed = isDimmed
    }
}

public struct ConversationTimelineRowCompressionPresentation: Equatable, Sendable {
    public var roundID: UUID
    public var status: CompressionStatusPresentation?
    public var isDimmed: Bool

    public init(roundID: UUID, status: CompressionStatusPresentation? = nil, isDimmed: Bool = false) {
        self.roundID = roundID
        self.status = status
        self.isDimmed = isDimmed
    }
}

public struct CompressionBoundaryPresentation: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case edited
        case compressed
        case joined
        case excluded
        case failed
    }

    public var kind: Kind
    public var startRoundID: UUID
    public var endRoundID: UUID
    public var versionID: UUID

    public init(kind: Kind, startRoundID: UUID, endRoundID: UUID, versionID: UUID) {
        self.kind = kind
        self.startRoundID = startRoundID
        self.endRoundID = endRoundID
        self.versionID = versionID
    }
}

public struct CompressionStatusPresentation: Equatable, Sendable {
    public var label: String
    public var versionID: UUID?

    public init(label: String, versionID: UUID? = nil) {
        self.label = label
        self.versionID = versionID
    }
}

public struct CompressionJoinedRelationshipPresentation: Equatable, Sendable {
    public var relatedRoundIDs: [UUID]
    public var versionID: UUID

    public init(relatedRoundIDs: [UUID], versionID: UUID) {
        self.relatedRoundIDs = relatedRoundIDs
        self.versionID = versionID
    }
}

public struct CompressionVersionHistoryPresentation: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var statusLabel: String
    public var operationLabel: String
    public var sourceRoundIDs: [UUID]
    public var providerSummary: String?
    public var inputSummary: String?
    public var errorMessage: String?
    public var isActive: Bool
    public var isFailed: Bool
    public var isTombstoned: Bool
    public var createdAt: Date

    public init(
        id: UUID,
        label: String,
        statusLabel: String,
        operationLabel: String,
        sourceRoundIDs: [UUID],
        providerSummary: String? = nil,
        inputSummary: String? = nil,
        errorMessage: String? = nil,
        isActive: Bool,
        isFailed: Bool,
        isTombstoned: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.label = label
        self.statusLabel = statusLabel
        self.operationLabel = operationLabel
        self.sourceRoundIDs = sourceRoundIDs
        self.providerSummary = providerSummary
        self.inputSummary = inputSummary
        self.errorMessage = errorMessage
        self.isActive = isActive
        self.isFailed = isFailed
        self.isTombstoned = isTombstoned
        self.createdAt = createdAt
    }
}

public enum ConversationTimelineBuilder {
    public static func items(from events: [ConversationDisplayEvent]) -> [ConversationTimelineItem] {
        guard !events.isEmpty else {
            return []
        }

        var items: [ConversationTimelineItem] = []
        var technicalEvents: [ConversationDisplayEvent] = []

        func flushTechnicalEvents() {
            guard let firstEvent = technicalEvents.first else {
                return
            }

            items.append(.technicalGroup(id: firstEvent.id, events: technicalEvents))
            technicalEvents.removeAll(keepingCapacity: true)
        }

        for event in events {
            if event.isTechnicalTimelineEvent {
                technicalEvents.append(event)
                continue
            }

            flushTechnicalEvents()
            items.append(.event(event))
        }

        flushTechnicalEvents()
        return items
    }

    public static func compressionPresentation(
        conversation: ConversationSession,
        compressionState: ConversationCompressionState
    ) -> ConversationTimelineCompressionPresentation {
        _ = conversation
        let versionsByID = Dictionary(uniqueKeysWithValues: compressionState.versions.map { ($0.id, $0) })
        var activeByRoundID: [UUID: CompressionVersion] = [:]
        for active in compressionState.activeVersions {
            guard let roundID = active.roundID,
                  let version = versionsByID[active.activeVersionID],
                  version.canBecomeActive else {
                continue
            }
            activeByRoundID[roundID] = version
        }
        let rangePresentations = activeRangePresentations(
            compressionState: compressionState,
            versionsByID: versionsByID
        )
        var rangeByRoundID: [UUID: ActiveTimelineRangePresentation] = [:]
        for range in rangePresentations {
            for roundID in range.roundIDs {
                rangeByRoundID[roundID] = range
            }
        }
        let roundEventsByRoundID = Dictionary(grouping: compressionState.roundEvents, by: \.roundID)
        let sortedRounds = compressionState.rounds.sorted {
            if $0.roundIndex != $1.roundIndex {
                return $0.roundIndex < $1.roundIndex
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        var rowPresentations: [UUID: ConversationTimelineRowCompressionPresentation] = [:]
        let roundPresentations = sortedRounds.map { round in
            let eventIDs = (roundEventsByRoundID[round.id] ?? [])
                .sorted {
                    if $0.ordinal != $1.ordinal {
                        return $0.ordinal < $1.ordinal
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .map(\.eventID)
            let version = activeByRoundID[round.id]
            let range = rangeByRoundID[round.id]
            let status = version.map(statusPresentation(for:)) ?? range.map { statusPresentation(for: $0.version) }
            let boundary = version.map {
                CompressionBoundaryPresentation(
                    kind: boundaryKind(for: $0),
                    startRoundID: round.id,
                    endRoundID: round.id,
                    versionID: $0.id
                )
            } ?? range.flatMap { range in
                guard range.roundIDs.first == round.id else {
                    return nil
                }
                return CompressionBoundaryPresentation(
                    kind: boundaryKind(for: range.version),
                    startRoundID: range.roundIDs.first ?? round.id,
                    endRoundID: range.roundIDs.last ?? round.id,
                    versionID: range.version.id
                )
            }
            let joinedRelationship = range.map {
                CompressionJoinedRelationshipPresentation(relatedRoundIDs: $0.roundIDs, versionID: $0.version.id)
            }
            let isDimmed = version?.operation == .exclude
            for eventID in eventIDs {
                rowPresentations[eventID] = ConversationTimelineRowCompressionPresentation(
                    roundID: round.id,
                    status: status,
                    isDimmed: isDimmed
                )
            }
            return ConversationRoundPresentation(
                roundID: round.id,
                eventIDs: eventIDs,
                boundary: boundary,
                status: status,
                joinedRelationship: joinedRelationship,
                isDimmed: isDimmed
            )
        }

        let versionHistory = versionHistoryPresentations(
            compressionState: compressionState,
            activeVersionIDs: Set(compressionState.activeVersions.map(\.activeVersionID))
        )
        var versionHistoryByRoundID: [UUID: [CompressionVersionHistoryPresentation]] = [:]
        for item in versionHistory {
            for roundID in item.sourceRoundIDs {
                versionHistoryByRoundID[roundID, default: []].append(item)
            }
        }

        return ConversationTimelineCompressionPresentation(
            rounds: roundPresentations,
            rowsByEventID: rowPresentations,
            versionHistory: versionHistory,
            versionHistoryByRoundID: versionHistoryByRoundID
        )
    }

    private static func activeRangePresentations(
        compressionState: ConversationCompressionState,
        versionsByID: [UUID: CompressionVersion]
    ) -> [ActiveTimelineRangePresentation] {
        let sourcesByVersionID = Dictionary(grouping: compressionState.versionSources, by: \.versionID)
        return compressionState.activeVersions.compactMap { active in
            guard active.rangeID != nil,
                  let version = versionsByID[active.activeVersionID],
                  version.canBecomeActive else {
                return nil
            }

            let roundIDs = sourcesByVersionID[version.id, default: []]
                .filter { $0.sourceKind == .round }
                .sorted {
                    if $0.ordinal != $1.ordinal {
                        return $0.ordinal < $1.ordinal
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .map(\.sourceID)
            guard !roundIDs.isEmpty else {
                return nil
            }
            return ActiveTimelineRangePresentation(version: version, roundIDs: roundIDs)
        }
    }

    private static func statusPresentation(for version: CompressionVersion) -> CompressionStatusPresentation {
        CompressionStatusPresentation(label: statusLabel(for: version), versionID: version.id)
    }

    private static func versionHistoryPresentations(
        compressionState: ConversationCompressionState,
        activeVersionIDs: Set<UUID>
    ) -> [CompressionVersionHistoryPresentation] {
        let sourcesByVersionID = Dictionary(grouping: compressionState.versionSources, by: \.versionID)
        let inputsByID = Dictionary(uniqueKeysWithValues: compressionState.inputs.map { ($0.id, $0) })

        return compressionState.versions
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map { version in
                let sources = sourcesByVersionID[version.id, default: []]
                    .filter { $0.sourceKind == .round }
                    .sorted {
                        if $0.ordinal != $1.ordinal {
                            return $0.ordinal < $1.ordinal
                        }
                        return $0.id.uuidString < $1.id.uuidString
                    }
                let input = version.compressionInputID.flatMap { inputsByID[$0] }
                return CompressionVersionHistoryPresentation(
                    id: version.id,
                    label: historyLabel(for: version),
                    statusLabel: historyStatusLabel(for: version.status),
                    operationLabel: operationLabel(for: version.operation),
                    sourceRoundIDs: sources.map(\.sourceID),
                    providerSummary: providerSummary(for: input),
                    inputSummary: inputSummary(for: input?.inputSnapshot),
                    errorMessage: version.errorMessage,
                    isActive: activeVersionIDs.contains(version.id),
                    isFailed: version.status == .failed || version.operation == .failedCompression,
                    isTombstoned: version.status == .tombstoned || version.operation == .tombstone,
                    createdAt: version.createdAt
                )
            }
    }

    private static func statusLabel(for version: CompressionVersion) -> String {
        switch version.operation {
        case .manualEdit:
            return "已修订"
        case .defaultCompression, .customCompression, .systemCompression:
            return version.scopeKind == .range || version.scopeKind == .assembled ? "拼接压缩" : "已压缩"
        case .exclude:
            return "已排除模型上下文"
        case .failedCompression:
            return "压缩失败"
        case .original:
            return "原文发送"
        case .tombstone:
            return "压缩失败"
        }
    }

    private static func historyLabel(for version: CompressionVersion) -> String {
        if version.status == .tombstoned || version.operation == .tombstone {
            return "已废弃分支"
        }
        return statusLabel(for: version)
    }

    private static func historyStatusLabel(for status: CompressionVersionStatus) -> String {
        switch status {
        case .active:
            return "活动版本"
        case .historical:
            return "历史版本"
        case .failed:
            return "失败尝试"
        case .tombstoned:
            return "已废弃"
        }
    }

    private static func operationLabel(for operation: CompressionVersionOperation) -> String {
        switch operation {
        case .original:
            return "原文"
        case .manualEdit:
            return "手动修订"
        case .defaultCompression:
            return "默认压缩"
        case .customCompression:
            return "自定义压缩"
        case .systemCompression:
            return "系统压缩"
        case .exclude:
            return "排除模型上下文"
        case .failedCompression:
            return "压缩失败"
        case .tombstone:
            return "废弃分支"
        }
    }

    private static func providerSummary(for input: CompressionInputRecord?) -> String? {
        guard let input else {
            return nil
        }
        let provider = input.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = input.providerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (provider.isEmpty, model.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return provider
        case (true, false):
            return model
        case (false, false):
            return "\(provider) / \(model)"
        }
    }

    private static func inputSummary(for inputSnapshot: String?) -> String? {
        guard let inputSnapshot else {
            return nil
        }
        let summary = inputSnapshot
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !summary.isEmpty else {
            return nil
        }
        if summary.count <= 120 {
            return summary
        }
        return String(summary.prefix(117)) + "..."
    }

    private static func boundaryKind(for version: CompressionVersion) -> CompressionBoundaryPresentation.Kind {
        switch version.operation {
        case .manualEdit:
            return .edited
        case .defaultCompression, .customCompression, .systemCompression:
            return version.scopeKind == .range || version.scopeKind == .assembled ? .joined : .compressed
        case .exclude:
            return .excluded
        case .failedCompression, .tombstone:
            return .failed
        case .original:
            return .compressed
        }
    }
}

private struct ActiveTimelineRangePresentation {
    var version: CompressionVersion
    var roundIDs: [UUID]
}
