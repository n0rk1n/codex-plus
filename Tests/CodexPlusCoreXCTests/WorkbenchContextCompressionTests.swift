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

    private func temporaryDatabase() throws -> SQLiteDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-plus-\(UUID().uuidString).sqlite")
        return try SQLiteDatabase(path: url.path)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
