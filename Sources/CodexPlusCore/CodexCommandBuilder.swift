import Foundation

public enum CodexCommandBuilder {
    public static func arguments(
        prompt: String,
        permissionMode: PermissionMode,
        configuration: CodexCommandConfiguration = .default
    ) -> [String] {
        var arguments = ["exec", "--json"]

        if configuration.skipGitRepoCheck {
            arguments.append("--skip-git-repo-check")
        }

        arguments.append(contentsOf: configuration.extraArguments)
        arguments.append("--sandbox")
        arguments.append(configuration.sandboxByPermissionMode[permissionMode] ?? sandboxValue(for: permissionMode))
        arguments.append("--")
        arguments.append(prompt)

        return arguments
    }

    private static func sandboxValue(for permissionMode: PermissionMode) -> String {
        switch permissionMode {
        case .semiAutomatic:
            return "read-only"
        case .fullAccess:
            return "danger-full-access"
        }
    }
}
