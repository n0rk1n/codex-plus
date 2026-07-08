import Foundation

public struct CodexCLIContextBudgetProvider: ContextBudgetProvider {
    private let registry: ModelContextWindowRegistry
    private let tokenCounter: any ModelInputTokenCounter
    private let modelNameProvider: @Sendable () -> String?
    private let now: @Sendable () -> Date
    private let policy: ContextBudgetPolicy

    public init(
        registry: ModelContextWindowRegistry,
        tokenCounter: any ModelInputTokenCounter,
        modelNameProvider: @escaping @Sendable () -> String?,
        now: @escaping @Sendable () -> Date = Date.init,
        policy: ContextBudgetPolicy = ContextBudgetPolicy()
    ) {
        self.registry = registry
        self.tokenCounter = tokenCounter
        self.modelNameProvider = modelNameProvider
        self.now = now
        self.policy = policy
    }

    public func measure(_ request: ContextBudgetRequest) async -> ContextBudgetSnapshot {
        guard let modelName = request.modelName ?? modelNameProvider(),
              let profile = registry.profile(for: modelName) else {
            return ContextBudgetSnapshot(
                modelName: request.modelName ?? modelNameProvider() ?? "unknown",
                contextWindowTokens: 0,
                assembledInputTokens: 0,
                reservedOutputTokens: request.reservedOutputTokens,
                usableInputTokens: 0,
                usageRatio: 0,
                state: .unknown,
                measurementSource: .unknown,
                measuredAt: now()
            )
        }

        let assembledInputTokens = tokenCounter.countTokens(in: request.assembledInput, modelName: modelName)
        let usableInputTokens = max(0, profile.contextWindowTokens - request.reservedOutputTokens)
        let usageRatio = usableInputTokens > 0 ? Double(assembledInputTokens) / Double(usableInputTokens) : 0
        let state = policy.classify(
            assembledInputTokens: assembledInputTokens,
            contextWindowTokens: profile.contextWindowTokens,
            reservedOutputTokens: request.reservedOutputTokens
        )

        return ContextBudgetSnapshot(
            modelName: profile.modelName,
            contextWindowTokens: profile.contextWindowTokens,
            assembledInputTokens: assembledInputTokens,
            reservedOutputTokens: request.reservedOutputTokens,
            usableInputTokens: usableInputTokens,
            usageRatio: usageRatio,
            state: state,
            measurementSource: .codexCLIModelRegistry,
            measuredAt: now()
        )
    }
}
