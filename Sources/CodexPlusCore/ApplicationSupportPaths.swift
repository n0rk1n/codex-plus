import Foundation

public enum ApplicationSupportPaths {
    public static func databasePath(
        bundleIdentifier: String = "com.oriki.CodexPlus",
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("CodexPlus.sqlite", isDirectory: false)
            .path
    }
}
