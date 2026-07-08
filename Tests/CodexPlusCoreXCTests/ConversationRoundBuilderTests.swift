import Foundation
import XCTest
@testable import CodexPlusCore

final class ConversationRoundBuilderTests: XCTestCase {
    func testBuildsOneRoundForUserAndAssistantMessage() {
        let userID = uuid(1)
        let assistantID = uuid(2)
        let conversation = conversation(
            state: .completed,
            events: [
                .userPrompt(id: userID, text: "Question"),
                .assistantMessage(id: assistantID, text: "Answer")
            ]
        )

        let result = ConversationRoundBuilder.buildRounds(
            conversation: conversation,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(result.rounds.count, 1)
        XCTAssertEqual(result.rounds[0].roundIndex, 0)
        XCTAssertEqual(result.rounds[0].conversationID, conversation.id)
        XCTAssertEqual(result.rounds[0].userEventID, userID)
        XCTAssertEqual(result.rounds[0].firstAssistantEventID, assistantID)
        XCTAssertEqual(result.rounds[0].lastAssistantEventID, assistantID)
        XCTAssertEqual(result.rounds[0].runState, "completed")
        XCTAssertEqual(result.events.map(\.roundID), [result.rounds[0].id, result.rounds[0].id])
        XCTAssertEqual(result.events.map(\.eventID), [userID, assistantID])
        XCTAssertEqual(result.events.map(\.segmentKind), [.user, .assistant])
        XCTAssertEqual(result.events.map(\.ordinal), [0, 1])
    }

    func testTechnicalEventsAfterUserPromptStayInAssistantBucket() {
        let userID = uuid(1)
        let statusID = uuid(2)
        let commandID = uuid(3)
        let warningID = uuid(4)
        let errorID = uuid(5)
        let conversation = conversation(
            events: [
                .userPrompt(id: userID, text: "Run"),
                .status(id: statusID, text: "started"),
                .command(id: commandID, executionID: "exec", command: "ls", status: .completed),
                .parseWarning(id: warningID, text: "warning"),
                .error(id: errorID, text: "failed")
            ]
        )

        let result = ConversationRoundBuilder.buildRounds(
            conversation: conversation,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(result.rounds.count, 1)
        XCTAssertEqual(result.rounds[0].firstAssistantEventID, statusID)
        XCTAssertEqual(result.rounds[0].lastAssistantEventID, errorID)
        XCTAssertEqual(result.events.map(\.segmentKind), [.user, .assistant, .assistant, .assistant, .assistant])
        XCTAssertEqual(result.events.map(\.ordinal), [0, 1, 2, 3, 4])
    }

    func testNextUserPromptStartsNextRound() {
        let firstUserID = uuid(1)
        let firstAssistantID = uuid(2)
        let secondUserID = uuid(3)
        let secondAssistantID = uuid(4)
        let conversation = conversation(
            events: [
                .userPrompt(id: firstUserID, text: "A"),
                .assistantMessage(id: firstAssistantID, text: "B"),
                .userPrompt(id: secondUserID, text: "C"),
                .assistantMessage(id: secondAssistantID, text: "D")
            ]
        )

        let result = ConversationRoundBuilder.buildRounds(
            conversation: conversation,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(result.rounds.map(\.roundIndex), [0, 1])
        XCTAssertEqual(result.rounds.map(\.userEventID), [firstUserID, secondUserID])
        XCTAssertEqual(result.rounds.map(\.firstAssistantEventID), [firstAssistantID, secondAssistantID])
        XCTAssertEqual(result.events.filter { $0.segmentKind == .user }.map(\.eventID), [firstUserID, secondUserID])
    }

    func testUserPromptWithoutAssistantOutputStillCreatesRound() {
        let userID = uuid(1)
        let conversation = conversation(state: .failed, events: [.userPrompt(id: userID, text: "A")])

        let result = ConversationRoundBuilder.buildRounds(
            conversation: conversation,
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(result.rounds.count, 1)
        XCTAssertEqual(result.rounds[0].userEventID, userID)
        XCTAssertNil(result.rounds[0].firstAssistantEventID)
        XCTAssertNil(result.rounds[0].lastAssistantEventID)
        XCTAssertEqual(result.rounds[0].runState, "failed")
        XCTAssertEqual(result.events.map(\.segmentKind), [.user])
    }

    private func conversation(
        state: ConversationRunState = .completed,
        events: [ConversationDisplayEvent]
    ) -> ConversationSession {
        ConversationSession(
            id: uuid(100),
            title: "Conversation",
            prompt: "Prompt",
            workspacePath: "/tmp/project",
            state: state,
            createdAt: Date(timeIntervalSince1970: 1),
            lastActivityAt: Date(timeIntervalSince1970: 2),
            events: events
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
