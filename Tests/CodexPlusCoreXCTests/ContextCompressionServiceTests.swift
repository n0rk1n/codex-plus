import Foundation
import XCTest
@testable import CodexPlusCore

final class ContextCompressionServiceTests: XCTestCase {
    func testManualEditCreatesActiveRoundVersionAndLineage() throws {
        let fixture = conversationFixture(["A", "B"])
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(rounds: fixture.rounds, roundEvents: fixture.roundEvents)
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: ManualCompressionExecutionProvider(),
            idGenerator: IncrementingUUIDGenerator(start: 500).next,
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        let version = try service.editRound(
            conversation: fixture.conversation,
            roundID: fixture.rounds[0].id,
            content: "只保留 A 的关键一句"
        )

        XCTAssertEqual(version.operation, .manualEdit)
        XCTAssertEqual(version.status, .active)
        XCTAssertEqual(version.content, "只保留 A 的关键一句")
        XCTAssertEqual(repository.savedVersions.map(\.id), [version.id])
        XCTAssertEqual(repository.savedSources.map(\.sourceID), [fixture.rounds[0].id])
        XCTAssertEqual(repository.activeVersions.last?.roundID, fixture.rounds[0].id)
        XCTAssertEqual(repository.activeVersions.last?.activeVersionID, version.id)
    }

    func testManualEditMarksPreviousActiveVersionHistoricalAndAddsLineage() throws {
        let fixture = conversationFixture(["A"])
        let previous = version(id: uuid(300), conversationID: fixture.conversation.id, operation: .manualEdit, status: .active, content: "旧版本")
        let previousActive = CompressionActiveVersion(
            id: uuid(301),
            conversationID: fixture.conversation.id,
            roundID: fixture.rounds[0].id,
            rangeID: nil,
            activeVersionID: previous.id
        )
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [previous],
                activeVersions: [previousActive]
            )
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: ManualCompressionExecutionProvider(),
            idGenerator: IncrementingUUIDGenerator(start: 600).next,
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let next = try service.editRound(
            conversation: fixture.conversation,
            roundID: fixture.rounds[0].id,
            content: "新版本"
        )

