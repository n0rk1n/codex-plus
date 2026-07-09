import Foundation

public enum ContextCompressionServiceError: Error, Equatable, Sendable {
    case roundNotFound(UUID)
    case noRoundsSelected
    case providerDidNotStart
}

public enum ContextCompressionServiceResult: Equatable, Sendable {
    case success(CompressionVersion)
    case failure(CompressionVersion)
}

public final class ContextCompressionService: @unchecked Sendable {
    private let repository: any ContextCompressionRepository
    private let executionProvider: any CompressionExecutionProvider
    private let idGenerator: @Sendable () -> UUID
    private let now: @Sendable () -> Date

    public init(
        repository: any ContextCompressionRepository,
        executionProvider: any CompressionExecutionProvider,
        idGenerator: @escaping @Sendable () -> UUID = { UUID() },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.executionProvider = executionProvider
        self.idGenerator = idGenerator
        self.now = now
    }

    @discardableResult
    public func editRound(
        conversation: ConversationSession,
        roundID: UUID,
        content: String
    ) throws -> CompressionVersion {
        let state = try repository.loadCompressionState(conversationID: conversation.id)
        guard state.rounds.contains(where: { $0.id == roundID }) else {
            throw ContextCompressionServiceError.roundNotFound(roundID)
        }

        let version = makeVersion(
            conversationID: conversation.id,
            scopeKind: .round,
            operation: .manualEdit,
            status: .active,
            content: content,
            templateID: nil,
            compressionInputID: nil,
            errorMessage: nil
        )
        try saveVersion(
            version,
            state: state,
            sourceRoundIDs: [roundID],
            edgeKind: .edit,
            activeRoundID: roundID,
            activeRangeID: nil
        )
        return version
    }

    @discardableResult
    public func excludeRound(
        conversation: ConversationSession,
        roundID: UUID
    ) throws -> CompressionVersion {
        let state = try repository.loadCompressionState(conversationID: conversation.id)
        guard state.rounds.contains(where: { $0.id == roundID }) else {
            throw ContextCompressionServiceError.roundNotFound(roundID)
        }

        let version = makeVersion(
            conversationID: conversation.id,
            scopeKind: .round,
            operation: .exclude,
            status: .active,
            content: "",
            templateID: nil,
            compressionInputID: nil,
            errorMessage: nil
        )
        try saveVersion(
            version,
            state: state,
            sourceRoundIDs: [roundID],
            edgeKind: .exclude,
            activeRoundID: roundID,
            activeRangeID: nil
        )
        return version
    }

    public func startCompression(
        conversation: ConversationSession,
        roundIDs: [UUID],
        mode: CompressionInputMode,
        template: PromptTemplate,
        userInstruction: String,
        workingDirectoryURL: URL,
        permissionMode: PermissionMode = .semiAutomatic,
        onFinish: @escaping @Sendable (ContextCompressionServiceResult) -> Void
    ) throws -> (any ExecutionHandle)? {
        guard !roundIDs.isEmpty else {
            throw ContextCompressionServiceError.noRoundsSelected
        }

        let state = try repository.loadCompressionState(conversationID: conversation.id)
        let sortedRoundIDs = try sortedSelectedRoundIDs(roundIDs, state: state)
        let sourceText = selectedCurrentInputText(
            conversation: conversation,
            state: state,
            selectedRoundIDs: sortedRoundIDs
        )
        let scopeKind: CompressionVersionScopeKind = sortedRoundIDs.count == 1 ? .round : .range
        return try startProviderCompression(
            conversationID: conversation.id,
            state: state,
            selectedRoundIDs: sortedRoundIDs,
            sourceText: sourceText,
            mode: mode,
            scopeKind: scopeKind,
            template: template,
            userInstruction: userInstruction,
            workingDirectoryURL: workingDirectoryURL,
            permissionMode: permissionMode,
            activeRoundID: sortedRoundIDs.count == 1 ? sortedRoundIDs[0] : nil,
            activateAsRange: sortedRoundIDs.count > 1,
            onFinish: onFinish
        )
    }

