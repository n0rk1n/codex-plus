import Foundation

public enum CodexCommandBuilder {
    public static func arguments(prompt: String, permissionMode: PermissionMode) -> [String] {
        [
            "exec",
            "--json",
            "--skip-git-repo-check",
            "--sandbox",
            sandboxValue(for: permissionMode),
            "--",
            prompt
        ]
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