        XCTAssertEqual(repository.savedVersions.first(where: { $0.id == previous.id })?.status, .historical)
        XCTAssertEqual(repository.savedLineageEdges.last?.parentVersionID, previous.id)
        XCTAssertEqual(repository.savedLineageEdges.last?.childVersionID, next.id)
        XCTAssertEqual(repository.savedLineageEdges.last?.edgeKind, .edit)
    }

    func testManualSegmentEditReplacesOnlySelectedSegmentInsideRoundVersion() throws {
        let fixture = conversationFixture(["A"])
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(rounds: fixture.rounds, roundEvents: fixture.roundEvents)
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: ManualCompressionExecutionProvider(),
            idGenerator: IncrementingUUIDGenerator(start: 650).next,
            now: { Date(timeIntervalSince1970: 2_500) }
        )

        let userEdited = try service.editRoundSegment(
            conversation: fixture.conversation,
            roundID: fixture.rounds[0].id,
            segmentKind: .user,
            content: "User A edited"
        )

        XCTAssertEqual(userEdited.content, "User A edited\n\nAssistant A")

        let assistantEdited = try service.editRoundSegment(
            conversation: fixture.conversation,
            roundID: fixture.rounds[0].id,
            segmentKind: .assistant,
            content: "Assistant A edited"
        )

        XCTAssertEqual(assistantEdited.content, "User A\n\nAssistant A edited")
    }

    func testExcludeRoundCreatesNonEmittingActiveVersion() throws {
        let fixture = conversationFixture(["A", "B"])
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(rounds: fixture.rounds, roundEvents: fixture.roundEvents)
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: ManualCompressionExecutionProvider(),
            idGenerator: IncrementingUUIDGenerator(start: 700).next,
            now: { Date(timeIntervalSince1970: 3_000) }
        )

        let version = try service.excludeRound(
            conversation: fixture.conversation,
            roundID: fixture.rounds[0].id
        )

        XCTAssertEqual(version.operation, .exclude)
        XCTAssertFalse(version.emitsModelInput)
        XCTAssertEqual(version.content, "")
        XCTAssertEqual(repository.savedSources.map(\.sourceID), [fixture.rounds[0].id])
        XCTAssertTrue(repository.savedLineageEdges.isEmpty)
        let assembled = try ContextCompressionAssemblerV2.assemble(
            ContextCompressionAssemblyInput(
                conversation: fixture.conversation,
                compressionState: repository.state
            )
        )
        XCTAssertEqual(assembled.text, "User B\n\nAssistant B")
    }

    func testSuccessfulProviderCompressionPersistsInputRangeVersionAndActivatesIt() throws {
        let fixture = conversationFixture(["A", "B", "C"])
        let provider = ManualCompressionExecutionProvider()
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(rounds: fixture.rounds, roundEvents: fixture.roundEvents)
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: provider,
            idGenerator: IncrementingUUIDGenerator(start: 800).next,
            now: { Date(timeIntervalSince1970: 4_000) }
        )
        let resultBox = CompressionServiceResultBox()

        let handle = try service.startCompression(
            conversation: fixture.conversation,
            roundIDs: [fixture.rounds[0].id, fixture.rounds[1].id],
            mode: .defaultTemplate,
            template: compressionTemplate(),
            userInstruction: "保留用户决策",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { resultBox.set($0) }
        )

        XCTAssertNotNil(handle)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(provider.requests.first?.sourceText, "User A\n\nAssistant A\n\nUser B\n\nAssistant B")
        XCTAssertEqual(provider.requests.first?.userInstruction, "保留用户决策")

        provider.finish(
            .success(
                CompressionExecutionSuccess(
                    output: "A-B 压缩结果",
                    providerName: "Codex CLI",
                    providerModel: "gpt-test"
                )
            )
        )

        let savedVersion = try XCTUnwrap(repository.savedVersions.last)
        XCTAssertEqual(savedVersion.scopeKind, .range)
        XCTAssertEqual(savedVersion.operation, .defaultCompression)
        XCTAssertEqual(savedVersion.status, .active)
        XCTAssertEqual(savedVersion.content, "A-B 压缩结果")
        XCTAssertEqual(repository.savedInputs.last?.inputSnapshot, "User A\n\nAssistant A\n\nUser B\n\nAssistant B")
        XCTAssertEqual(repository.savedInputs.last?.providerName, "Codex CLI")
        XCTAssertEqual(repository.savedSources.map(\.sourceID), [fixture.rounds[0].id, fixture.rounds[1].id])
        XCTAssertEqual(repository.activeVersions.last?.rangeID, savedVersion.id)
        XCTAssertEqual(resultBox.value(), .success(savedVersion))
    }

    func testCompressionRejectsNonContiguousRoundSelectionBeforeStartingProvider() throws {
        let fixture = conversationFixture(["A", "B", "C"])
        let provider = ManualCompressionExecutionProvider()
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(rounds: fixture.rounds, roundEvents: fixture.roundEvents)
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: provider,
            idGenerator: IncrementingUUIDGenerator(start: 850).next,
            now: { Date(timeIntervalSince1970: 4_500) }
        )

        XCTAssertThrowsError(
            try service.startCompression(
                conversation: fixture.conversation,
                roundIDs: [fixture.rounds[0].id, fixture.rounds[2].id],
                mode: .defaultTemplate,
                template: compressionTemplate(),
                userInstruction: "",
                workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
                onFinish: { _ in }
            )
        ) { error in
            XCTAssertEqual(
                error as? ContextCompressionServiceError,
                .nonContiguousRoundSelection([fixture.rounds[0].id, fixture.rounds[2].id])
            )
        }

        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertTrue(repository.savedVersions.isEmpty)
        XCTAssertTrue(repository.activeVersions.isEmpty)
    }

    func testFailedProviderCompressionPersistsFailedVersionWithoutActivatingIt() throws {
        let fixture = conversationFixture(["A"])
        let provider = ManualCompressionExecutionProvider()
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(rounds: fixture.rounds, roundEvents: fixture.roundEvents)
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: provider,
            idGenerator: IncrementingUUIDGenerator(start: 900).next,
            now: { Date(timeIntervalSince1970: 5_000) }
        )
        let resultBox = CompressionServiceResultBox()

        _ = try service.startCompression(
            conversation: fixture.conversation,
            roundIDs: [fixture.rounds[0].id],
            mode: .customTemplate,
            template: compressionTemplate(),
            userInstruction: "只保留一句",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { resultBox.set($0) }
        )

        provider.finish(
            .failure(
                CompressionExecutionFailure(
                    message: "provider failed",
                    providerName: "Codex CLI",
                    providerModel: "gpt-test"
                )
            )
        )

        let savedVersion = try XCTUnwrap(repository.savedVersions.last)
        XCTAssertEqual(savedVersion.operation, .failedCompression)
        XCTAssertEqual(savedVersion.status, .failed)
        XCTAssertEqual(savedVersion.errorMessage, "provider failed")
        XCTAssertTrue(repository.activeVersions.isEmpty)
        XCTAssertEqual(resultBox.value(), .failure(savedVersion))
    }

    func testFailedProviderCompressionKeepsPreviousActiveVersionAsModelInput() throws {
        let fixture = conversationFixture(["A"])
        let previous = version(id: uuid(910), conversationID: fixture.conversation.id, operation: .manualEdit, status: .active, content: "Still active")
        let previousActive = CompressionActiveVersion(
            id: uuid(911),
            conversationID: fixture.conversation.id,
            roundID: fixture.rounds[0].id,
            rangeID: nil,
            activeVersionID: previous.id
        )
        let provider = ManualCompressionExecutionProvider()
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [previous],
                activeVersions: [previousActive]
            )
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: provider,
            idGenerator: IncrementingUUIDGenerator(start: 920).next,
            now: { Date(timeIntervalSince1970: 5_200) }
        )

        _ = try service.startCompression(
            conversation: fixture.conversation,
            roundIDs: [fixture.rounds[0].id],
            mode: .defaultTemplate,
            template: compressionTemplate(),
            userInstruction: "",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { _ in }
        )
        provider.finish(
            .failure(
                CompressionExecutionFailure(
                    message: "provider failed",
                    providerName: "Codex CLI",
                    providerModel: "gpt-test"
                )
            )
        )

        let assembled = try ContextCompressionAssemblerV2.assemble(
            ContextCompressionAssemblyInput(conversation: fixture.conversation, compressionState: repository.state)
        )
        XCTAssertEqual(repository.savedVersions.last?.operation, .failedCompression)
        XCTAssertEqual(repository.state.activeVersions.map(\.activeVersionID), [previous.id])
        XCTAssertEqual(assembled.text, "Still active")
    }

    func testCompressionUsesCurrentActiveRangeAsProviderInputForTraceability() throws {
        let fixture = conversationFixture(["A", "B", "C"])
        let existing = CompressionVersion(
            id: uuid(950),
            conversationID: fixture.conversation.id,
            scopeKind: .range,
            operation: .defaultCompression,
            status: .active,
            content: "AMG",
            templateID: nil,
            compressionInputID: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let existingSources = fixture.rounds.enumerated().map { index, round in
            CompressionVersionSource(
                id: uuid(960 + index),
                versionID: existing.id,
                sourceKind: .round,
                sourceID: round.id,
                ordinal: index
            )
        }
        let existingActive = CompressionActiveVersion(
            id: uuid(970),
            conversationID: fixture.conversation.id,
            roundID: nil,
            rangeID: existing.id,
            activeVersionID: existing.id
        )
        let provider = ManualCompressionExecutionProvider()
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [existing],
                versionSources: existingSources,
                activeVersions: [existingActive]
            )
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: provider,
            idGenerator: IncrementingUUIDGenerator(start: 980).next,
            now: { Date(timeIntervalSince1970: 6_000) }
        )

        _ = try service.startCompression(
            conversation: fixture.conversation,
            roundIDs: fixture.rounds.map(\.id),
            mode: .system,
            template: compressionTemplate(),
            userInstruction: "",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { _ in }
        )

        XCTAssertEqual(provider.requests.first?.sourceText, "AMG")

        provider.finish(
            .success(
                CompressionExecutionSuccess(
                    output: "N",
                    providerName: "Codex CLI",
                    providerModel: "gpt-test"
                )
            )
        )

        XCTAssertEqual(repository.savedInputs.last?.inputSnapshot, "AMG")
        XCTAssertEqual(repository.savedSources.map(\.sourceKind), [.round, .round, .round, .version])
        XCTAssertEqual(repository.savedSources.last?.sourceID, existing.id)
        XCTAssertEqual(repository.savedLineageEdges.last?.parentVersionID, existing.id)
        XCTAssertEqual(repository.savedLineageEdges.last?.edgeKind, .systemCompress)
        XCTAssertEqual(repository.savedVersions.first(where: { $0.id == existing.id })?.status, .historical)
        XCTAssertEqual(repository.savedVersions.last?.operation, .systemCompression)
        XCTAssertEqual(repository.savedVersions.last?.content, "N")
    }

    func testSystemCompressionCanUseExplicitAssembledInputSnapshot() throws {
        let fixture = conversationFixture(["A", "B"])
        let provider = ManualCompressionExecutionProvider()
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(rounds: fixture.rounds, roundEvents: fixture.roundEvents)
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: provider,
            idGenerator: IncrementingUUIDGenerator(start: 1_100).next,
            now: { Date(timeIntervalSince1970: 7_000) }
        )
        let resultBox = CompressionServiceResultBox()

        _ = try service.startAssembledSystemCompression(
            conversation: fixture.conversation,
            sourceText: "Compressed history\n\nNext task",
            sourceRoundIDs: fixture.rounds.map(\.id),
            template: compressionTemplate(),
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { resultBox.set($0) }
        )

        XCTAssertEqual(provider.requests.first?.sourceText, "Compressed history\n\nNext task")

        provider.finish(
            .success(
                CompressionExecutionSuccess(
                    output: "System compressed assembled input",
                    providerName: "Codex CLI",
                    providerModel: "gpt-test"
                )
            )
        )

        let savedVersion = try XCTUnwrap(repository.savedVersions.last)
        XCTAssertEqual(savedVersion.scopeKind, .assembled)
        XCTAssertEqual(savedVersion.operation, .systemCompression)
        XCTAssertEqual(savedVersion.content, "System compressed assembled input")
        XCTAssertEqual(repository.savedInputs.last?.inputSnapshot, "Compressed history\n\nNext task")
        XCTAssertEqual(repository.savedSources.map(\.sourceID), fixture.rounds.map(\.id))
        XCTAssertEqual(repository.activeVersions.last?.rangeID, savedVersion.id)
        XCTAssertEqual(resultBox.value(), .success(savedVersion))
    }

    func testRestoreOriginalCreatesNewActiveVersionFromSourceRoundAndTombstonesPreviousActive() throws {
        let fixture = conversationFixture(["A"])
        let previous = version(id: uuid(1_200), conversationID: fixture.conversation.id, operation: .manualEdit, status: .active, content: "Edited A")
        let previousActive = CompressionActiveVersion(
            id: uuid(1_201),
            conversationID: fixture.conversation.id,
            roundID: fixture.rounds[0].id,
            rangeID: nil,
            activeVersionID: previous.id
        )
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [previous],
                activeVersions: [previousActive]
            )
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: ManualCompressionExecutionProvider(),
            idGenerator: IncrementingUUIDGenerator(start: 1_210).next,
            now: { Date(timeIntervalSince1970: 8_000) }
        )

        let restored = try service.restoreOriginalRound(conversation: fixture.conversation, roundID: fixture.rounds[0].id)

        XCTAssertEqual(restored.operation, .original)
        XCTAssertEqual(restored.status, .active)
        XCTAssertEqual(restored.content, "User A\n\nAssistant A")
        XCTAssertEqual(repository.savedLineageEdges.last?.edgeKind, .rollback)
        XCTAssertEqual(repository.savedTombstones.last?.versionID, previous.id)
        XCTAssertEqual(repository.savedTombstones.last?.replacedByVersionID, restored.id)
        XCTAssertEqual(repository.state.activeVersions.map(\.activeVersionID), [restored.id])
    }

    func testRollbackToHistoricalVersionCreatesNewActiveBranchAndTombstonesCurrentActive() throws {
        let fixture = conversationFixture(["A"])
        let historical = version(id: uuid(1_300), conversationID: fixture.conversation.id, operation: .manualEdit, status: .historical, content: "Historical A")
        let current = version(id: uuid(1_301), conversationID: fixture.conversation.id, operation: .defaultCompression, status: .active, content: "Current A")
        let currentActive = CompressionActiveVersion(
            id: uuid(1_302),
            conversationID: fixture.conversation.id,
            roundID: fixture.rounds[0].id,
            rangeID: nil,
            activeVersionID: current.id
        )
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [historical, current],
                versionSources: [
                    CompressionVersionSource(id: uuid(1_303), versionID: historical.id, sourceKind: .round, sourceID: fixture.rounds[0].id, ordinal: 0),
                    CompressionVersionSource(id: uuid(1_304), versionID: current.id, sourceKind: .round, sourceID: fixture.rounds[0].id, ordinal: 0)
                ],
                activeVersions: [currentActive]
            )
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: ManualCompressionExecutionProvider(),
            idGenerator: IncrementingUUIDGenerator(start: 1_310).next,
            now: { Date(timeIntervalSince1970: 8_500) }
        )

        let rollback = try service.rollbackToVersion(conversation: fixture.conversation, versionID: historical.id)

        XCTAssertNotEqual(rollback.id, historical.id)
        XCTAssertEqual(rollback.operation, historical.operation)
        XCTAssertEqual(rollback.status, .active)
        XCTAssertEqual(rollback.content, historical.content)
        XCTAssertEqual(repository.savedLineageEdges.last?.parentVersionID, historical.id)
        XCTAssertEqual(repository.savedLineageEdges.last?.childVersionID, rollback.id)
        XCTAssertEqual(repository.savedLineageEdges.last?.edgeKind, .rollback)
        XCTAssertEqual(repository.savedTombstones.last?.versionID, current.id)
        XCTAssertEqual(repository.state.activeVersions.map(\.activeVersionID), [rollback.id])
    }

    func testContinueCompressLatestActiveVersionUsesCurrentActiveText() throws {
        let fixture = conversationFixture(["A"])
        let current = version(id: uuid(1_400), conversationID: fixture.conversation.id, operation: .manualEdit, status: .active, content: "Latest active A")
        let currentActive = CompressionActiveVersion(
            id: uuid(1_401),
            conversationID: fixture.conversation.id,
            roundID: fixture.rounds[0].id,
            rangeID: nil,
            activeVersionID: current.id
        )
        let provider = ManualCompressionExecutionProvider()
        let repository = MemoryContextCompressionRepository(
            state: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [current],
                activeVersions: [currentActive]
            )
        )
        let service = ContextCompressionService(
            repository: repository,
            executionProvider: provider,
            idGenerator: IncrementingUUIDGenerator(start: 1_410).next,
            now: { Date(timeIntervalSince1970: 9_000) }
        )

        _ = try service.continueCompressLatestActiveVersion(
            conversation: fixture.conversation,
            roundIDs: [fixture.rounds[0].id],
            mode: .defaultTemplate,
            template: compressionTemplate(),
            userInstruction: "continue",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { _ in }
        )

        XCTAssertEqual(provider.requests.first?.sourceText, "Latest active A")
        XCTAssertEqual(provider.requests.first?.userInstruction, "continue")
    }

    private func conversationFixture(_ labels: [String]) -> (
        conversation: ConversationSession,
        rounds: [CompressionRound],
        roundEvents: [CompressionRoundEvent]
    ) {
        let conversationID = uuid(1)
        var events: [ConversationDisplayEvent] = []
        for (index, label) in labels.enumerated() {
            events.append(.userPrompt(id: uuid(10 + index * 2), text: "User \(label)"))
            events.append(.assistantMessage(id: uuid(11 + index * 2), text: "Assistant \(label)"))
        }
        let conversation = ConversationSession(
            id: conversationID,
            title: "Conversation",
            prompt: "Prompt",
            state: .completed,
            events: events
        )
        let result = ConversationRoundBuilder.buildRounds(
            conversation: conversation,
            now: Date(timeIntervalSince1970: 100)
        )
        return (conversation, result.rounds, result.events)
    }

    private func version(
        id: UUID,
        conversationID: UUID,
        operation: CompressionVersionOperation,
        status: CompressionVersionStatus,
        content: String
    ) -> CompressionVersion {
        CompressionVersion(
            id: id,
            conversationID: conversationID,
            scopeKind: .round,
            operation: operation,
            status: status,
            content: content,
            templateID: nil,
            compressionInputID: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
    }

    private func compressionTemplate() -> PromptTemplate {
        PromptTemplate(
            id: uuid(100),
            source: .systemBuiltIn,
            type: .conversationContextCompression,
            name: "压缩",
            systemPrompt: "系统压缩提示词",
            userPrompt: "用户压缩提示词",
            note: "",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private final class CompressionServiceResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: ContextCompressionServiceResult?

    func set(_ result: ContextCompressionServiceResult) {
        lock.lock()
        defer {
            lock.unlock()
        }
        storage = result
    }

    func value() -> ContextCompressionServiceResult? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storage
    }
}

private final class MemoryContextCompressionRepository: ContextCompressionRepository, @unchecked Sendable {
    var state: ConversationCompressionState
    var savedVersions: [CompressionVersion] = []
    var savedSources: [CompressionVersionSource] = []
    var savedLineageEdges: [CompressionLineageEdge] = []
    var savedInputs: [CompressionInputRecord] = []
    var savedTombstones: [CompressionTombstone] = []
    var activeVersions: [CompressionActiveVersion] = []

    init(state: ConversationCompressionState) {
        self.state = state
    }

    func loadCompressionState(conversationID: UUID) throws -> ConversationCompressionState {
        state
    }

    func replaceCompressionRounds(
        _ rounds: [CompressionRound],
        events: [CompressionRoundEvent],
        conversationID: UUID
    ) throws {
        state.rounds = rounds
        state.roundEvents = events
    }

    func saveCompressionVersion(_ version: CompressionVersion) throws {
        savedVersions.append(version)
        state.versions.removeAll { $0.id == version.id }
        state.versions.append(version)
    }

    func saveCompressionVersionSources(_ sources: [CompressionVersionSource]) throws {
        savedSources.append(contentsOf: sources)
        state.versionSources.removeAll { source in
            sources.contains { $0.id == source.id }
        }
        state.versionSources.append(contentsOf: sources)
    }

    func saveCompressionLineageEdges(_ edges: [CompressionLineageEdge]) throws {
        savedLineageEdges.append(contentsOf: edges)
        state.lineageEdges.append(contentsOf: edges)
    }

    func saveCompressionInput(_ input: CompressionInputRecord) throws {
        savedInputs.append(input)
        state.inputs.removeAll { $0.id == input.id }
        state.inputs.append(input)
    }

    func saveCompressionTombstones(_ tombstones: [CompressionTombstone]) throws {
        savedTombstones.append(contentsOf: tombstones)
        state.tombstones.append(contentsOf: tombstones)
    }

    func setActiveCompressionVersion(_ active: CompressionActiveVersion) throws {
        activeVersions.append(active)
        state.activeVersions.removeAll { existing in
            existing.conversationID == active.conversationID
                && existing.roundID == active.roundID
                && existing.rangeID == active.rangeID
        }
        state.activeVersions.append(active)
    }

    func clearActiveCompressionVersion(conversationID: UUID, roundID: UUID?, rangeID: UUID?) throws {
        state.activeVersions.removeAll { active in
            active.conversationID == conversationID
                && active.roundID == roundID
                && active.rangeID == rangeID
        }
    }
}

private final class ManualCompressionExecutionProvider: CompressionExecutionProvider, @unchecked Sendable {
    final class Handle: ExecutionHandle, @unchecked Sendable {
        func stop() {}
    }

    var requests: [CompressionExecutionRequest] = []
    private var onFinish: (@Sendable (CompressionExecutionResult) -> Void)?

    func startCompression(
        request: CompressionExecutionRequest,
        onFinish: @escaping @Sendable (CompressionExecutionResult) -> Void
    ) -> (any ExecutionHandle)? {
        requests.append(request)
        self.onFinish = onFinish
        return Handle()
    }

    func finish(_ result: CompressionExecutionResult) {
        onFinish?(result)
    }
}

private final class IncrementingUUIDGenerator: @unchecked Sendable {
    private var value: Int

    init(start: Int) {
        self.value = start
    }

    func next() -> UUID {
        defer {
            value += 1
        }
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
