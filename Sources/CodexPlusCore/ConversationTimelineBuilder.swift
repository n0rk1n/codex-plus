import Foundation

public enum ConversationTimelineItem: Equatable, Identifiable, Sendable {
    case event(ConversationDisplayEvent)
    case technicalGroup(id: UUID, events: [ConversationDisplayEvent])
    case compressionSnapshot(
        ConversationContextCompressionSnapshot,
        sourceEvents: [ConversationDisplayEvent]
    )

    public var id: UUID {
        switch self {
        case let .event(event):
            return event.id
        case let .technicalGroup(id, _):
            return id
        case let .compressionSnapshot(snapshot, _):
            return snapshot.id
        }
    }
}

public struct ConversationTimelineCompressionPresentation: Equatable, Sendable {
    public var rounds: [ConversationRoundPresentation]
    public var rowsByEventID: [UUID: ConversationTimelineRowCompressionPresentation]

    public init(
        rounds: [ConversationRoundPresentation] = [],
        rowsByEventID: [UUID: ConversationTimelineRowCompressionPresentation] = [:]
    ) {
        self.rounds = rounds
        self.rowsByEventID = rowsByEventID
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

public enum ConversationTimelineBuilder {
    public static func items(from events: [ConversationDisplayEvent]) -> [ConversationTimelineItem] {
        items(from: events, compressionSnapshots: [])
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

        return ConversationTimelineCompressionPresentation(
            rounds: roundPresentations,
            rowsByEventID: rowPresentations
        )
    }

    public static func items(
        from events: [ConversationDisplayEvent],
        compressionSnapshots: [ConversationContextCompressionSnapshot]
    ) -> [ConversationTimelineItem] {
        guard !events.isEmpty || !compressionSnapshots.isEmpty else {
            return []
        }

        let sourceSnapshots = compressionSnapshots.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }

            return $0.id.uuidString < $1.id.uuidString
        }

        let visibleSnapshots = ConversationContextCompressionAssembler.rootCompressionSnapshots(from: sourceSnapshots)
        let coveredEventIDs = ConversationContextCompressionAssembler.coveredEventIDs(by: visibleSnapshots)
        let snapshotInsertionPoints = insertionPoints(
            for: events,
            snapshots: visibleSnapshots,
            allSnapshots: sourceSnapshots
        )

        var items: [ConversationTimelineItem] = []
        var technicalEvents: [ConversationDisplayEvent] = []
        var snapshotCursor = 0

        func flushTechnicalEvents() {
            guard let firstEvent = technicalEvents.first else {
                return
            }

            items.append(.technicalGroup(id: firstEvent.id, events: technicalEvents))
            technicalEvents.removeAll(keepingCapacity: true)
        }

        func appendSnapshot(at index: Int) {
            while snapshotCursor < snapshotInsertionPoints.count && snapshotInsertionPoints[snapshotCursor].index == index {
                let point = snapshotInsertionPoints[snapshotCursor]
                let sourceEvents = ConversationContextCompressionAssembler.expandedEvents(
                    for: point.snapshot,
                    in: events,
                    allSnapshots: sourceSnapshots
                )
                items.append(.compressionSnapshot(point.snapshot, sourceEvents: sourceEvents))
                snapshotCursor += 1
            }
        }

        for (index, event) in events.enumerated() {
            appendSnapshot(at: index)

            if coveredEventIDs.contains(event.id) {
                continue
            }

            if event.isTechnicalTimelineEvent {
                technicalEvents.append(event)
                continue
            }

            flushTechnicalEvents()
            items.append(.event(event))
        }

        while snapshotCursor < snapshotInsertionPoints.count && snapshotInsertionPoints[snapshotCursor].index >= events.count {
            flushTechnicalEvents()
            let point = snapshotInsertionPoints[snapshotCursor]
            let sourceEvents = ConversationContextCompressionAssembler.expandedEvents(
                for: point.snapshot,
                in: events,
                allSnapshots: sourceSnapshots
            )
            items.append(.compressionSnapshot(point.snapshot, sourceEvents: sourceEvents))
            snapshotCursor += 1
        }

        flushTechnicalEvents()
        return items
    }

    private static func insertionPoints(
        for events: [ConversationDisplayEvent],
        snapshots: [ConversationContextCompressionSnapshot],
        allSnapshots: [ConversationContextCompressionSnapshot]
    ) -> [(index: Int, snapshot: ConversationContextCompressionSnapshot)] {
        let eventsByID = Dictionary(uniqueKeysWithValues: events.enumerated().map { (index, event) in
            (event.id, index)
        })

        var points: [(index: Int, snapshot: ConversationContextCompressionSnapshot)] = []

        for snapshot in snapshots {
            let eventIDs = ConversationContextCompressionAssembler.expandedEventIDs(
                for: snapshot,
                in: allSnapshots
            )

            let indexes = eventIDs.compactMap { eventsByID[$0] }
            let insertionIndex = indexes.min() ?? events.count
            points.append((insertionIndex, snapshot))
        }

        let ordered = points.sorted {
            if $0.index != $1.index {
                return $0.index < $1.index
            }

            if $0.snapshot.createdAt != $1.snapshot.createdAt {
                return $0.snapshot.createdAt < $1.snapshot.createdAt
            }

            return $0.snapshot.id.uuidString < $1.snapshot.id.uuidString
        }
        return ordered
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
