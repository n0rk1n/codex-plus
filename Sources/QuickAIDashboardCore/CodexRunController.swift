import Foundation

@MainActor
public final class CodexRunController {
    private let runner: ProcessCodexRunner
    private let callbackQueue = DispatchQueue(label: "QuickAIDashboardCore.CodexRunController.callbacks")

    private var activeRunHandle: CodexRunHandle?
    private var activeRunID: UUID?
    private var activeRunSessionID: UUID?
    private var stoppedRunIDs = Set<UUID>()
    private var eventHandler: ((CodexEvent, UUID) -> Void)?
    private var finishHandler: ((CodexRunResult, UUID) -> Void)?

    public var isRunning: Bool {
        activeRunHandle != nil
    }

    public init(runner: ProcessCodexRunner) {
        self.runner = runner
    }

    @discardableResult
    public func start(
        prompt: String,
        permissionMode: PermissionMode,
        sessionID: UUID,
        onEvent: @escaping (CodexEvent, UUID) -> Void,
        onFinish: @escaping (CodexRunResult, UUID) -> Void
    ) -> Bool {
        guard activeRunHandle == nil else {
            return false
        }

        let runID = UUID()
        activeRunID = runID
        activeRunSessionID = sessionID
        eventHandler = onEvent
        finishHandler = onFinish

        let callbackQueue = callbackQueue
        let callbackTarget = WeakCodexRunControllerBox(self)
        let handle = runner.run(
            prompt: prompt,
            permissionMode: permissionMode,
            onEvent: { event in
                callbackQueue.async {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            callbackTarget.value?.handleEvent(event, sessionID: sessionID, runID: runID)
                        }
                    }
                }
            },
            onFinish: { result in
                callbackQueue.async {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            callbackTarget.value?.handleFinish(result, sessionID: sessionID, runID: runID)
                        }
                    }
                }
            }
        )

        if activeRunID == runID {
            activeRunHandle = handle
        }

        return true
    }

    @discardableResult
    public func stop(sessionID: UUID) -> Bool {
        guard let activeRunHandle, activeRunSessionID == sessionID else {
            return false
        }

        if let activeRunID {
            stoppedRunIDs.insert(activeRunID)
        }
        activeRunHandle.stop()
        return true
    }

    private func handleEvent(_ event: CodexEvent, sessionID: UUID, runID: UUID) {
        guard activeRunSessionID == sessionID, activeRunID == runID else {
            return
        }

        eventHandler?(event, sessionID)
    }

    private func handleFinish(_ result: CodexRunResult, sessionID: UUID, runID: UUID) {
        if stoppedRunIDs.remove(runID) != nil {
            clearRunIfCurrent(runID: runID)
            return
        }

        guard activeRunSessionID == sessionID, activeRunID == runID else {
            return
        }

        let finishHandler = finishHandler
        clearRunIfCurrent(runID: runID)
        finishHandler?(result, sessionID)
    }

    private func clearRunIfCurrent(runID: UUID) {
        guard activeRunID == runID else {
            return
        }

        activeRunHandle = nil
        activeRunID = nil
        activeRunSessionID = nil
        eventHandler = nil
        finishHandler = nil
    }
}

private final class WeakCodexRunControllerBox: @unchecked Sendable {
    weak var value: CodexRunController?

    init(_ value: CodexRunController) {
        self.value = value
    }
}
