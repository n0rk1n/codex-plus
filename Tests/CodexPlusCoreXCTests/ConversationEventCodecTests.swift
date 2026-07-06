import XCTest
@testable import CodexPlusCore

final class ConversationEventCodecTests: XCTestCase {
    func testRoundTripsSupportedEvents() throws {
        let events: [ConversationDisplayEvent] = [
            .userPrompt(id: UUID(), text: "hello"),
            .status(id: UUID(), text: "running"),
            .assistantMessage(id: UUID(), text: "done"),
            .command(id: UUID(), executionID: "exec-1", command: "ls", status: .completed),
            .error(id: UUID(), text: "failed"),
            .parseWarning(id: UUID(), text: "bad json")
        ]

        for (index, event) in events.enumerated() {
            let encoded = try ConversationEventCodec.encode(
                event,
                ordinal: index,
                fallbackDate: Date(timeIntervalSince1970: 1)
            )
            let decoded = try ConversationEventCodec.decode(kind: encoded.kind, payloadJSON: encoded.payloadJSON)

            XCTAssertEqual(decoded, event)
            XCTAssertEqual(encoded.ordinal, index)
            XCTAssertFalse(encoded.searchableText.isEmpty)
        }
    }
}
