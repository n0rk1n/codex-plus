import Foundation

public struct ExecutionRequest: Equatable, Sendable {
    public var prompt: String
    public var permissionMode: PermissionMode
    public var sessionID: UUID
    public var workingDirectoryURL: URL

    public init(
        prompt: String,
        permissionMode: PermissionMode,
        sessionID: UUID,
        workingDirectoryURL: URL
    ) {
        self.prompt = prompt
        self.permissionMode = permissionMode
        self.sessionID = sessionID
        self.workingDirectoryURL = workingDirectoryURL
    }
}

public protocol ExecutionHandle: Sendable {
    func stop()
}

public protocol ExecutionEngine: Sendable {
    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle
}

public final class EngineStopProxy: ExecutionHandle, @unchecked Sendable {
    private let handle: ExecutionHandle
    private let onStop: @Sendable () -> Void

    public init(handle: ExecutionHandle, onStop: @escaping @Sendable () -> Void) {
        self.handle = handle
        self.onStop = onStop
    }

    public func stop() {
        onStop()
        handle.stop()
    }
}
