import Foundation

public struct CodexCommandConfiguration: Equatable, Sendable {
    public var skipGitRepoCheck: Bool
    public var sandboxByPermissionMode: [PermissionMode: String]
    public var extraArguments: [String]

    public static let `default` = CodexCommandConfiguration(
        skipGitRepoCheck: true,
        sandboxByPermissionMode: [
            .semiAutomatic: "read-only",
            .fullAccess: "danger-full-access"
        ],
        extraArguments: []
    )

    public init(
        skipGitRepoCheck: Bool,
        sandboxByPermissionMode: [PermissionMode: String],
        extraArguments: [String]
    ) {
        self.skipGitRepoCheck = skipGitRepoCheck
        self.sandboxByPermissionMode = sandboxByPermissionMode
        self.extraArguments = extraArguments
    }
}
