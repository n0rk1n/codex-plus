import Foundation

public enum ApplicationSupportPaths {
    public static let rootDirectoryName = ".codex-plus"
    public static let databaseFileName = "CodexPlus.sqlite"
    public static let archivesDirectoryName = "Archives"
    public static let statusDirectoryName = "status"
    public static let workspacesDirectoryName = "workspaces"
    public static let codexUsageStatusFileName = "codex-usage.json"
    public static let dailyTokenStatusFileName = "daily-token.json"

    public static func rootDirectoryPath(
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
            .path
    }

    public static func databasePath(
        bundleIdentifier: String = "com.oriki.CodexPlus",
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: rootDirectoryPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true)
            .appendingPathComponent(databaseFileName, isDirectory: false)
            .path
    }

    public static func legacyDatabasePath(
        bundleIdentifier: String = "com.oriki.CodexPlus",
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(databaseFileName, isDirectory: false)
            .path
    }

    public static func archiveRootPath(
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: rootDirectoryPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true)
            .appendingPathComponent(archivesDirectoryName, isDirectory: true)
            .path
    }

    public static func statusDirectoryPath(
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: rootDirectoryPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true)
            .appendingPathComponent(statusDirectoryName, isDirectory: true)
            .path
    }

    public static func codexUsageStatusCachePath(
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: statusDirectoryPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true)
            .appendingPathComponent(codexUsageStatusFileName, isDirectory: false)
            .path
    }

    public static func dailyTokenStatusCachePath(
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: statusDirectoryPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true)
            .appendingPathComponent(dailyTokenStatusFileName, isDirectory: false)
            .path
    }
}