    public func startAssembledSystemCompression(
        conversation: ConversationSession,
        sourceText: String,
        sourceRoundIDs: [UUID],
        template: PromptTemplate,
        workingDirectoryURL: URL,
        permissionMode: PermissionMode = .semiAutomatic,
        onFinish: @escaping @Sendable (ContextCompressionServiceResult) -> Void
    ) throws -> (any ExecutionHandle)? {
        guard !sourceRoundIDs.isEmpty else {
            throw ContextCompressionServiceError.noRoundsSelected
        }

        let state = try repository.loadCompressionState(conversationID: conversation.id)
        let sortedRoundIDs = try sortedSelectedRoundIDs(sourceRoundIDs, state: state)
        return try startProviderCompression(
            conversationID: conversation.id,
            state: state,
            selectedRoundIDs: sortedRoundIDs,
            sourceText: sourceText,
            mode: .system,
            scopeKind: .assembled,
            template: template,
            userInstruction: "",
            workingDirectoryURL: workingDirectoryURL,
            permissionMode: permissionMode,
            activeRoundID: nil,
            activateAsRange: true,
            onFinish: onFinish
        )
    }

    private func startProviderCompression(
        conversationID: UUID,
        state: ConversationCompressionState,
        selectedRoundIDs: [UUID],
        sourceText: String,
        mode: CompressionInputMode,
        scopeKind: CompressionVersionScopeKind,
        template: PromptTemplate,
        userInstruction: String,
        workingDirectoryURL: URL,
        permissionMode: PermissionMode,
        activeRoundID: UUID?,
        activateAsRange: Bool,
        onFinish: @escaping @Sendable (ContextCompressionServiceResult) -> Void
    ) throws -> (any ExecutionHandle)? {
        let request = CompressionExecutionRequest(
            sourceText: sourceText,
            template: template,
            userInstruction: userInstruction,
            workingDirectoryURL: workingDirectoryURL,
            permissionMode: permissionMode
        )

        let handle = executionProvider.startCompression(request: request) { [repository, idGenerator, now] result in
            do {
                let storedResult = try Self.persistProviderResult(
                    result,
                    repository: repository,
                    idGenerator: idGenerator,
                    now: now,
                    conversationID: conversationID,
                    state: state,
                    selectedRoundIDs: selectedRoundIDs,
                    mode: mode,
                    scopeKind: scopeKind,
                    templateID: template.id,
                    userInstruction: userInstruction,
                    inputSnapshot: sourceText,
                    activeRoundID: activeRoundID,
                    activateAsRange: activateAsRange
                )
                onFinish(storedResult)
            } catch {
                let failure = Self.makeFailureVersion(
                    repository: repository,
                    idGenerator: idGenerator,
                    now: now,
                    conversationID: conversationID,
                    state: state,
                    selectedRoundIDs: selectedRoundIDs,
                    mode: mode,
                    scopeKind: scopeKind,
                    templateID: template.id,
                    userInstruction: userInstruction,
                    inputSnapshot: sourceText,
                    message: String(describing: error),
                    providerName: "ContextCompressionService",
                    providerModel: "unknown"
                )
                if let failure {
                    onFinish(.failure(failure))
                }
            }
        }

        guard handle != nil else {
            throw ContextCompressionServiceError.providerDidNotStart
        }
        return handle
    }

    private static func persistProviderResult(
        _ result: CompressionExecutionResult,
        repository: any ContextCompressionRepository,
        idGenerator: @Sendable () -> UUID,
        now: @Sendable () -> Date,
        conversationID: UUID,
        state: ConversationCompressionState,
        selectedRoundIDs: [UUID],
        mode: CompressionInputMode,
        scopeKind: CompressionVersionScopeKind,
        templateID: UUID,
        userInstruction: String,
        inputSnapshot: String,
        activeRoundID: UUID?,
        activateAsRange: Bool
    ) throws -> ContextCompressionServiceResult {
        switch result {
        case let .success(success):
            let input = makeInput(
                idGenerator: idGenerator,
                now: now,
                conversationID: conversationID,
                mode: mode,
                templateID: templateID,
                userInstruction: userInstruction,
                inputSnapshot: inputSnapshot,
                providerName: success.providerName,
                providerModel: success.providerModel
            )
            try repository.saveCompressionInput(input)

            let version = makeVersion(
                idGenerator: idGenerator,
                now: now,
                conversationID: conversationID,
                scopeKind: scopeKind,
                operation: operation(for: mode),
                status: .active,
                content: success.output,
                templateID: templateID,
                compressionInputID: input.id,
                errorMessage: nil
            )
            try saveVersion(
                version,
                repository: repository,
                idGenerator: idGenerator,
                now: now,
                state: state,
                sourceRoundIDs: selectedRoundIDs,
                edgeKind: mode == .system ? .systemCompress : .compress,
                activeRoundID: activeRoundID,
                activeRangeID: activateAsRange ? version.id : nil
            )
            return .success(version)

        case let .failure(failure):
            let version = try persistFailure(
                repository: repository,
                idGenerator: idGenerator,
                now: now,
                conversationID: conversationID,
                state: state,
                selectedRoundIDs: selectedRoundIDs,
                mode: mode,
                scopeKind: scopeKind,
                templateID: templateID,
                userInstruction: userInstruction,
                inputSnapshot: inputSnapshot,
                message: failure.message,
                providerName: failure.providerName,
                providerModel: failure.providerModel
            )
            return .failure(version)
        }
    }

