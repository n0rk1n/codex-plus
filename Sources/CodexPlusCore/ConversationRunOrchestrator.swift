import Foundation

@MainActor
public final class ConversationRunOrchestrator {
    private let engine: ExecutionEngine
    private var activeHandles: [UUID: ExecutionHandle] = [:]

    public init(engine: ExecutionEngine) {
        self.engine = engine
    }

    public func start(
        conversation: ConversationSession,
        prompt: String,
        onEvent: @escaping @MainActor @Sendable (ConversationDisplayEvent) -> Void,
        onFinish: @escaping @MainActor @Sendable (CodexRunResult) -> Void
    ) throws {
        guard activeHandles[conversation.id] == nil else {
            throw WorkbenchDomainError.persistenceFailed("Conversation is already running.")
        }

        let request = ExecutionRequest(
            prompt: prompt,
            permissionMode: conversation.permissionMode,
            sessionID: conversation.id,
            workingDirectoryURL: URL(fileURLWithPath: conversation.workspacePath, isDirectory: true)
        )

        let conversationID = conversation.id
        let handle = engine.start(
            request: request,
            onEvent: { event in
                let displayEvent = CodexEventDisplayMapper.displayEvent(from: event)
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        onEvent(displayEvent)
                    }
                } else {
                    Task { @MainActor in
                        onEvent(displayEvent)
                    }
                }
            },
            onFinish: { [weak self] result in
                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        self?.activeHandles[conversationID] = nil
                        onFinish(result)
                    }
                } else {
                    Task { @MainActor in
                        self?.activeHandles[conversationID] = nil
                        onFinish(result)
                    }
                }
            }
        )

        activeHandles[conversation.id] = handle
    }

    public func stop(conversationID: UUID) -> Bool {
        guard let handle = activeHandles.removeValue(forKey: conversationID) else {
            return false
        }

        handle.stop()
        return true
    }

    public func isRunning(conversationID: UUID) -> Bool {
        activeHandles[conversationID] != nil
    }
}
