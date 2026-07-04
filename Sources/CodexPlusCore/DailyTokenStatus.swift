import Foundation

public struct DailyTokenStatus: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedInputTokens: Int
    public let observedAt: Date?

    public init(inputTokens: Int, outputTokens: Int, cachedInputTokens: Int, observedAt: Date?) {
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cachedInputTokens = max(0, cachedInputTokens)
        self.observedAt = observedAt
    }

    public static let unknown = DailyTokenStatus(
        inputTokens: 0,
        outputTokens: 0,
        cachedInputTokens: 0,
        observedAt: nil
    )

    public var totalTokens: Int {
        inputTokens + outputTokens
    }

    public var inputText: String {
        guard hasData else {
            return "--"
        }

        return Self.compactTokenText(inputTokens)
    }

    public var outputText: String {
        guard hasData else {
            return "--"
        }

        return Self.compactTokenText(outputTokens)
    }

    public var hitRateText: String {
        guard let hitRatePercent else {
            return "--"
        }

        return "\(hitRatePercent)%"
    }

    public var hitRatePercent: Int? {
        guard hasData, inputTokens > 0 else {
            return nil
        }

        let percent = (Double(cachedInputTokens) / Double(inputTokens) * 100).rounded()
        return max(0, min(100, Int(percent)))
    }

    private var hasData: Bool {
        observedAt != nil
    }

    private static func compactTokenText(_ tokens: Int) -> String {
        if tokens < 1_000 {
            return "\(tokens)"
        }

        if tokens < 1_000_000 {
            return compact(Double(tokens) / 1_000, suffix: "K")
        }

        return compact(Double(tokens) / 1_000_000, suffix: "M")
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let roundedText: String
        if value < 10 {
            roundedText = String(format: "%.1f", value)
                .replacingOccurrences(of: ".0", with: "")
        } else {
            roundedText = "\(Int(value.rounded()))"
        }

        return "\(roundedText)\(suffix)"
    }
}
