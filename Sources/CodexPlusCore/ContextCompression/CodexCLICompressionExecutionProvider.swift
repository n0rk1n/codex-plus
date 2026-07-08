import Foundation

public final class CodexCLICompressionExecutionProvider: CompressionExecutionProvider, @unchecked Sendable {
    public static let providerName = "Codex CLI"

    private let engine: any ExecutionEngine
    private let providerModel: String

    public init(engine: any ExecutionEngine, providerModel: String) {
        self.engine = engine
        self.providerModel = providerModel
    }

    public func startCompression(
        request: CompressionExecutionRequest,
        onFinish: @escaping @Sendable (CompressionExecutionResult) -> Void
    ) -> (any ExecutionHandle)? {
        let collector = ContextCompressionOutputCollector()
        return engine.start(
            request: ExecutionRequest(
                prompt: Self.prompt(for: request),
                permissionMode: request.permissionMode,
                sessionID: request.sessionID,
                workingDirectoryURL: request.workingDirectoryURL
            ),
            onEvent: { event in
                collector.append(event)
            },
            onFinish: { [providerModel] result in
                guard result.succeeded else {
                    onFinish(
                        .failure(
                            CompressionExecutionFailure(
                                message: result.stderr.isEmpty ? "上下文压缩失败。" : result.stderr,
                                providerName: Self.providerName,
                                providerModel: providerModel
                            )
                        )
                    )
                    return
                }

                let output = collector.output()
                guard !output.isEmpty else {
                    onFinish(
                        .failure(
                            CompressionExecutionFailure(
                                message: "上下文压缩没有返回内容。",
                                providerName: Self.providerName,
                                providerModel: providerModel
                            )
                        )
                    )
                    return
                }

                onFinish(
                    .success(
                        CompressionExecutionSuccess(
                            output: output,
                            providerName: Self.providerName,
                            providerModel: providerModel
                        )
                    )
                )
            }
        )
    }

    public static func prompt(for request: CompressionExecutionRequest) -> String {
        let trimmedInstruction = request.userInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructionBlock = trimmedInstruction.isEmpty
            ? "用户本次没有补充额外压缩意图。"
            : trimmedInstruction

        return """
        \(request.template.systemPrompt)

        \(request.template.userPrompt)

        本次压缩意图：
        \(instructionBlock)

        待压缩内容：
        \(request.sourceText)

        请只输出压缩后的内容正文，不要输出解释、标题或 Markdown 代码块。
        """
    }
}