    private static func persistFailure(
        repository: any ContextCompressionRepository,
        idGenerator: @Sendable () -> UUID,
        now: @Sendable () -> Date,
        conversationID: UUID,
        state: ConversationCompressionState,
        selectedRoundIDs: [UUID],
        mode: CompressionInputMode,
        scopeKind: CompressionVersionScopeKind,
        templateID: UUID,
        userInstruction: String,
        inputSnapshot: String,
        message: String,
        providerName: String,
        providerModel: String
    ) throws -> CompressionVersion {
        let input = makeInput(
            idGenerator: idGenerator,
            now: now,
            conversationID: conversationID,
            mode: mode,
            templateID: templateID,
            userInstruction: userInstruction,
            inputSnapshot: inputSnapshot,
            providerName: providerName,
            providerModel: providerModel
        )
        try repository.saveCompressionInput(input)

        let version = makeVersion(
            idGenerator: idGenerator,
            now: now,
            conversationID: conversationID,
            scopeKind: scopeKind,
            operation: .failedCompression,
            status: .failed,
            content: "",
            templateID: templateID,
            compressionInputID: input.id,
            errorMessage: message
        )
        try repository.saveCompressionVersion(version)
        try repository.saveCompressionVersionSources(
            makeSources(
                idGenerator: idGenerator,
                versionID: version.id,
                sourceRoundIDs: selectedRoundIDs
            )
        )
        try repository.saveCompressionLineageEdges(
            lineageEdges(
                idGenerator: idGenerator,
                now: now,
                state: state,
                sourceRoundIDs: selectedRoundIDs,
                childVersionID: version.id,
                edgeKind: mode == .system ? .systemCompress : .compress
            )
        )
        return version
    }

    private static func makeFailureVersion(
        repository: any ContextCompressionRepository,
        idGenerator: @Sendable () -> UUID,
        now: @Sendable () -> Date,
        conversationID: UUID,
        state: ConversationCompressionState,
        selectedRoundIDs: [UUID],
        mode: CompressionInputMode,
        scopeKind: CompressionVersionScopeKind,
        templateID: UUID,
        userInstruction: String,
        inputSnapshot: String,
        message: String,
        providerName: String,
        providerModel: String
    ) -> CompressionVersion? {
        try? persistFailure(
            repository: repository,
            idGenerator: idGenerator,
            now: now,
            conversationID: conversationID,
            state: state,
            selectedRoundIDs: selectedRoundIDs,
            mode: mode,
            scopeKind: scopeKind,
            templateID: templateID,
            userInstruction: userInstruction,
            inputSnapshot: inputSnapshot,
            message: message,
            providerName: providerName,
            providerModel: providerModel
        )
    }

    private func saveVersion(
        _ version: CompressionVersion,
        state: ConversationCompressionState,
        sourceRoundIDs: [UUID],
        edgeKind: CompressionLineageEdgeKind,
        activeRoundID: UUID?,
        activeRangeID: UUID?
    ) throws {
        try Self.saveVersion(
            version,
            repository: repository,
            idGenerator: idGenerator,
            now: now,
            state: state,
            sourceRoundIDs: sourceRoundIDs,
            edgeKind: edgeKind,
            activeRoundID: activeRoundID,
            activeRangeID: activeRangeID
        )
    }

    private static func saveVersion(
        _ version: CompressionVersion,
        repository: any ContextCompressionRepository,
        idGenerator: @Sendable () -> UUID,
        now: @Sendable () -> Date,
        state: ConversationCompressionState,
        sourceRoundIDs: [UUID],
        edgeKind: CompressionLineageEdgeKind,
        activeRoundID: UUID?,
        activeRangeID: UUID?
    ) throws {
        let previousActiveVersions = activeVersions(
            in: state,
            sourceRoundIDs: sourceRoundIDs,
            activeRoundID: activeRoundID,
            activeRangeID: activeRangeID
        )
        for previous in previousActiveVersions {
            var historical = previous
            historical.status = .historical
            historical.updatedAt = now()
            try repository.saveCompressionVersion(historical)
        }

        try repository.saveCompressionVersion(version)
        try repository.saveCompressionVersionSources(
            makeSources(
                idGenerator: idGenerator,
                versionID: version.id,
                sourceRoundIDs: sourceRoundIDs
            )
        )
        try repository.saveCompressionLineageEdges(
            previousActiveVersions.map { previous in
                CompressionLineageEdge(
                    id: idGenerator(),
                    parentVersionID: previous.id,
                    childVersionID: version.id,
                    edgeKind: edgeKind,
                    createdAt: now()
                )
            }
        )

        try repository.setActiveCompressionVersion(
            CompressionActiveVersion(
                id: idGenerator(),
                conversationID: version.conversationID,
                roundID: activeRoundID,
                rangeID: activeRangeID,
                activeVersionID: version.id
            )
        )
    }

