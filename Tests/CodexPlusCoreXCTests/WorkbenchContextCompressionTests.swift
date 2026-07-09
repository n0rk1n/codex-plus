import Foundation
import XCTest
@testable import CodexPlusCore

final class WorkbenchContextCompressionTests: XCTestCase {
    func testSavingConversationSynchronizesCompressionRounds() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let project = WorkspaceSessionGroup(
            id: uuid(1),
            path: "/tmp/project",
            displayName: "Project",
            conversationIDs: [uuid(2)],
            lastActivityAt: Date(timeIntervalSince1970: 1)
        )
        let firstUserID = uuid(10)
        let firstAssistantID = uuid(11)
        let secondUserID = uuid(12)
        let conversation = ConversationSession(
            id: uuid(2),
            title: "Conversation",
            prompt: "Prompt",
            workspacePath: project.path,
            state: .failed,
            createdAt: Date(timeIntervalSince1970: 2),
            lastActivityAt: Date(timeIntervalSince1970: 3),
            events: [
                .userPrompt(id: firstUserID, text: "A"),
                .assistantMessage(id: firstAssistantID, text: "B"),
                .userPrompt(id: secondUserID, text: "C")
            ]
        )

        try repository.saveProject(project)
        try repository.saveConversation(conversation, projectID: project.id)

        let state = try repository.loadCompressionState(conversationID: conversation.id)
        XCTAssertEqual(state.rounds.map(\.roundIndex), [0, 1])
        XCTAssertEqual(state.rounds.map(\.userEventID), [firstUserID, secondUserID])
        XCTAssertEqual(state.rounds.map(\.firstAssistantEventID), [firstAssistantID, nil])
        XCTAssertEqual(state.roundEvents.map(\.eventID), [firstUserID, firstAssistantID, secondUserID])
        XCTAssertEqual(state.roundEvents.map(\.segmentKind), [.user, .assistant, .user])

        try repository.saveConversation(conversation, projectID: project.id)

