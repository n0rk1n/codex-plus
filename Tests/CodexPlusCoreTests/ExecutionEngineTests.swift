import Foundation
import CodexPlusCore

@MainActor
func runExecutionEngineTests() {
    let sessionID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    let fake = FakeExecutionEngine()
    let request = ExecutionRequest(
        prompt: "who are you",
        permissionMode: .semiAutomatic,
        sessionID: sessionID,
        workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
    )
    let capturedEvent = LockedValue<CodexEvent>()
    let capturedResult = LockedValue<CodexRunResult>()

    let handle = fake.start(
        request: request,
        onEvent: { event in
            capturedEvent.set(event)
        },
        onFinish: { result in
            capturedResult.set(result)
        }
    )

    expect(capturedEvent.value == .raw("fake event"), "fake engine forwards event")
    expect(capturedResult.value?.succeeded == true, "fake engine forwards success")
    expect(fake.requests == [request], "fake engine captures request")
    handle.stop()
    expect(fake.stopCount == 1, "fake handle records stop")
    expect(fake.handles.first?.stopCount == 1, "stop proxy forwards stop to wrapped handle")
}

private final class FakeExecutionHandle: ExecutionHandle, @unchecked Sendable {
    var stopCount = 0

    func stop() {
        stopCount += 1
    }
}

private final class FakeExecutionEngine: ExecutionEngine, @unchecked Sendable {
    var requests: [ExecutionRequest] = []
    var handles: [FakeExecutionHandle] = []
    var stopCount = 0

    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        requests.append(request)
        onEvent(.raw("fake event"))
        onFinish(CodexRunResult(exitCode: 0, stderr: ""))
        let handle = FakeExecutionHandle()
        handles.append(handle)
        return EngineStopProxy(handle: handle) { [weak self] in
            self?.stopCount += 1
        }
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    func set(_ value: Value) {
        lock.lock()
        defer {
            lock.unlock()
        }

        storage = value
    }

    var value: Value? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return storage
    }
}
