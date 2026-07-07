import Foundation

public enum PromptOptimizationResult: Equatable, Sendable {
    case success(String)
    case failure(String)
}

public final class PromptOptimizationService: @unchecked Sendable {
    private let repository: any PromptTemplateRepository
    private let engine: any ExecutionEngine

    public init(repository: any PromptTemplateRepository, engine: any ExecutionEngine) {
        self.repository = repository
        self.engine = engine
    }

    @discardableResult
    public func startOptimization(
        input: String,
        workingDirectoryURL: URL,
        onFinish: @escaping @Sendable (PromptOptimizationResult) -> Void
    ) -> (any ExecutionHandle)? {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        let template: PromptTemplate
        do {
            template = try defaultInputOptimizationTemplate()
        } catch {
            onFinish(.failure("无法加载默认优化提示词模板：\(error)"))
            return nil
        }

        let collector = PromptOptimizationOutputCollector()
        return engine.start(
            request: ExecutionRequest(
                prompt: Self.optimizationPrompt(input: trimmedInput, template: template),
                permissionMode: .semiAutomatic,
                sessionID: UUID(),
                workingDirectoryURL: workingDirectoryURL
            ),
            onEvent: { event in
                collector.append(event)
            },
            onFinish: { result in
                guard result.succeeded else {
                    onFinish(.failure(result.stderr.isEmpty ? "提示词优化失败。" : result.stderr))
                    return
                }

                let output = collector.output()
                if output.isEmpty {
                    onFinish(.failure("提示词优化没有返回内容。"))
                } else {
                    onFinish(.success(output))
                }
            }
        )
    }

    public static func optimizationPrompt(input: String, template: PromptTemplate) -> String {
        """
        \(template.systemPrompt)

        \(template.userPrompt)

        用户原始输入：
        \(input)

        请只输出优化后的提示词正文，不要添加解释、标题或 Markdown 代码块。
        """
    }

    private func defaultInputOptimizationTemplate() throws -> PromptTemplate {
        let templates = PromptTemplateLibrary.sortedTemplates(
            PromptTemplateLibrary.builtInTemplates() + (try repository.loadPromptTemplates())
        )
        let defaults = PromptTemplateLibrary.resolvedDefaultTemplateIDs(
            templates: templates,
            savedDefaultTemplateIDs: try repository.loadDefaultPromptTemplateIDs()
        )

        guard let id = defaults[.optimizeUserInputPrompt],
              let template = templates.first(where: { $0.id == id && $0.type == .optimizeUserInputPrompt }) else {
            throw PromptOptimizationServiceError.missingDefaultTemplate
        }

        return template
    }
}

private enum PromptOptimizationServiceError: Error {
    case missingDefaultTemplate
}

private final class PromptOptimizationOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func append(_ event: CodexEvent) {
        guard case let .agentMessage(text) = event else {
            return
        }

        lock.lock()
        defer {
            lock.unlock()
        }
        messages.append(text)
    }

    func output() -> String {
        lock.lock()
        defer {
            lock.unlock()
        }

        return messages
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
