import Foundation

public protocol CodexAppServerHandoffHandle: Sendable {
    func stop()
}

public final class ProcessCodexAppServerHandoffHandle: CodexAppServerHandoffHandle {
    private let process: LockedHandoffProcess

    public init(process: Process) {
        self.process = LockedHandoffProcess(process)
    }

    public func stop() {
        process.terminateIfRunning()
    }
}

public struct ProcessCodexAppServerHandoffRunner: Sendable {
    fileprivate static let initializeRequestID = 0
    fileprivate static let threadStartRequestID = 1
    fileprivate static let turnStartRequestID = 2
    public static var defaultWorkingDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/threads", isDirectory: true)
    }

    private let executableURL: URL
    private let executableArgumentsPrefix: [String]
    private let workingDirectoryURL: URL

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        executableArgumentsPrefix: [String] = ["codex", "app-server"],
        workingDirectoryURL: URL = ProcessCodexAppServerHandoffRunner.defaultWorkingDirectoryURL
    ) {
        self.executableURL = executableURL
        self.executableArgumentsPrefix = executableArgumentsPrefix
        self.workingDirectoryURL = workingDirectoryURL
    }

    @discardableResult
    public func start(
        prompt: String,
        permissionMode: PermissionMode,
        onStarted: @escaping @Sendable (CodexAppServerHandoff) -> Void,
        onFinish: @escaping @Sendable (CodexAppServerHandoffResult) -> Void
    ) -> CodexAppServerHandoffHandle {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = executableArgumentsPrefix
        process.currentDirectoryURL = workingDirectoryURL

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let handle = ProcessCodexAppServerHandoffHandle(process: process)
        let writer = LockedHandoffInputWriter(fileHandle: stdinPipe.fileHandleForWriting)
        let stderrBuffer = LockedHandoffTextBuffer()
        let state = CodexAppServerHandoffState(
            prompt: prompt,
            permissionMode: permissionMode,
            writer: writer,
            stopProcess: {
                handle.stop()
            },
            onStarted: onStarted,
            onFinish: onFinish
        )

        process.terminationHandler = { terminatedProcess in
            let stderr = stderrBuffer.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let exitCode = terminatedProcess.terminationStatus
            let message = stderr.isEmpty ? "codex app-server exited with code \(exitCode)." : stderr
            state.finishIfNeeded(.failure(message))
        }

        do {
            try FileManager.default.createDirectory(
                at: workingDirectoryURL,
                withIntermediateDirectories: true
            )
            try process.run()
        } catch {
            state.finishIfNeeded(.failure("Unable to start codex app-server: \(error)"))
            return handle
        }

        state.start()

        DispatchQueue.global(qos: .userInitiated).async {
            var lineBuffer = LineBuffer()
            let fileHandle = stdoutPipe.fileHandleForReading

            while true {
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    if let remainingLine = lineBuffer.flush() {
                        state.handleLine(remainingLine)
                    }
                    return
                }

                let chunk = String(decoding: data, as: UTF8.self)
                for line in lineBuffer.append(chunk) {
                    state.handleLine(line)
                }
            }
        }

        DispatchQueue.global(qos: .utility).async {
            let fileHandle = stderrPipe.fileHandleForReading

            while true {
                let data = fileHandle.availableData
                guard !data.isEmpty else {
                    return
                }

                stderrBuffer.append(data)
            }
        }

        return handle
    }
}

private final class CodexAppServerHandoffState: @unchecked Sendable {
    private enum Stage {
        case initializing
        case startingThread
        case startingTurn(CodexAppServerHandoff)
        case running(CodexAppServerHandoff)
        case finished
    }

    private let lock = NSLock()
    private let prompt: String
    private let permissionMode: PermissionMode
    private let writer: LockedHandoffInputWriter
    private let stopProcess: @Sendable () -> Void
    private let onStarted: @Sendable (CodexAppServerHandoff) -> Void
    private let onFinish: @Sendable (CodexAppServerHandoffResult) -> Void

    private var stage: Stage = .initializing

    init(
        prompt: String,
        permissionMode: PermissionMode,
        writer: LockedHandoffInputWriter,
        stopProcess: @escaping @Sendable () -> Void,
        onStarted: @escaping @Sendable (CodexAppServerHandoff) -> Void,
        onFinish: @escaping @Sendable (CodexAppServerHandoffResult) -> Void
    ) {
        self.prompt = prompt
        self.permissionMode = permissionMode
        self.writer = writer
        self.stopProcess = stopProcess
        self.onStarted = onStarted
        self.onFinish = onFinish
    }

