import Foundation

public protocol CodexUsageProviding: Sendable {
    func currentStatus() -> CodexUsageStatus
}

public struct LocalCodexUsageProvider: CodexUsageProviding, @unchecked Sendable {
    private let sessionDirectories: [URL]
    private let archiveDirectories: [URL]
    private let fileManager: FileManager

    public init(
        sessionDirectories: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")],
        archiveDirectories: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/archived_sessions")],
        fileManager: FileManager = .default
    ) {
        self.sessionDirectories = sessionDirectories
        self.archiveDirectories = archiveDirectories
        self.fileManager = fileManager
    }

    public func currentStatus() -> CodexUsageStatus {
        let files = candidateFiles()
        var currentNewestStatus = CodexUsageStatus.unknown

        for file in files {
            guard let fileStatus = newestStatus(in: file) else {
                continue
            }

            if shouldReplace(currentNewestStatus, with: fileStatus) {
                currentNewestStatus = fileStatus
            }
        }

        return currentNewestStatus
    }

    private func candidateFiles() -> [URL] {
        let directories = sessionDirectories + archiveDirectories
        var files: [(url: URL, modifiedAt: Date)] = []

        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else {
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true
                else {
                    continue
                }

                files.append((url, values.contentModificationDate ?? .distantPast))
            }
        }

        return files
            .sorted { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }
            .map(\.url)
    }

    private func newestStatus(in file: URL) -> CodexUsageStatus? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
            return nil
        }

        var newestStatus: CodexUsageStatus?
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let status = Self.status(fromJSONLine: String(line)) else {
                continue
            }

            if shouldReplace(newestStatus, with: status) {
                newestStatus = status
            }
        }

        return newestStatus
    }

    private func shouldReplace(_ current: CodexUsageStatus?, with candidate: CodexUsageStatus) -> Bool {
        guard let current else {
            return true
        }

        guard let currentDate = current.observedAt else {
            return true
        }

        guard let candidateDate = candidate.observedAt else {
            return false
        }

        return candidateDate > currentDate
    }

    static func status(fromJSONLine line: String) -> CodexUsageStatus? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        let timestamp = (object["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        let fiveHourPercent = Self.percent(from: rateLimits["primary"], expectedWindowMinutes: 300)
        let weeklyPercent = Self.percent(from: rateLimits["secondary"], expectedWindowMinutes: 10_080)

        guard fiveHourPercent != nil || weeklyPercent != nil else {
            return nil
        }

        return CodexUsageStatus(
            fiveHourPercent: fiveHourPercent,
            weeklyPercent: weeklyPercent,
            observedAt: timestamp
        )
    }

    private static func percent(from value: Any?, expectedWindowMinutes: Int) -> Int? {
        guard let object = value as? [String: Any],
              object["window_minutes"] as? Int == expectedWindowMinutes
        else {
            return nil
        }

        if let integer = object["used_percent"] as? Int {
            return integer
        }

        if let double = object["used_percent"] as? Double {
            return Int(double.rounded())
        }

        return nil
    }
}
