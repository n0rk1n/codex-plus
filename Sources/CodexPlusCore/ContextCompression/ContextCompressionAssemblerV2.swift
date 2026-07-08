import Foundation

public struct ContextCompressionAssemblyInput: Equatable, Sendable {
    public var conversation: ConversationSession
    public var compressionState: ConversationCompressionState
    public var pendingUserPrompt: String?

    public init(
        conversation: ConversationSession,
        compressionState: ConversationCompressionState,
        pendingUserPrompt: String? = nil
    ) {
        self.conversation = conversation
        self.compressionState = compressionState
        self.pendingUserPrompt = pendingUserPrompt
    }
}

public enum ContextCompressionAssemblerV2 {
    public static func assemble(_ input: ContextCompressionAssemblyInput) throws -> AssembledModelInput {
        let state = input.compressionState
        let rounds = state.rounds.sorted {
            if $0.roundIndex != $1.roundIndex {
                return $0.roundIndex < $1.roundIndex
            }

            return $0.id.uuidString < $1.id.uuidString
        }
        let roundIndexByID = Dictionary(uniqueKeysWithValues: rounds.enumerated().map { ($0.element.id, $0.offset) })
        let versionsByID = Dictionary(uniqueKeysWithValues: state.versions.map { ($0.id, $0) })
        let eventsByID = Dictionary(uniqueKeysWithValues: input.conversation.events.map { ($0.id, $0) })
        let roundEventsByRoundID = Dictionary(grouping: state.roundEvents, by: \.roundID)
        let activeRoundVersions = activeVersionsByRoundID(state.activeVersions, versionsByID: versionsByID)
        let activeRanges = activeRangeReplacements(
            activeVersions: state.activeVersions,
            versionSources: state.versionSources,
            versionsByID: versionsByID,
            roundIndexByID: roundIndexByID
        )
        let coveredRoundIDs = Set(activeRanges.flatMap(\.sourceRoundIDs))
        let activeRangeByFirstRoundID = Dictionary(uniqueKeysWithValues: activeRanges.map { ($0.sourceRoundIDs[0], $0) })

        var components: [AssembledModelInputComponent] = []
        for round in rounds {
            if coveredRoundIDs.contains(round.id) {
                if let range = activeRangeByFirstRoundID[round.id] {
                    append(version: range.version, fallbackRoundID: round.id, to: &components)
                }
                continue
            }

            if let activeVersion = activeRoundVersions[round.id] {
                append(version: activeVersion, fallbackRoundID: round.id, to: &components)
                continue
            }

            let sourceText = sourceText(
                for: round,
                roundEvents: roundEventsByRoundID[round.id] ?? [],
                eventsByID: eventsByID
            )
            if !sourceText.isEmpty {
                components.append(.sourceRound(roundID: round.id, text: sourceText))
            }
        }

        if let pendingPrompt = input.pendingUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pendingPrompt.isEmpty {
            components.append(.pendingUserPrompt(pendingPrompt))
        }

        return AssembledModelInput(components: components)
    }

    private static func activeVersionsByRoundID(
        _ activeVersions: [CompressionActiveVersion],
        versionsByID: [UUID: CompressionVersion]
    ) -> [UUID: CompressionVersion] {
        var result: [UUID: CompressionVersion] = [:]
        for active in activeVersions {
            guard let roundID = active.roundID,
                  let version = versionsByID[active.activeVersionID],
                  version.canBecomeActive else {
                continue
            }

            result[roundID] = version
        }
        return result
    }

    private static func activeRangeReplacements(
        activeVersions: [CompressionActiveVersion],
        versionSources: [CompressionVersionSource],
        versionsByID: [UUID: CompressionVersion],
        roundIndexByID: [UUID: Int]
    ) -> [ActiveRangeReplacement] {
        activeVersions.compactMap { active in
            guard active.rangeID != nil,
                  let version = versionsByID[active.activeVersionID],
                  version.canBecomeActive else {
                return nil
            }

            let sourceRoundIDs = versionSources
                .filter { $0.versionID == version.id && $0.sourceKind == .round }
                .sorted {
                    if $0.ordinal != $1.ordinal {
                        return $0.ordinal < $1.ordinal
                    }

                    return $0.id.uuidString < $1.id.uuidString
                }
                .map(\.sourceID)
                .filter { roundIndexByID[$0] != nil }
            guard !sourceRoundIDs.isEmpty else {
                return nil
            }

            return ActiveRangeReplacement(version: version, sourceRoundIDs: sourceRoundIDs)
        }
        .sorted {
            let lhsIndex = roundIndexByID[$0.sourceRoundIDs[0]] ?? Int.max
            let rhsIndex = roundIndexByID[$1.sourceRoundIDs[0]] ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }

            return $0.version.id.uuidString < $1.version.id.uuidString
        }
    }

    private static func append(
        version: CompressionVersion,
        fallbackRoundID: UUID,
        to components: inout [AssembledModelInputComponent]
    ) {
        if version.operation == .exclude {
            components.append(.excluded(roundID: fallbackRoundID))
            return
        }

        components.append(.version(versionID: version.id, text: version.content))
    }

    private static func sourceText(
        for round: CompressionRound,
        roundEvents: [CompressionRoundEvent],
        eventsByID: [UUID: ConversationDisplayEvent]
    ) -> String {
        let orderedEvents = roundEvents.sorted {
            if $0.ordinal != $1.ordinal {
                return $0.ordinal < $1.ordinal
            }

            return $0.id.uuidString < $1.id.uuidString
        }
        let textParts = orderedEvents.compactMap { roundEvent in
            eventsByID[roundEvent.eventID]?.modelInputText
        }

        if !textParts.isEmpty {
            return textParts.joined(separator: "\n\n")
        }

        return eventsByID[round.userEventID]?.modelInputText ?? ""
    }
}

private struct ActiveRangeReplacement {
    var version: CompressionVersion
    var sourceRoundIDs: [UUID]
}

private extension ConversationDisplayEvent {
    var modelInputText: String {
        switch self {
        case let .userPrompt(_, text),
             let .status(_, text),
             let .assistantMessage(_, text),
             let .error(_, text),
             let .parseWarning(_, text):
            return text
        case let .command(_, _, command, _):
            return command
        }
    }
}
