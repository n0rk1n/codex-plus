import Foundation
import XCTest
@testable import CodexPlusCore

final class ContextBudgetProviderTests: XCTestCase {
    func testPolicyClassifiesSmallMediumAndLargeWindowsWithDynamicThresholds() {
        let policy = ContextBudgetPolicy()

        XCTAssertEqual(
            policy.classify(assembledInputTokens: 5_000, contextWindowTokens: 8_000, reservedOutputTokens: 1_000),
            .notice
        )
        XCTAssertEqual(
            policy.classify(assembledInputTokens: 65_000, contextWindowTokens: 100_000, reservedOutputTokens: 10_000),
            .notice
        )
        XCTAssertEqual(
            policy.classify(assembledInputTokens: 250_000, contextWindowTokens: 400_000, reservedOutputTokens: 50_000),
            .safe
        )
    }

    func testPolicyReturnsHardLimitWhenInputExceedsUsableTokens() {
        let policy = ContextBudgetPolicy()

        XCTAssertEqual(
            policy.classify(assembledInputTokens: 90_001, contextWindowTokens: 100_000, reservedOutputTokens: 10_000),
            .hardLimit
        )
    }

    func testCodexCLIProviderReturnsUnknownWhenModelWindowIsUnavailable() async {
        let provider = CodexCLIContextBudgetProvider(
            registry: ModelContextWindowRegistry(profiles: []),
            tokenCounter: FixedTokenCounter(tokens: 10),
            modelNameProvider: { "unknown-model" },
            now: { Date(timeIntervalSince1970: 100) }
        )

        let snapshot = await provider.measure(
            ContextBudgetRequest(
                modelName: nil,
                assembledInput: "hello",
                reservedOutputTokens: 1,
                workingDirectoryURL: URL(fileURLWithPath: "/tmp/project")
            )
        )

        XCTAssertEqual(snapshot.state, .unknown)
        XCTAssertEqual(snapshot.measurementSource, .unknown)
    }

    func testCodexCLIProviderUsesInjectedTokenCounterAndRegistry() async {
        let provider = CodexCLIContextBudgetProvider(
            registry: ModelContextWindowRegistry(
                profiles: [
                    ModelContextWindowProfile(modelName: "gpt-test", contextWindowTokens: 100)
                ]
            ),
            tokenCounter: FixedTokenCounter(tokens: 80),
            modelNameProvider: { "gpt-test" },
            now: { Date(timeIntervalSince1970: 100) }
        )

        let snapshot = await provider.measure(
            ContextBudgetRequest(
                modelName: nil,
                assembledInput: "ignored by fixed counter",
                reservedOutputTokens: 10,
                workingDirectoryURL: URL(fileURLWithPath: "/tmp/project")
            )
        )

        XCTAssertEqual(snapshot.modelName, "gpt-test")
        XCTAssertEqual(snapshot.contextWindowTokens, 100)
        XCTAssertEqual(snapshot.assembledInputTokens, 80)
        XCTAssertEqual(snapshot.reservedOutputTokens, 10)
        XCTAssertEqual(snapshot.usableInputTokens, 90)
        XCTAssertEqual(snapshot.state, .warning)
        XCTAssertEqual(snapshot.measurementSource, .codexCLIModelRegistry)
        XCTAssertEqual(snapshot.measuredAt, Date(timeIntervalSince1970: 100))
    }

    func testWorkbenchCanDependOnContextBudgetProviderProtocol() async {
        let provider: any ContextBudgetProvider = FakeBudgetProvider(state: .hardLimit)

        let snapshot = await provider.measure(
            ContextBudgetRequest(
                modelName: "future-model",
                assembledInput: "text",
                reservedOutputTokens: 1,
                workingDirectoryURL: URL(fileURLWithPath: "/tmp/project")
            )
        )

        XCTAssertEqual(snapshot.state, .hardLimit)
    }
}

private struct FixedTokenCounter: ModelInputTokenCounter {
    var tokens: Int

    func countTokens(in text: String, modelName: String?) -> Int {
        tokens
    }
}

private struct FakeBudgetProvider: ContextBudgetProvider {
    var state: ContextBudgetState

    func measure(_ request: ContextBudgetRequest) async -> ContextBudgetSnapshot {
        ContextBudgetSnapshot(
            modelName: request.modelName ?? "future-model",
            contextWindowTokens: 100,
            assembledInputTokens: 100,
            reservedOutputTokens: request.reservedOutputTokens,
            usableInputTokens: 99,
            usageRatio: 1,
            state: state,
            measurementSource: .provider,
            measuredAt: Date(timeIntervalSince1970: 1)
        )
    }
}