    private func makeVersion(
        conversationID: UUID,
        scopeKind: CompressionVersionScopeKind,
        operation: CompressionVersionOperation,
        status: CompressionVersionStatus,
        content: String,
        templateID: UUID?,
        compressionInputID: UUID?,
        errorMessage: String?
    ) -> CompressionVersion {
        Self.makeVersion(
            idGenerator: idGenerator,
            now: now,
            conversationID: conversationID,
            scopeKind: scopeKind,
            operation: operation,
            status: status,
            content: content,
            templateID: templateID,
            compressionInputID: compressionInputID,
            errorMessage: errorMessage
        )
    }

    private static func makeVersion(
        idGenerator: @Sendable () -> UUID,
        now: @Sendable () -> Date,
        conversationID: UUID,
        scopeKind: CompressionVersionScopeKind,
        operation: CompressionVersionOperation,
        status: CompressionVersionStatus,
        content: String,
        templateID: UUID?,
        compressionInputID: UUID?,
        errorMessage: String?
    ) -> CompressionVersion {
        let timestamp = now()
        return CompressionVersion(
            id: idGenerator(),
            conversationID: conversationID,
            scopeKind: scopeKind,
            operation: operation,
            status: status,
            content: content,
            templateID: templateID,
            compressionInputID: compressionInputID,
            errorMessage: errorMessage,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }

    private static func makeInput(
        idGenerator: @Sendable () -> UUID,
        now: @Sendable () -> Date,
        conversationID: UUID,
        mode: CompressionInputMode,
        templateID: UUID,
        userInstruction: String,
        inputSnapshot: String,
        providerName: String,
        providerModel: String
    ) -> CompressionInputRecord {
        CompressionInputRecord(
            id: idGenerator(),
            conversationID: conversationID,
            mode: mode,
            templateID: templateID,
            userInstruction: userInstruction,
            inputSnapshot: inputSnapshot,
            providerName: providerName,
            providerModel: providerModel,
            createdAt: now()
        )
    }

    private static func makeSources(
        idGenerator: @Sendable () -> UUID,
        versionID: UUID,
        sourceRoundIDs: [UUID]
    ) -> [CompressionVersionSource] {
        sourceRoundIDs.enumerated().map { index, roundID in
            CompressionVersionSource(
                id: idGenerator(),
                versionID: versionID,
                sourceKind: .round,
                sourceID: roundID,
                ordinal: index
            )
        }
    }

    private static func lineageEdges(
        idGenerator: @Sendable () -> UUID,
        now: @Sendable () -> Date,
        state: ConversationCompressionState,
        sourceRoundIDs: [UUID],
        childVersionID: UUID,
        edgeKind: CompressionLineageEdgeKind
    ) -> [CompressionLineageEdge] {
        activeVersions(in: state, sourceRoundIDs: sourceRoundIDs, activeRoundID: nil, activeRangeID: nil)
            .map { parent in
                CompressionLineageEdge(
                    id: idGenerator(),
                    parentVersionID: parent.id,
                    childVersionID: childVersionID,
                    edgeKind: edgeKind,
                    createdAt: now()
                )
            }
    }

    private static func activeVersions(
        in state: ConversationCompressionState,
        sourceRoundIDs: [UUID],
        activeRoundID: UUID?,
        activeRangeID: UUID?
    ) -> [CompressionVersion] {
        let versionsByID = Dictionary(uniqueKeysWithValues: state.versions.map { ($0.id, $0) })
        let selectedRoundIDs = Set(sourceRoundIDs)
        let sourcesByVersionID = Dictionary(grouping: state.versionSources, by: \.versionID)
        var result: [CompressionVersion] = []
        var seenIDs = Set<UUID>()

        for active in state.activeVersions {
            let isSameActiveSlot = active.roundID == activeRoundID && active.rangeID == activeRangeID
            let coversSelectedRound = active.roundID.map { selectedRoundIDs.contains($0) } ?? false
            let overlapsSelectedRange = sourcesByVersionID[active.activeVersionID, default: []]
                .contains { $0.sourceKind == .round && selectedRoundIDs.contains($0.sourceID) }
            guard isSameActiveSlot || coversSelectedRound || overlapsSelectedRange,
                  let version = versionsByID[active.activeVersionID],
                  !seenIDs.contains(version.id) else {
                continue
            }

            result.append(version)
            seenIDs.insert(version.id)
        }

        return result
    }

    private func sortedSelectedRoundIDs(
        _ roundIDs: [UUID],
        state: ConversationCompressionState
    ) throws -> [UUID] {
        let requested = Set(roundIDs)
        let sortedRounds = state.rounds.sorted {
            if $0.roundIndex != $1.roundIndex {
                return $0.roundIndex < $1.roundIndex
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let selected = sortedRounds.filter { requested.contains($0.id) }.map(\.id)
        if let missing = roundIDs.first(where: { !selected.contains($0) }) {
            throw ContextCompressionServiceError.roundNotFound(missing)
        }
        return selected
    }

    private func selectedCurrentInputText(
        conversation: ConversationSession,
        state: ConversationCompressionState,
        selectedRoundIDs: [UUID]
    ) -> String {
        let selected = Set(selectedRoundIDs)
        let versionsByID = Dictionary(uniqueKeysWithValues: state.versions.map { ($0.id, $0) })
        let eventsByID = Dictionary(uniqueKeysWithValues: conversation.events.map { ($0.id, $0) })
        let roundEventsByRoundID = Dictionary(grouping: state.roundEvents, by: \.roundID)
        let sourcesByVersionID = Dictionary(grouping: state.versionSources, by: \.versionID)
        var activeRoundVersions: [UUID: CompressionVersion] = [:]
        for active in state.activeVersions {
            guard let roundID = active.roundID,
                  let version = versionsByID[active.activeVersionID],
                  version.canBecomeActive else {
                continue
            }
            activeRoundVersions[roundID] = version
        }
        let activeRanges = state.activeVersions.compactMap { active -> ActiveCompressionRange? in
            guard active.rangeID != nil,
                  let version = versionsByID[active.activeVersionID],
                  version.canBecomeActive else {
                return nil
            }

            let sourceRoundIDs = sourcesByVersionID[version.id, default: []]
                .filter { $0.sourceKind == .round }
                .sorted {
                    if $0.ordinal != $1.ordinal {
                        return $0.ordinal < $1.ordinal
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .map(\.sourceID)
            guard !sourceRoundIDs.isEmpty else {
                return nil
            }
            return ActiveCompressionRange(version: version, sourceRoundIDs: sourceRoundIDs)
        }
        let activeRangeByFirstRoundID = Dictionary(
            uniqueKeysWithValues: activeRanges.map { ($0.sourceRoundIDs[0], $0) }
        )
        let coveredRoundIDs = Set(activeRanges.flatMap(\.sourceRoundIDs))

        var parts: [String] = []
        let rounds = state.rounds.sorted {
            if $0.roundIndex != $1.roundIndex {
                return $0.roundIndex < $1.roundIndex
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        for round in rounds where selected.contains(round.id) {
            if coveredRoundIDs.contains(round.id) {
                if let range = activeRangeByFirstRoundID[round.id], range.version.emitsModelInput {
                    parts.append(range.version.content)
                }
                continue
            }

            if let version = activeRoundVersions[round.id] {
                if version.emitsModelInput {
                    parts.append(version.content)
                }
                continue
            }

            let source = sourceText(
                round: round,
                roundEvents: roundEventsByRoundID[round.id] ?? [],
                eventsByID: eventsByID
            )
            if !source.isEmpty {
                parts.append(source)
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private func sourceText(
        round: CompressionRound,
        roundEvents: [CompressionRoundEvent],
        eventsByID: [UUID: ConversationDisplayEvent]
    ) -> String {
        let orderedEvents = roundEvents.sorted {
            if $0.ordinal != $1.ordinal {
                return $0.ordinal < $1.ordinal
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let parts = orderedEvents.compactMap { roundEvent in
            eventsByID[roundEvent.eventID]?.modelInputText
        }
        if !parts.isEmpty {
            return parts.joined(separator: "\n\n")
        }
        return eventsByID[round.userEventID]?.modelInputText ?? ""
    }

    private static func operation(for mode: CompressionInputMode) -> CompressionVersionOperation {
        switch mode {
        case .defaultTemplate:
            return .defaultCompression
        case .customTemplate:
            return .customCompression
        case .system:
            return .systemCompression
        }
    }
}

private struct ActiveCompressionRange {
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
