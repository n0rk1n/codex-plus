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
