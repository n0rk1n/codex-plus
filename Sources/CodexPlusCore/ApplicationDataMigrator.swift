import Foundation

public enum ApplicationDataMigrator {
    public static func migrateLegacyLocalDataIfNeeded(
        bundleIdentifier: String = "com.oriki.CodexPlus",
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        fileManager: FileManager = .default
    ) throws {
        let rootURL = URL(
            fileURLWithPath: ApplicationSupportPaths.rootDirectoryPath(homeDirectoryPath: homeDirectoryPath),
            isDirectory: true
        )
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        try migrateFile(
            from: URL(fileURLWithPath: ApplicationSupportPaths.legacyDatabasePath(
                bundleIdentifier: bundleIdentifier,
                homeDirectoryPath: homeDirectoryPath
            )),
            to: URL(fileURLWithPath: ApplicationSupportPaths.databasePath(
                bundleIdentifier: bundleIdentifier,
                homeDirectoryPath: homeDirectoryPath
            )),
            fileManager: fileManager
        )

        try migrateDirectoryContents(
            from: URL(fileURLWithPath: ArchiveSearchService.legacyArchiveRootPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true),
            to: URL(fileURLWithPath: ApplicationSupportPaths.archiveRootPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true),
            fileManager: fileManager
        )

        removeEmptyLegacyDirectories(
            bundleIdentifier: bundleIdentifier,
            homeDirectoryPath: homeDirectoryPath,
            fileManager: fileManager
        )
    }

    private static func migrateFile(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: destinationURL.path)
        else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private static func migrateDirectoryContents(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return
        }

        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(
            at: sourceURL,
            includingPropertiesForKeys: nil
        )

        for sourceChildURL in children {
            let destinationChildURL = destinationURL.appendingPathComponent(sourceChildURL.lastPathComponent)
            guard !fileManager.fileExists(atPath: destinationChildURL.path) else {
                continue
            }

            try fileManager.moveItem(at: sourceChildURL, to: destinationChildURL)
        }

        if (try? fileManager.contentsOfDirectory(atPath: sourceURL.path).isEmpty) == true {
            try? fileManager.removeItem(at: sourceURL)
        }
    }

    private static func removeEmptyLegacyDirectories(
        bundleIdentifier: String,
        homeDirectoryPath: String,
        fileManager: FileManager
    ) {
        let legacyAppSupportURL = URL(fileURLWithPath: homeDirectoryPath, isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let candidateURLs = [
            legacyAppSupportURL.appendingPathComponent("CodexPlus", isDirectory: true),
            legacyAppSupportURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
        ]

        for url in candidateURLs {
            if (try? fileManager.contentsOfDirectory(atPath: url.path).isEmpty) == true {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
