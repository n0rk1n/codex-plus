import XCTest
@testable import CodexPlusCore

final class ConversationRunOrchestratorTests: XCTestCase {
    @MainActor
    func testStartStoresHandleAndForwardsEvents() {
        let engine = ManualRunEngine()
        let orchestrator = ConversationRunOrchestrator(engine: engine)
        let conversationID = UUID()
        let conversation = ConversationSession(
            id: conversationID,
            title: "Run",
            prompt: "prompt",
            workspacePath: "/tmp/project",
            state: .running
        )
        var events: [ConversationDisplayEvent] = []
        var finishes: [CodexRunResult] = []

        XCTAssertNoThrow(try orchestrator.start(
            conversation: conversation,
            prompt: "prompt",
            onEvent: { events.append($0) },
            onFinish: { finishes.append($0) }
        ))

        XCTAssertTrue(orchestrator.isRunning(conversationID: conversationID))
        engine.emit(.agentMessage("hello"), for: conversationID)
        engine.finish(CodexRunResult(exitCode: 0, stderr: ""), for: conversationID)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(finishes, [CodexRunResult(exitCode: 0, stderr: "")])
        XCTAssertFalse(orchestrator.isRunning(conversationID: conversationID))
    }

    @MainActor
    func testStopCallsUnderlyingHandle() throws {
        let engine = ManualRunEngine()
        let orchestrator = ConversationRunOrchestrator(engine: engine)
        let conversationID = UUID()
        let conversation = ConversationSession(
            id: conversationID,
            title: "Run",
            prompt: "prompt",
            workspacePath: "/tmp/project",
            state: .running
        )

        try orchestrator.start(conversation: conversation, prompt: "prompt", onEvent: { _ in }, onFinish: { _ in })

        XCTAssertTrue(orchestrator.stop(conversationID: conversationID))
        XCTAssertEqual(engine.stopCount, 1)
    }
}

private final class ManualRunEngine: ExecutionEngine, @unchecked Sendable {
    final class Handle: ExecutionHandle, @unchecked Sendable {
        private let onStop: @Sendable () -> Void

        init(onStop: @escaping @Sendable () -> Void) {
            self.onStop = onStop
        }

        func stop() {
            onStop()
        }
    }

    private var eventCallbacks: [UUID: @Sendable (CodexEvent) -> Void] = [:]
    private var finishCallbacks: [UUID: @Sendable (CodexRunResult) -> Void] = [:]
    var stopCount = 0

    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        eventCallbacks[request.sessionID] = onEvent
        finishCallbacks[request.sessionID] = onFinish
        return Handle { [weak self] in
            self?.stopCount += 1
        }
    }

    func emit(_ event: CodexEvent, for id: UUID) {
        eventCallbacks[id]?(event)
    }

    func finish(_ result: CodexRunResult, for id: UUID) {
        finishCallbacks[id]?(result)
    }
}
