import Foundation

public struct CodexCLIEngine: ExecutionEngine {
    private let runner: ProcessCodexRunner

    public init(runner: ProcessCodexRunner = ProcessCodexRunner()) {
        self.runner = runner
    }

    public func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        let handle = runner.run(
            prompt: request.prompt,
            permissionMode: request.permissionMode,
            workingDirectoryURL: request.workingDirectoryURL,
            onEvent: onEvent,
            onFinish: onFinish
        )

        return CLIExecutionHandle(handle: handle)
    }
}

private final class CLIExecutionHandle: ExecutionHandle, @unchecked Sendable {
    private let handle: ProcessCodexRunHandle

    init(handle: ProcessCodexRunHandle) {
        self.handle = handle
    }

    func stop() {
        handle.stop()
    }
}