    func start() {
        writer.writeLine(
            CodexAppServerProtocol.initializeRequest(
                id: ProcessCodexAppServerHandoffRunner.initializeRequestID
            )
        )
        writer.writeLine(CodexAppServerProtocol.initializedNotification())
    }

    func handleLine(_ line: String) {
        if let requestID = CodexAppServerProtocol.requestID(from: line) {
            handleServerRequest(line, requestID: requestID)
            return
        }

        if let errorMessage = CodexAppServerProtocol.errorMessage(fromNotification: line) {
            finishIfNeeded(.failure(errorMessage))
            return
        }

        lock.lock()
        let currentStage = stage
        lock.unlock()

        switch currentStage {
        case .initializing:
            handleInitializeResponse(line)
        case .startingThread:
            handleThreadStartResponse(line)
        case let .startingTurn(handoff):
            handleTurnStartResponse(line, handoff: handoff)
        case let .running(handoff):
            if CodexAppServerProtocol.isTurnCompletedNotification(line, threadID: handoff.threadID) {
                finishIfNeeded(.success())
            }
        case .finished:
            return
        }
    }

    func finishIfNeeded(_ result: CodexAppServerHandoffResult) {
        let shouldFinish: Bool
        lock.lock()
        switch stage {
        case .finished:
            shouldFinish = false
        case .initializing, .startingThread, .startingTurn, .running:
            stage = .finished
            shouldFinish = true
        }
        lock.unlock()

        guard shouldFinish else {
            return
        }

        onFinish(result)
        stopProcess()
    }

    private func handleInitializeResponse(_ line: String) {
        guard CodexAppServerProtocol.responseID(from: line) == ProcessCodexAppServerHandoffRunner.initializeRequestID else {
            return
        }

        if let errorMessage = CodexAppServerProtocol.errorMessage(fromResponse: line) {
            finishIfNeeded(.failure(errorMessage))
            return
        }

        setStage(.startingThread)
        writer.writeLine(
            CodexAppServerProtocol.threadStartRequest(
                id: ProcessCodexAppServerHandoffRunner.threadStartRequestID,
                permissionMode: permissionMode
            )
        )
    }

    private func handleThreadStartResponse(_ line: String) {
        guard CodexAppServerProtocol.responseID(from: line) == ProcessCodexAppServerHandoffRunner.threadStartRequestID else {
            return
        }

        if let errorMessage = CodexAppServerProtocol.errorMessage(fromResponse: line) {
            finishIfNeeded(.failure(errorMessage))
            return
        }

        guard let handoff = CodexAppServerProtocol.handoff(fromThreadStartResponse: line) else {
            finishIfNeeded(.failure("Codex app-server did not return a thread id."))
            return
        }

        setStage(.startingTurn(handoff))
        writer.writeLine(
            CodexAppServerProtocol.turnStartRequest(
                id: ProcessCodexAppServerHandoffRunner.turnStartRequestID,
                threadID: handoff.threadID,
                prompt: prompt
            )
        )
    }

    private func handleTurnStartResponse(_ line: String, handoff: CodexAppServerHandoff) {
        guard CodexAppServerProtocol.responseID(from: line) == ProcessCodexAppServerHandoffRunner.turnStartRequestID else {
            return
        }

        if let errorMessage = CodexAppServerProtocol.errorMessage(fromResponse: line) {
            finishIfNeeded(.failure(errorMessage))
            return
        }

        setStage(.running(handoff))
        onStarted(handoff)
    }

    private func handleServerRequest(_ line: String, requestID: Int) {
        if CodexAppServerProtocol.isApprovalRequest(line) {
            writer.writeLine(CodexAppServerProtocol.declineApprovalResponse(id: requestID))
            return
        }

        writer.writeLine(
            CodexAppServerProtocol.unsupportedRequestResponse(
                id: requestID,
                message: "QuickAI Dashboard cannot handle this Codex app-server request."
            )
        )
    }

    private func setStage(_ nextStage: Stage) {
        lock.lock()
        stage = nextStage
        lock.unlock()
    }
}

private final class LockedHandoffInputWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func writeLine(_ line: String) {
        guard let data = "\(line)\n".data(using: .utf8) else {
            return
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        try? fileHandle.write(contentsOf: data)
    }
}

private final class LockedHandoffTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer {
            lock.unlock()
        }

        data.append(chunk)
    }

    func text() -> String {
        lock.lock()
        defer {
            lock.unlock()
        }

        return String(decoding: data, as: UTF8.self)
    }
}

private final class LockedHandoffProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminateIfRunning() {
        lock.lock()
        defer {
            lock.unlock()
        }

        if process.isRunning {
            process.terminate()
        }
    }
}
