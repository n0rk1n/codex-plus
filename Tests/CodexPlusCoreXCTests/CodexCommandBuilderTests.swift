import XCTest
@testable import CodexPlusCore

final class CodexCommandBuilderTests: XCTestCase {
    func testCodexCommandBuilderUsesDefaultConfiguration() {
        XCTAssertEqual(
            CodexCommandBuilder.arguments(prompt: "List files", permissionMode: .semiAutomatic),
            ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", "--", "List files"]
        )
        XCTAssertEqual(
            CodexCommandBuilder.arguments(prompt: "List files", permissionMode: .fullAccess),
            ["exec", "--json", "--skip-git-repo-check", "--sandbox", "danger-full-access", "--", "List files"]
        )
    }

    func testCodexCommandBuilderAcceptsCustomConfiguration() {
        let configuration = CodexCommandConfiguration(
            skipGitRepoCheck: false,
            sandboxByPermissionMode: [.semiAutomatic: "workspace-write", .fullAccess: "danger-full-access"],
            extraArguments: ["--model", "gpt-5-codex"]
        )

        XCTAssertEqual(
            CodexCommandBuilder.arguments(
                prompt: "Run",
                permissionMode: .semiAutomatic,
                configuration: configuration
            ),
            ["exec", "--json", "--model", "gpt-5-codex", "--sandbox", "workspace-write", "--", "Run"]
        )
    }
}
