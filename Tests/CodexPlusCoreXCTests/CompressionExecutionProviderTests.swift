import Foundation
import XCTest
@testable import CodexPlusCore

final class CompressionExecutionProviderTests: XCTestCase {
    func testCodexCLICompressionProviderStartsTransientRunWithTemplateAndSourceText() {
        let engine = ManualCompressionEngine()
        let provider = CodexCLICompressionExecutionProvider(engine: engine, providerModel: "gpt-test")
        let resultBox = CompressionExecutionResultBox()
        let template = compressionTemplate()

        let handle = provider.startCompression(
            request: CompressionExecutionRequest(
                sourceText: "source conversation",
                template: template,
                userInstruction: "保留关键约束",
                workingDirectoryURL: URL(fileURLWithPath: "/tmp/project")
            ),
            onFinish: { resultBox.set($0) }
        )

        XCTAssertNotNil(handle)
        XCTAssertEqual(engine.requests.count, 1)
        XCTAssertEqual(engine.requests.first?.permissionMode, .semiAutomatic)
        XCTAssertEqual(engine.requests.first?.workingDirectoryURL.path, "/tmp/project")
        XCTAssertTrue(engine.requests.first?.prompt.contains(template.systemPrompt) == true)
        XCTAssertTrue(engine.requests.first?.prompt.contains(template.userPrompt) == true)
        XCTAssertTrue(engine.requests.first?.prompt.contains("source conversation") == true)
        XCTAssertTrue(engine.requests.first?.prompt.contains("保留关键约束") == true)
    }

    func testCodexCLICompressionProviderCollectsAgentMessagesAsSuccessOutput() {
        let engine = ManualCompressionEngine()
        let provider = CodexCLICompressionExecutionProvider(engine: engine, providerModel: "gpt-test")
        let resultBox = CompressionExecutionResultBox()

        _ = provider.startCompression(
            request: request(),
            onFinish: { resultBox.set($0) }
        )

        engine.emit(.agentMessage("Line 1"))
        engine.emit(.agentMessage("Line 2"))
        engine.finish(CodexRunResult(exitCode: 0, stderr: ""))

        XCTAssertEqual(
            resultBox.value(),
            .success(
                CompressionExecutionSuccess(
                    output: "Line 1\nLine 2",
                    providerName: "Codex CLI",
                    providerModel: "gpt-test"
                )
            )
        )
    }

    func testCodexCLICompressionProviderReturnsFailureWhenRunFails() {
        let engine = ManualCompressionEngine()
        let provider = CodexCLICompressionExecutionProvider(engine: engine, providerModel: "gpt-test")
        let resultBox = CompressionExecutionResultBox()

        _ = provider.startCompression(
            request: request(),
            onFinish: { resultBox.set($0) }
        )

        engine.finish(CodexRunResult(exitCode: 1, stderr: "boom"))

        XCTAssertEqual(
            resultBox.value(),
            .failure(
                CompressionExecutionFailure(
                    message: "boom",
                    providerName: "Codex CLI",
                    providerModel: "gpt-test"
                )
            )
        )
    }

    func testCodexCLICompressionProviderReturnsFailureForEmptyOutput() {
        let engine = ManualCompressionEngine()
        let provider = CodexCLICompressionExecutionProvider(engine: engine, providerModel: "gpt-test")
        let resultBox = CompressionExecutionResultBox()

        _ = provider.startCompression(
            request: request(),
            onFinish: { resultBox.set($0) }
        )

        engine.finish(CodexRunResult(exitCode: 0, stderr: ""))

        XCTAssertEqual(
            resultBox.value(),
            .failure(
                CompressionExecutionFailure(
                    message: "上下文压缩没有返回内容。",
                    providerName: "Codex CLI",
                    providerModel: "gpt-test"
                )
            )
        )
    }

    private func request() -> CompressionExecutionRequest {
        CompressionExecutionRequest(
            sourceText: "source",
            template: compressionTemplate(),
            userInstruction: "",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project")
        )
    }

    private func compressionTemplate() -> PromptTemplate {
        PromptTemplate(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            source: .systemBuiltIn,
            type: .conversationContextCompression,
            name: "压缩",
            systemPrompt: "系统压缩提示词",
            userPrompt: "用户压缩提示词",
            note: "",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private final class CompressionExecutionResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: CompressionExecutionResult?

    func set(_ result: CompressionExecutionResult) {
        lock.lock()
        defer {
            lock.unlock()
        }
        storage = result
    }

    func value() -> CompressionExecutionResult? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storage
    }
}

private final class ManualCompressionEngine: ExecutionEngine, @unchecked Sendable {
    final class Handle: ExecutionHandle, @unchecked Sendable {
        private let onStop: @Sendable () -> Void

        init(onStop: @escaping @Sendable () -> Void) {
            self.onStop = onStop
        }

        func stop() {
            onStop()
        }
    }

    var requests: [ExecutionRequest] = []
    var stopCount = 0
    private var onEvent: (@Sendable (CodexEvent) -> Void)?
    private var onFinish: (@Sendable (CodexRunResult) -> Void)?

    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        requests.append(request)
        self.onEvent = onEvent
        self.onFinish = onFinish
        return Handle { [weak self] in
            self?.stopCount += 1
        }
    }

    func emit(_ event: CodexEvent) {
        onEvent?(event)
    }

    func finish(_ result: CodexRunResult) {
        onFinish?(result)
    }
}
