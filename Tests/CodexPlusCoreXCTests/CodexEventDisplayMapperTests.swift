import XCTest
@testable import CodexPlusCore

final class CodexEventDisplayMapperTests: XCTestCase {
    func testMapsCodexEventsToDisplayEvents() {
        XCTAssertEqual(
            CodexEventDisplayMapper.displayEvent(from: .threadStarted("thread-1")).displayText,
            "Thread started: thread-1"
        )
        XCTAssertEqual(
            CodexEventDisplayMapper.displayEvent(from: .turnStarted).displayText,
            "Turn started"
        )
        XCTAssertEqual(
            CodexEventDisplayMapper.displayEvent(from: .turnCompleted).displayText,
            "Turn completed"
        )

        if case let .assistantMessage(_, text) = CodexEventDisplayMapper.displayEvent(from: .agentMessage("hello")) {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("agent message should map to assistant message")
        }

        if case let .command(_, executionID, command, status) = CodexEventDisplayMapper.displayEvent(
            from: .command(id: "cmd-1", command: "ls", status: .completed)
        ) {
            XCTAssertEqual(executionID, "cmd-1")
            XCTAssertEqual(command, "ls")
            XCTAssertEqual(status, .completed)
        } else {
            XCTFail("command should map to command display event")
        }
    }
}

private extension ConversationDisplayEvent {
    var displayText: String {
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
