import Foundation
import XCTest
@testable import CodexPlusCore

final class PromptOptimizationServiceTests: XCTestCase {
    func testStartsBackgroundOptimizationWithDefaultInputOptimizationTemplate() {
        let templateID = UUID(uuidString: "aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa")!
        let template = PromptTemplate(
            id: templateID,
            source: .userCustom,
            type: .optimizeUserInputPrompt,
            name: "默认优化",
            systemPrompt: "请优化输入。",
            userPrompt: "只输出优化后的提示词。",
            note: "",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let repository = MemoryPromptTemplateRepository(
            templates: [template],
            defaultTemplateIDs: [.optimizeUserInputPrompt: templateID]
        )
        let engine = ManualPromptOptimizationEngine()
        let service = PromptOptimizationService(repository: repository, engine: engine)
        let resultBox = PromptOptimizationResultBox()

        let handle = service.startOptimization(
            input: "帮我写一个测试",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { resultBox.set($0) }
        )

        XCTAssertNotNil(handle)
        XCTAssertEqual(engine.requests.count, 1)
        XCTAssertEqual(engine.requests.first?.permissionMode, .semiAutomatic)
        XCTAssertEqual(engine.requests.first?.workingDirectoryURL.path, "/tmp/project")
        XCTAssertTrue(engine.requests.first?.prompt.contains("请优化输入。") == true)
        XCTAssertTrue(engine.requests.first?.prompt.contains("只输出优化后的提示词。") == true)
        XCTAssertTrue(engine.requests.first?.prompt.contains("帮我写一个测试") == true)

        engine.emit(.agentMessage("请为目标功能编写单元测试。"))
        engine.finish(CodexRunResult(exitCode: 0, stderr: ""))

        XCTAssertEqual(resultBox.value(), .success("请为目标功能编写单元测试。"))
    }

    func testFallsBackToBuiltInInputOptimizationTemplateWhenNoDefaultIsSaved() {
        let repository = MemoryPromptTemplateRepository(templates: [], defaultTemplateIDs: [:])
        let engine = ManualPromptOptimizationEngine()
        let service = PromptOptimizationService(repository: repository, engine: engine)

        _ = service.startOptimization(
            input: "整理一下这句话",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { _ in }
        )

        XCTAssertEqual(engine.requests.count, 1)
        XCTAssertTrue(engine.requests.first?.prompt.contains("你是 Codex 提示词优化助手") == true)
    }

    func testStopTerminatesUnderlyingBackgroundOptimization() {
        let repository = MemoryPromptTemplateRepository(templates: [], defaultTemplateIDs: [:])
        let engine = ManualPromptOptimizationEngine()
        let service = PromptOptimizationService(repository: repository, engine: engine)

        let handle = service.startOptimization(
            input: "优化",
            workingDirectoryURL: URL(fileURLWithPath: "/tmp/project"),
            onFinish: { _ in }
        )

        handle?.stop()

        XCTAssertEqual(engine.stopCount, 1)
    }
}

private final class PromptOptimizationResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: PromptOptimizationResult?

    func set(_ result: PromptOptimizationResult) {
        lock.lock()
        defer {
            lock.unlock()
        }
        storage = result
    }

    func value() -> PromptOptimizationResult? {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storage
    }
}

private final class MemoryPromptTemplateRepository: PromptTemplateRepository, @unchecked Sendable {
    var templates: [PromptTemplate]
    var defaultTemplateIDs: [PromptTemplateType: UUID]

    init(templates: [PromptTemplate], defaultTemplateIDs: [PromptTemplateType: UUID]) {
        self.templates = templates
        self.defaultTemplateIDs = defaultTemplateIDs
    }

    func savePromptTemplate(_ template: PromptTemplate) throws {
        templates.removeAll { $0.id == template.id }
        templates.append(template)
    }

    func loadPromptTemplates() throws -> [PromptTemplate] {
        templates
    }

    func deletePromptTemplate(_ id: UUID) throws {
        templates.removeAll { $0.id == id }
    }

    func setDefaultPromptTemplateID(_ id: UUID, for type: PromptTemplateType) throws {
        defaultTemplateIDs[type] = id
    }

    func loadDefaultPromptTemplateIDs() throws -> [PromptTemplateType: UUID] {
        defaultTemplateIDs
    }
}

private final class ManualPromptOptimizationEngine: ExecutionEngine, @unchecked Sendable {
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
