import Foundation

public enum ContextBudgetState: String, Equatable, Sendable {
    case safe
    case notice
    case warning
    case hardLimit
    case unknown
}

public enum ContextBudgetMeasurementSource: String, Equatable, Sendable {
    case unknown
    case provider
    case codexCLIModelRegistry
}

public struct ContextBudgetRequest: Equatable, Sendable {
    public var modelName: String?
    public var assembledInput: String
    public var reservedOutputTokens: Int
    public var workingDirectoryURL: URL

    public init(
        modelName: String?,
        assembledInput: String,
        reservedOutputTokens: Int,
        workingDirectoryURL: URL
    ) {
        self.modelName = modelName
        self.assembledInput = assembledInput
        self.reservedOutputTokens = reservedOutputTokens
        self.workingDirectoryURL = workingDirectoryURL
    }
}

public struct ContextBudgetSnapshot: Equatable, Sendable {
    public var modelName: String
    public var contextWindowTokens: Int
    public var assembledInputTokens: Int
    public var reservedOutputTokens: Int
    public var usableInputTokens: Int
    public var usageRatio: Double
    public var state: ContextBudgetState
    public var measurementSource: ContextBudgetMeasurementSource
    public var measuredAt: Date

    public init(
        modelName: String,
        contextWindowTokens: Int,
        assembledInputTokens: Int,
        reservedOutputTokens: Int,
        usableInputTokens: Int,
        usageRatio: Double,
        state: ContextBudgetState,
        measurementSource: ContextBudgetMeasurementSource,
        measuredAt: Date
    ) {
        self.modelName = modelName
        self.contextWindowTokens = contextWindowTokens
        self.assembledInputTokens = assembledInputTokens
        self.reservedOutputTokens = reservedOutputTokens
        self.usableInputTokens = usableInputTokens
        self.usageRatio = usageRatio
        self.state = state
        self.measurementSource = measurementSource
        self.measuredAt = measuredAt
    }
}

public protocol ContextBudgetProvider: Sendable {
    func measure(_ request: ContextBudgetRequest) async -> ContextBudgetSnapshot
}

public struct ContextBudgetPolicy: Sendable {
    public init() {}

    public func classify(
        assembledInputTokens: Int,
        contextWindowTokens: Int,
        reservedOutputTokens: Int
    ) -> ContextBudgetState {
        let usableInputTokens = max(0, contextWindowTokens - reservedOutputTokens)
        guard usableInputTokens > 0 else {
            return assembledInputTokens > 0 ? .hardLimit : .unknown
        }

        if assembledInputTokens > usableInputTokens {
            return .hardLimit
        }

        let ratio = Double(assembledInputTokens) / Double(usableInputTokens)
        let thresholds = thresholds(for: contextWindowTokens)
        if ratio >= thresholds.warning {
            return .warning
        }

        if ratio >= thresholds.notice {
            return .notice
        }

        return .safe
    }

    private func thresholds(for contextWindowTokens: Int) -> (notice: Double, warning: Double) {
        if contextWindowTokens <= 32_000 {
            return (notice: 0.55, warning: 0.80)
        }

        if contextWindowTokens <= 128_000 {
            return (notice: 0.65, warning: 0.85)
        }

        return (notice: 0.75, warning: 0.90)
    }
}
