import Foundation

@MainActor
public final class CodexRunController {
    private struct ActiveRun {
        var handle: ProcessCodexRunHandle
        var runID: UUID
        var sessionID: UUID
        var eventHandler: (CodexEvent, UUID) -> Void
        var finishHandler: (CodexRunResult, UUID) -> Void
    }

    private let runner: ProcessCodexRunner
    private let callbackQueue = DispatchQueue(label: "CodexPlusCore.CodexRunController.callbacks")

    private var activeRuns: [UUID: ActiveRun] = [:]
    private var stoppedRunIDs = Set<UUID>()

    public var isRunning: Bool {
        !activeRuns.isEmpty
    }

    public init(runner: ProcessCodexRunner) {
        self.runner = runner
    }

    public func isRunning(sessionID: UUID) -> Bool {
        activeRuns[sessionID] != nil
    }

    @discardableResult
    public func start(
        prompt: String,
        permissionMode: PermissionMode,
        sessionID: UUID,
        workingDirectoryURL: URL? = nil,
        onEvent: @escaping (CodexEvent, UUID) -> Void,
        onFinish: @escaping (CodexRunResult, UUID) -> Void
    ) -> Bool {
        guard activeRuns[sessionID] == nil else {
            return false
        }

        let runID = UUID()

        let callbackQueue = callbackQueue
        let callbackTarget = WeakCodexRunControllerBox(self)
        let handle = runner.run(
            prompt: prompt,
            permissionMode: permissionMode,
            workingDirectoryURL: workingDirectoryURL,
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

        activeRuns[sessionID] = ActiveRun(
            handle: handle,
            runID: runID,
            sessionID: sessionID,
            eventHandler: onEvent,
            finishHandler: onFinish
        )

        return true
    }

    @discardableResult
    public func stop(sessionID: UUID) -> Bool {
        guard let activeRun = activeRuns[sessionID] else {
            return false
        }

        stoppedRunIDs.insert(activeRun.runID)
        activeRun.handle.stop()
        return true
    }

    private func handleEvent(_ event: CodexEvent, sessionID: UUID, runID: UUID) {
        guard let activeRun = activeRuns[sessionID], activeRun.runID == runID else {
            return
        }

        activeRun.eventHandler(event, sessionID)
    }

    private func handleFinish(_ result: CodexRunResult, sessionID: UUID, runID: UUID) {
        if stoppedRunIDs.remove(runID) != nil {
            clearRunIfCurrent(sessionID: sessionID, runID: runID)
            return
        }

        guard let activeRun = activeRuns[sessionID], activeRun.runID == runID else {
            return
        }

        let finishHandler = activeRun.finishHandler
        clearRunIfCurrent(sessionID: sessionID, runID: runID)
        finishHandler(result, sessionID)
    }

    private func clearRunIfCurrent(sessionID: UUID, runID: UUID) {
        guard activeRuns[sessionID]?.runID == runID else {
            return
        }

        activeRuns[sessionID] = nil
    }
}

private final class WeakCodexRunControllerBox: @unchecked Sendable {
    weak var value: CodexRunController?

    init(_ value: CodexRunController) {
        self.value = value
    }
}
