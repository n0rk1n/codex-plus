import Foundation

public struct CodexRunResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stderr: String

    public var succeeded: Bool {
        exitCode == 0
    }

    public init(exitCode: Int32, stderr: String) {
        self.exitCode = exitCode
        self.stderr = stderr
    }
}

public protocol CodexRunHandle: Sendable {
    func stop()
}

public final class ProcessCodexRunHandle: CodexRunHandle {
    private let process: LockedProcess

    public init(process: Process) {
        self.process = LockedProcess(process)
    }

    public func stop() {
        process.terminateIfRunning()
    }
}

public struct ProcessCodexRunner: Sendable {
    private let executableURL: URL
    private let executableArgumentsPrefix: [String]
    private let parser: @Sendable (String) -> CodexEvent

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        executableArgumentsPrefix: [String] = ["codex"],
        parser: @escaping @Sendable (String) -> CodexEvent = CodexEventParser.parseLine
    ) {
        self.executableURL = executableURL
        self.executableArgumentsPrefix = executableArgumentsPrefix
        self.parser = parser
    }

    @discardableResult
    public func run(
        prompt: String,
        permissionMode: PermissionMode,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> CodexRunHandle {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = executableArgumentsPrefix + CodexCommandBuilder.arguments(
            prompt: prompt,
            permissionMode: permissionMode
        )

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = LockedOutputLineBuffer()
        let stderrBuffer = LockedDataBuffer()
        let outputGroup = DispatchGroup()
        let finishQueue = DispatchQueue(label: "QuickAIDashboardCore.ProcessCodexRunner.finish")
        let stdoutReader = StreamReader(fileHandle: stdoutPipe.fileHandleForReading)
        let stderrReader = StreamReader(fileHandle: stderrPipe.fileHandleForReading)
        let eventParser = parser

        outputGroup.enter()
        outputGroup.enter()

        process.terminationHandler = { terminatedProcess in
            let exitCode = terminatedProcess.terminationStatus
            outputGroup.notify(queue: finishQueue) {
                onFinish(CodexRunResult(exitCode: exitCode, stderr: stderrBuffer.text()))
            }
        }

        let handle = ProcessCodexRunHandle(process: process)

        do {
            try process.run()
        } catch {
            outputGroup.leave()
            outputGroup.leave()

            let message = "Unable to start codex: \(error)"
            onEvent(.error(message))
            onFinish(CodexRunResult(exitCode: 127, stderr: message))
            return handle
        }

        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                outputGroup.leave()
            }

            stdoutReader.readChunks { data in
                let lines = stdoutBuffer.append(data)

                for line in lines {
                    onEvent(eventParser(line))
                }
            }

            if let remainingLine = stdoutBuffer.flush() {
                onEvent(eventParser(remainingLine))
            }
        }

        DispatchQueue.global(qos: .utility).async {
            defer {
                outputGroup.leave()
            }

            stderrReader.readChunks { data in
                stderrBuffer.append(data)
            }
        }

        return handle
    }
}

private final class LockedProcess: @unchecked Sendable {
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

private final class LockedOutputLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer {
            lock.unlock()
        }

        buffer.append(data)

        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var lineEndIndex = newlineIndex
            if lineEndIndex > buffer.startIndex {
                let previousIndex = buffer.index(before: lineEndIndex)
                if buffer[previousIndex] == 0x0D {
                    lineEndIndex = previousIndex
                }
            }

            let lineData = buffer[buffer.startIndex..<lineEndIndex]
            lines.append(String(decoding: lineData, as: UTF8.self))

            let afterNewlineIndex = buffer.index(after: newlineIndex)
            buffer.removeSubrange(buffer.startIndex..<afterNewlineIndex)
        }

        return lines
    }

    func flush() -> String? {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !buffer.isEmpty else {
            return nil
        }

        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        return line
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        defer {
            lock.unlock()
        }

        buffer.append(data)
    }

    func text() -> String {
        lock.lock()
        defer {
            lock.unlock()
        }

        return String(decoding: buffer, as: UTF8.self)
    }
}

private final class StreamReader: @unchecked Sendable {
    private let fileHandle: FileHandle

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    func readChunks(_ onChunk: (Data) -> Void) {
        while true {
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                return
            }

            onChunk(data)
        }
    }
}
