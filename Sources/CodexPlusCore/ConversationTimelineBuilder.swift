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

public enum ConversationTimelineBuilder {
    public static func items(from events: [ConversationDisplayEvent]) -> [ConversationTimelineItem] {
        items(from: events, compressionSnapshots: [])
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
}