        let reloadedState = try repository.loadCompressionState(conversationID: conversation.id)
        XCTAssertEqual(reloadedState.rounds.map(\.id), [firstUserID, secondUserID])
        XCTAssertEqual(reloadedState.roundEvents.map(\.eventID), [firstUserID, firstAssistantID, secondUserID])
    }

    @MainActor
    func testFollowUpRunUsesActiveCompressedLineageWhenCompressionExists() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let project = WorkspaceSessionGroup(
            id: uuid(100),
            path: "/tmp/project",
            displayName: "Project",
            conversationIDs: [uuid(101)],
            lastActivityAt: Date(timeIntervalSince1970: 1)
        )
        let conversation = ConversationSession(
            id: uuid(101),
            title: "Conversation",
            prompt: "Initial prompt",
            workspacePath: project.path,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 2),
            lastActivityAt: Date(timeIntervalSince1970: 3),
            events: [
                .userPrompt(id: uuid(110), text: "User A"),
                .assistantMessage(id: uuid(111), text: "Assistant A")
            ]
        )

        try repository.saveProject(project)
        try repository.saveConversation(conversation, projectID: project.id)

        let compressionState = try repository.loadCompressionState(conversationID: conversation.id)
        let round = try XCTUnwrap(compressionState.rounds.first)
        let version = CompressionVersion(
            id: uuid(120),
            conversationID: conversation.id,
            scopeKind: .round,
            operation: .manualEdit,
            status: .active,
            content: "Compressed A",
            templateID: nil,
            compressionInputID: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 4),
            updatedAt: Date(timeIntervalSince1970: 5)
        )
        try repository.saveCompressionVersion(version)
        try repository.saveCompressionVersionSources([
            CompressionVersionSource(
                id: uuid(121),
                versionID: version.id,
                sourceKind: .round,
                sourceID: round.id,
                ordinal: 0
            )
        ])
        try repository.setActiveCompressionVersion(
            CompressionActiveVersion(
                id: uuid(122),
                conversationID: conversation.id,
                roundID: round.id,
                rangeID: nil,
                activeVersionID: version.id
            )
        )

        let engine = WorkbenchCompressionManualExecutionEngine()
        let store = WorkbenchStore(repository: repository, engine: engine)

        store.sendFollowUp("Next task")

        XCTAssertEqual(engine.requests.last?.prompt, "Compressed A\n\nNext task")
    }

    @MainActor
    func testSnapshotExposesCompressionStateAndAssembledPreviewForActiveConversation() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let fixture = try saveCompressedConversation(repository: repository)

        let store = WorkbenchStore(repository: repository, engine: WorkbenchCompressionManualExecutionEngine())

        XCTAssertEqual(store.snapshot.compression.rounds.map(\.id), [fixture.roundID])
        XCTAssertEqual(store.snapshot.compression.activeVersions.map(\.activeVersionID), [fixture.versionID])
        XCTAssertEqual(store.snapshot.compression.assembledPreview, "Compressed A")
        XCTAssertEqual(store.snapshot.compression.timelinePresentation.rounds.map(\.roundID), [fixture.roundID])
        XCTAssertEqual(store.snapshot.compression.timelinePresentation.rounds.first?.status?.label, "已修订")
        XCTAssertEqual(store.snapshot.compression.timelinePresentation.rowsByEventID[uuid(210)]?.status?.label, "已修订")
        XCTAssertEqual(store.snapshot.compression.timelinePresentation.rowsByEventID[uuid(211)]?.status?.label, "已修订")
        XCTAssertNil(store.snapshot.compression.sendBlockReason)
    }

    @MainActor
    func testHardLimitBudgetDisablesSubmitAndSetsCompressionBlockReason() async throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        _ = try saveCompressedConversation(repository: repository)
        let budgetProvider = WorkbenchFixedBudgetProvider(state: .hardLimit)
        let store = WorkbenchStore(
            repository: repository,
            engine: WorkbenchCompressionManualExecutionEngine(),
            contextBudgetProvider: budgetProvider
        )

        await store.refreshCompressionBudget(pendingPrompt: "Next task")

        XCTAssertEqual(store.snapshot.compression.budgetSnapshot?.state, .hardLimit)
        XCTAssertEqual(store.snapshot.compression.sendBlockReason, "需要压缩后继续")
        XCTAssertFalse(store.snapshot.canSubmitPrompt)
        XCTAssertEqual(budgetProvider.requests.last?.assembledInput, "Compressed A\n\nNext task")
    }

    @MainActor
    func testSafeBudgetClearsPreviousCompressionBlockReason() async throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        _ = try saveCompressedConversation(repository: repository)
        let budgetProvider = WorkbenchFixedBudgetProvider(state: .hardLimit)
        let store = WorkbenchStore(
            repository: repository,
            engine: WorkbenchCompressionManualExecutionEngine(),
            contextBudgetProvider: budgetProvider
        )

        await store.refreshCompressionBudget(pendingPrompt: "Next task")
        budgetProvider.state = .safe
        await store.refreshCompressionBudget(pendingPrompt: "Short task")

        XCTAssertEqual(store.snapshot.compression.budgetSnapshot?.state, .safe)
        XCTAssertNil(store.snapshot.compression.sendBlockReason)
        XCTAssertTrue(store.snapshot.canSubmitPrompt)
    }

    @MainActor
    func testSwitchingConversationClearsPreviousCompressionBudgetBlock() async throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let fixture = try saveCompressedConversation(repository: repository)
        let secondConversationID = uuid(301)
        let project = WorkspaceSessionGroup(
            id: uuid(300),
            path: "/tmp/second-project",
            displayName: "Second",
            conversationIDs: [secondConversationID],
            lastActivityAt: Date(timeIntervalSince1970: 10)
        )
        let secondConversation = ConversationSession(
            id: secondConversationID,
            title: "Second",
            prompt: "Second prompt",
            workspacePath: project.path,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 11),
            lastActivityAt: Date(timeIntervalSince1970: 12),
            events: [.userPrompt(id: uuid(302), text: "Second prompt")]
        )
        try repository.saveProject(project)
        try repository.saveConversation(secondConversation, projectID: project.id)

        let budgetProvider = WorkbenchFixedBudgetProvider(state: .hardLimit)
        let store = WorkbenchStore(
            repository: repository,
            engine: WorkbenchCompressionManualExecutionEngine(),
            contextBudgetProvider: budgetProvider
        )

        store.selectConversation(fixture.conversationID)
        await store.refreshCompressionBudget(pendingPrompt: "Next task")
        store.selectConversation(secondConversationID)

        XCTAssertNil(store.snapshot.compression.budgetSnapshot)
        XCTAssertNil(store.snapshot.compression.sendBlockReason)
        XCTAssertTrue(store.snapshot.canSubmitPrompt)
    }

    @MainActor
    func testSystemCompressActiveConversationUsesAssembledPreviewAndPendingPrompt() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        _ = try saveCompressedConversation(repository: repository)
        let compressionProvider = WorkbenchManualCompressionExecutionProvider()
        let compressionService = ContextCompressionService(
            repository: repository,
            executionProvider: compressionProvider,
            idGenerator: IncrementingUUIDGenerator(start: 400).next,
            now: { Date(timeIntervalSince1970: 20) }
        )
        let store = WorkbenchStore(
            repository: repository,
            engine: WorkbenchCompressionManualExecutionEngine(),
            contextCompressionService: compressionService
        )

        let handle = store.systemCompressActiveConversation(pendingPrompt: "Next task")

        XCTAssertNotNil(handle)
        XCTAssertEqual(compressionProvider.requests.first?.sourceText, "Compressed A\n\nNext task")
    }

    @MainActor
    func testManualSegmentEditActionRefreshesTimelinePresentation() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let fixture = try saveCompressedConversation(repository: repository)
        let compressionService = ContextCompressionService(
            repository: repository,
            executionProvider: WorkbenchManualCompressionExecutionProvider(),
            idGenerator: IncrementingUUIDGenerator(start: 500).next,
            now: { Date(timeIntervalSince1970: 30) }
        )
        let store = WorkbenchStore(
            repository: repository,
            engine: WorkbenchCompressionManualExecutionEngine(),
            contextCompressionService: compressionService
        )

        store.editCompressionSegment(roundID: fixture.roundID, segmentKind: .assistant, content: "Only useful answer")

        XCTAssertEqual(store.snapshot.compression.assembledPreview, "User A\n\nOnly useful answer")
        XCTAssertEqual(store.snapshot.compression.timelinePresentation.rounds.first?.status?.label, "已修订")
    }

    @MainActor
    func testExcludeCompressionRoundActionRefreshesDimmedTimelinePresentation() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let fixture = try saveCompressedConversation(repository: repository)
        let compressionService = ContextCompressionService(
            repository: repository,
            executionProvider: WorkbenchManualCompressionExecutionProvider(),
            idGenerator: IncrementingUUIDGenerator(start: 520).next,
            now: { Date(timeIntervalSince1970: 31) }
        )
        let store = WorkbenchStore(
            repository: repository,
            engine: WorkbenchCompressionManualExecutionEngine(),
            contextCompressionService: compressionService
        )

        store.excludeCompressionRound(roundID: fixture.roundID)

        XCTAssertTrue(store.snapshot.compression.timelinePresentation.rounds.first?.isDimmed == true)
        XCTAssertEqual(store.snapshot.compression.timelinePresentation.rounds.first?.status?.label, "已排除模型上下文")
    }

    @MainActor
    func testDefaultRangeCompressionActionUsesSelectedRoundsAsProviderInput() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let fixture = try saveCompressedConversation(repository: repository)
        let compressionProvider = WorkbenchManualCompressionExecutionProvider()
        let compressionService = ContextCompressionService(
            repository: repository,
            executionProvider: compressionProvider,
            idGenerator: IncrementingUUIDGenerator(start: 540).next,
            now: { Date(timeIntervalSince1970: 32) }
        )
        let store = WorkbenchStore(
            repository: repository,
            engine: WorkbenchCompressionManualExecutionEngine(),
            contextCompressionService: compressionService
        )

        let handle = store.compressSelectedRounds(roundIDs: [fixture.roundID])

        XCTAssertNotNil(handle)
        XCTAssertEqual(compressionProvider.requests.first?.sourceText, "Compressed A")
        XCTAssertEqual(compressionProvider.requests.first?.userInstruction, "")
    }

    private func saveCompressedConversation(
        repository: SQLiteCodexPlusRepository
    ) throws -> (conversationID: UUID, roundID: UUID, versionID: UUID) {
        let project = WorkspaceSessionGroup(
            id: uuid(200),
            path: "/tmp/project",
            displayName: "Project",
            conversationIDs: [uuid(201)],
            lastActivityAt: Date(timeIntervalSince1970: 1)
        )
        let conversation = ConversationSession(
            id: uuid(201),
            title: "Conversation",
            prompt: "Initial prompt",
            workspacePath: project.path,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 2),
            lastActivityAt: Date(timeIntervalSince1970: 3),
            events: [
                .userPrompt(id: uuid(210), text: "User A"),
                .assistantMessage(id: uuid(211), text: "Assistant A")
            ]
        )

        try repository.saveProject(project)
        try repository.saveConversation(conversation, projectID: project.id)
        let compressionState = try repository.loadCompressionState(conversationID: conversation.id)
        let round = try XCTUnwrap(compressionState.rounds.first)
        let version = CompressionVersion(
            id: uuid(220),
            conversationID: conversation.id,
            scopeKind: .round,
            operation: .manualEdit,
            status: .active,
            content: "Compressed A",
            templateID: nil,
            compressionInputID: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 4),
            updatedAt: Date(timeIntervalSince1970: 5)
        )
        try repository.saveCompressionVersion(version)
        try repository.saveCompressionVersionSources([
            CompressionVersionSource(
                id: uuid(221),
                versionID: version.id,
                sourceKind: .round,
                sourceID: round.id,
                ordinal: 0
            )
        ])
        try repository.setActiveCompressionVersion(
            CompressionActiveVersion(
                id: uuid(222),
                conversationID: conversation.id,
                roundID: round.id,
                rangeID: nil,
                activeVersionID: version.id
            )
        )
        return (conversation.id, round.id, version.id)
    }

    private func temporaryDatabase() throws -> SQLiteDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-plus-\(UUID().uuidString).sqlite")
        return try SQLiteDatabase(path: url.path)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private final class WorkbenchCompressionManualExecutionEngine: ExecutionEngine, @unchecked Sendable {
    var requests: [ExecutionRequest] = []

    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> any ExecutionHandle {
        requests.append(request)
        return WorkbenchCompressionManualExecutionHandle()
    }
}

private final class WorkbenchCompressionManualExecutionHandle: ExecutionHandle, @unchecked Sendable {
    func stop() {}
}

private final class WorkbenchManualCompressionExecutionProvider: CompressionExecutionProvider, @unchecked Sendable {
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

private final class WorkbenchFixedBudgetProvider: ContextBudgetProvider, @unchecked Sendable {
    var state: ContextBudgetState
    var requests: [ContextBudgetRequest] = []

    init(state: ContextBudgetState) {
        self.state = state
    }

    func measure(_ request: ContextBudgetRequest) async -> ContextBudgetSnapshot {
        requests.append(request)
        return ContextBudgetSnapshot(
            modelName: request.modelName ?? "gpt-test",
            contextWindowTokens: 100,
            assembledInputTokens: state == .hardLimit ? 100 : 10,
            reservedOutputTokens: request.reservedOutputTokens,
            usableInputTokens: 90,
            usageRatio: state == .hardLimit ? 1.1 : 0.1,
            state: state,
            measurementSource: .provider,
            measuredAt: Date(timeIntervalSince1970: 10)
        )
    }
}
