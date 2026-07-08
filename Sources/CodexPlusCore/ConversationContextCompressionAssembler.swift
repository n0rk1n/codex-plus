import Foundation

public enum ConversationContextCompressionAssembler {
    private static func snapshotMap(
        for snapshots: [ConversationContextCompressionSnapshot]
    ) -> [UUID: ConversationContextCompressionSnapshot] {
        var map: [UUID: ConversationContextCompressionSnapshot] = [:]
        for snapshot in snapshots {
            map[snapshot.id] = snapshot
        }
        return map
    }

    public static func rootCompressionSnapshots(
        from snapshots: [ConversationContextCompressionSnapshot]
    ) -> [ConversationContextCompressionSnapshot] {
        let referenced = Set(snapshots.flatMap(\.sourceSnapshotIDs))

        return snapshots
            .filter { !referenced.contains($0.id) }
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }

                return $0.id.uuidString < $1.id.uuidString
            }
    }

    public static func sourceEventIDs(
        for snapshots: [ConversationContextCompressionSnapshot]
    ) -> Set<UUID> {
        snapshots.reduce(into: Set<UUID>()) { set, snapshot in
            set.formUnion(snapshot.sourceEventIDs)
            set.formUnion(expandedEventIDs(for: snapshot, in: snapshots))
        }
    }

    public static func coveredEventIDs(by snapshots: [ConversationContextCompressionSnapshot]) -> Set<UUID> {
        var covered: Set<UUID> = []
        for snapshot in snapshots {
            covered.formUnion(expandedEventIDs(for: snapshot, in: snapshots))
        }

        return covered
    }

    public static func expandedEventIDs(
        for snapshot: ConversationContextCompressionSnapshot,
        in snapshots: [ConversationContextCompressionSnapshot]
    ) -> [UUID] {
        let snapshotByID = snapshotMap(for: snapshots)
        var visited: Set<UUID> = []
        var pending: [ConversationContextCompressionSnapshot] = [snapshot]
        var eventIDs: [UUID] = []
        var eventIDSet: Set<UUID> = []

        while let current = pending.popLast() {
            guard !visited.contains(current.id) else {
                continue
            }

            visited.insert(current.id)

            for eventID in current.sourceEventIDs where !eventIDSet.contains(eventID) {
                eventIDSet.insert(eventID)
                eventIDs.append(eventID)
            }

            for parentID in current.sourceSnapshotIDs {
                guard let parent = snapshotByID[parentID] else {
                    continue
                }

                pending.append(parent)
            }
        }

        return eventIDs
    }

    public static func orderedEventIDs(
        for snapshot: ConversationContextCompressionSnapshot,
        in snapshots: [ConversationContextCompressionSnapshot],
        allEvents: [ConversationDisplayEvent]
    ) -> [UUID] {
        let expanded = Set(expandedEventIDs(for: snapshot, in: snapshots))
        return allEvents.enumerated()
            .filter { expanded.contains($0.element.id) }
            .map { $0.element.id }
    }

    public static func expandedEvents(
        for snapshot: ConversationContextCompressionSnapshot,
        in events: [ConversationDisplayEvent],
        allSnapshots: [ConversationContextCompressionSnapshot]
    ) -> [ConversationDisplayEvent] {
        let snapshotEventIDs = expandedEventIDs(for: snapshot, in: allSnapshots)
        let eventIndexByID = Dictionary(uniqueKeysWithValues: events.enumerated().map { ($0.element.id, $0.offset) })
        let ordered = snapshotEventIDs
            .compactMap { eventIndexByID[$0] }
            .sorted()
            .compactMap { index in events[index] }

        if !ordered.isEmpty {
            return ordered
        }

        return []
    }
}
