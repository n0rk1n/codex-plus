import Foundation

public struct ConversationRoundBuildResult: Equatable, Sendable {
    public var rounds: [CompressionRound]
    public var events: [CompressionRoundEvent]

    public init(rounds: [CompressionRound], events: [CompressionRoundEvent]) {
        self.rounds = rounds
        self.events = events
    }
}

public enum ConversationRoundBuilder {
    public static func buildRounds(
        conversation: ConversationSession,
        now: Date = Date()
    ) -> ConversationRoundBuildResult {
        var rounds: [CompressionRound] = []
        var roundEvents: [CompressionRoundEvent] = []
        var current: PendingRound?

        func flushCurrentRound() {
            guard let pending = current else {
                return
            }

            let assistantEventIDs = pending.events
                .filter { $0.segmentKind == .assistant }
                .map(\.eventID)
            rounds.append(
                CompressionRound(
                    id: pending.id,
                    conversationID: conversation.id,
                    roundIndex: rounds.count,
                    userEventID: pending.userEventID,
                    firstAssistantEventID: assistantEventIDs.first,
                    lastAssistantEventID: assistantEventIDs.last,
                    runState: conversation.state.rawValue,
                    runStartedAt: nil,
                    runFinishedAt: nil,
                    createdAt: now,
                    updatedAt: now
                )
            )
            roundEvents.append(contentsOf: pending.events)
            current = nil
        }

        for event in conversation.events {
            switch event {
            case let .userPrompt(id, _):
                flushCurrentRound()
                let roundID = id
                current = PendingRound(
                    id: roundID,
                    userEventID: id,
                    events: [
                        CompressionRoundEvent(
                            id: id,
                            roundID: roundID,
                            eventID: id,
                            segmentKind: .user,
                            ordinal: 0
                        )
                    ]
                )
            case .assistantMessage, .status, .command, .error, .parseWarning:
                guard var pending = current else {
                    continue
                }

                pending.events.append(
                    CompressionRoundEvent(
                        id: event.id,
                        roundID: pending.id,
                        eventID: event.id,
                        segmentKind: .assistant,
                        ordinal: pending.events.count
                    )
                )
                current = pending
            }
        }

        flushCurrentRound()
        return ConversationRoundBuildResult(rounds: rounds, events: roundEvents)
    }
}

private struct PendingRound {
    var id: UUID
    var userEventID: UUID
    var events: [CompressionRoundEvent]
}
