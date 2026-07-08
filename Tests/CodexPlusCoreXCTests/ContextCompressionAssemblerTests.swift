import Foundation
import XCTest
@testable import CodexPlusCore

final class ContextCompressionAssemblerTests: XCTestCase {
    func testOriginalOnlyConversationEmitsSourceRoundsAndPendingPrompt() throws {
        let fixture = conversationFixture(["A", "B"])
        let input = ContextCompressionAssemblyInput(
            conversation: fixture.conversation,
            compressionState: ConversationCompressionState(rounds: fixture.rounds, roundEvents: fixture.roundEvents),
            pendingUserPrompt: "C"
        )

        let assembled = try ContextCompressionAssemblerV2.assemble(input)

        XCTAssertEqual(assembled.text, "User A\n\nAssistant A\n\nUser B\n\nAssistant B\n\nC")
    }

    func testRoundActiveManualEditReplacesOneRound() throws {
        let fixture = conversationFixture(["A", "B"])
        let edited = version(id: uuid(100), operation: .manualEdit, content: "Edited A")
        let active = active(roundID: fixture.rounds[0].id, versionID: edited.id)
        let input = ContextCompressionAssemblyInput(
            conversation: fixture.conversation,
            compressionState: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [edited],
                activeVersions: [active]
            )
        )

        let assembled = try ContextCompressionAssemblerV2.assemble(input)

        XCTAssertEqual(assembled.text, "Edited A\n\nUser B\n\nAssistant B")
    }

    func testExcludedRoundEmitsNoText() throws {
        let fixture = conversationFixture(["A", "B"])
        let excluded = version(id: uuid(101), operation: .exclude, content: "")
        let active = active(roundID: fixture.rounds[0].id, versionID: excluded.id)
        let input = ContextCompressionAssemblyInput(
            conversation: fixture.conversation,
            compressionState: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [excluded],
                activeVersions: [active]
            )
        )

        let assembled = try ContextCompressionAssemblerV2.assemble(input)

        XCTAssertEqual(assembled.text, "User B\n\nAssistant B")
        XCTAssertEqual(assembled.components[0], .excluded(roundID: fixture.rounds[0].id))
    }

    func testJoinedCompressionEmitsOnceAndSuppressesCoveredRounds() throws {
        let fixture = conversationFixture(["A", "B", "C", "D"])
        let joined = version(id: uuid(102), scopeKind: .range, operation: .defaultCompression, content: "Compressed B-C")
        let sources = [
            source(versionID: joined.id, roundID: fixture.rounds[1].id, ordinal: 0),
            source(versionID: joined.id, roundID: fixture.rounds[2].id, ordinal: 1)
        ]
        let active = CompressionActiveVersion(
            id: uuid(103),
            conversationID: fixture.conversation.id,
            roundID: nil,
            rangeID: joined.id,
            activeVersionID: joined.id
        )
        let input = ContextCompressionAssemblyInput(
            conversation: fixture.conversation,
            compressionState: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [joined],
                versionSources: sources,
                activeVersions: [active]
            )
        )

        let assembled = try ContextCompressionAssemblerV2.assemble(input)

        XCTAssertEqual(assembled.text, "User A\n\nAssistant A\n\nCompressed B-C\n\nUser D\n\nAssistant D")
    }

    func testOnlyFinalActiveLineageIsEmittedForAPENG() throws {
        let fixture = conversationFixture(["A", "B", "C", "D", "E", "F", "G"])
        let amg = version(id: uuid(110), scopeKind: .range, operation: .defaultCompression, status: .historical, content: "AMG")
        let n = version(id: uuid(111), scopeKind: .range, operation: .systemCompression, status: .historical, content: "N")
        let apeng = version(id: uuid(112), scopeKind: .range, operation: .customCompression, status: .active, content: "APENG")
        let sources = fixture.rounds.enumerated().map { index, round in
            source(versionID: apeng.id, roundID: round.id, ordinal: index)
        }
        let active = CompressionActiveVersion(
            id: uuid(113),
            conversationID: fixture.conversation.id,
            roundID: nil,
            rangeID: apeng.id,
            activeVersionID: apeng.id
        )
        let input = ContextCompressionAssemblyInput(
            conversation: fixture.conversation,
            compressionState: ConversationCompressionState(
                rounds: fixture.rounds,
                roundEvents: fixture.roundEvents,
                versions: [amg, n, apeng],
                versionSources: sources,
                activeVersions: [active]
            )
        )

        let assembled = try ContextCompressionAssemblerV2.assemble(input)

        XCTAssertEqual(assembled.text, "APENG")
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
        scopeKind: CompressionVersionScopeKind = .round,
        operation: CompressionVersionOperation,
        status: CompressionVersionStatus = .active,
        content: String
    ) -> CompressionVersion {
        CompressionVersion(
            id: id,
            conversationID: uuid(1),
            scopeKind: scopeKind,
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

    private func active(roundID: UUID, versionID: UUID) -> CompressionActiveVersion {
        CompressionActiveVersion(
            id: uuid(200),
            conversationID: uuid(1),
            roundID: roundID,
            rangeID: nil,
            activeVersionID: versionID
        )
    }

    private func source(versionID: UUID, roundID: UUID, ordinal: Int) -> CompressionVersionSource {
        CompressionVersionSource(
            id: uuid(300 + ordinal),
            versionID: versionID,
            sourceKind: .round,
            sourceID: roundID,
            ordinal: ordinal
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
