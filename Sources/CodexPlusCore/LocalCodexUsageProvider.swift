import Foundation

public protocol CodexUsageProviding: Sendable {
    func currentStatus() -> CodexUsageStatus
}

public struct LocalCodexUsageProvider: CodexUsageProviding {
    private struct CandidateFile {
        let url: URL
        let modifiedAt: Date
        let size: Int64

        var cacheKey: String {
            url.path
        }
    }

    private struct CachedFileStatus {
        let modifiedAt: Date
        let size: Int64
        let status: CodexUsageStatus?
    }

    // Mutable cache state is protected by lock; callers never receive references
    // to the dictionary or entries, so sharing this cache across Sendable copies is safe.
    private final class FileStatusCache: @unchecked Sendable {
        private let lock = NSLock()
        private var statusesByPath: [String: CachedFileStatus] = [:]

        func cachedStatus(for file: CandidateFile) -> CodexUsageStatus?? {
            lock.lock()
            defer {
                lock.unlock()
            }

            guard let cached = statusesByPath[file.cacheKey],
                  cached.modifiedAt == file.modifiedAt,
                  cached.size == file.size
            else {
                return nil
            }

            return .some(cached.status)
        }

        func store(_ status: CodexUsageStatus?, for file: CandidateFile) {
            lock.lock()
            defer {
                lock.unlock()
            }

            statusesByPath[file.cacheKey] = CachedFileStatus(
                modifiedAt: file.modifiedAt,
                size: file.size,
                status: status
            )
        }

        func removeEntries(notIn cacheKeys: Set<String>) {
            lock.lock()
            defer {
                lock.unlock()
            }

            statusesByPath = statusesByPath.filter { cacheKeys.contains($0.key) }
        }
    }

    private static let readChunkSize = 64 * 1024
    private static let lineFeed: UInt8 = 10
    private static let carriageReturn: UInt8 = 13

    private let sessionDirectories: [URL]
    private let archiveDirectories: [URL]
    private let cache = FileStatusCache()

    public init(
        sessionDirectories: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")],
        archiveDirectories: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/archived_sessions")]
    ) {
        self.sessionDirectories = sessionDirectories
        self.archiveDirectories = archiveDirectories
    }

    public func currentStatus() -> CodexUsageStatus {
        let files = candidateFiles()
        let cacheKeys = Set(files.map(\.cacheKey))
        var currentNewestStatus = CodexUsageStatus.unknown

        for file in files {
            guard let fileStatus = status(for: file) else {
                continue
            }

            if shouldReplace(currentNewestStatus, with: fileStatus) {
                currentNewestStatus = fileStatus
            }
        }

        cache.removeEntries(notIn: cacheKeys)

        return currentNewestStatus
    }

    private func candidateFiles() -> [CandidateFile] {
        let directories = sessionDirectories + archiveDirectories
        let fileManager = FileManager.default
        var files: [CandidateFile] = []

        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else {
                    continue
                }

                guard let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
                ),
                      values.isRegularFile == true
                else {
                    continue
                }

                files.append(
                    CandidateFile(
                        url: url,
                        modifiedAt: values.contentModificationDate ?? .distantPast,
                        size: Int64(values.fileSize ?? -1)
                    )
                )
            }
        }

        return files
            .sorted { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }
    }

    private func status(for file: CandidateFile) -> CodexUsageStatus? {
        if let cachedStatus = cache.cachedStatus(for: file) {
            return cachedStatus
        }

        let fileStatus = newestStatus(in: file.url)
        cache.store(fileStatus, for: file)
        return fileStatus
    }

    private func newestStatus(in file: URL) -> CodexUsageStatus? {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer {
                try? handle.close()
            }

            var newestStatus: CodexUsageStatus?
            var lineData = Data()

            while true {
                guard let chunk = try handle.read(upToCount: Self.readChunkSize),
                      !chunk.isEmpty
                else {
                    break
                }

                for byte in chunk {
                    if byte == Self.lineFeed || byte == Self.carriageReturn {
                        updateNewestStatus(from: lineData, newestStatus: &newestStatus)
                        lineData.removeAll(keepingCapacity: true)
                    } else {
                        lineData.append(byte)
                    }
                }
            }

            updateNewestStatus(from: lineData, newestStatus: &newestStatus)
            return newestStatus
        } catch {
            return nil
        }
    }

    private func updateNewestStatus(from lineData: Data, newestStatus: inout CodexUsageStatus?) {
        guard !lineData.isEmpty,
              let line = String(data: lineData, encoding: .utf8),
              let status = Self.status(fromJSONLine: line)
        else {
            return
        }

        if shouldReplace(newestStatus, with: status) {
            newestStatus = status
        }
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

        let timestamp = Self.timestamp(from: object["timestamp"] as? String)
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

    private static func timestamp(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let wholeSecondFormatter = ISO8601DateFormatter()
        if let date = wholeSecondFormatter.date(from: value) {
            return date
        }

        let fractionalSecondFormatter = ISO8601DateFormatter()
        fractionalSecondFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalSecondFormatter.date(from: value)
    }
}
