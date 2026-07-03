import Foundation

public protocol DailyTokenUsageProviding: Sendable {
    func currentStatus() -> DailyTokenStatus
}

public struct LocalDailyTokenUsageProvider: DailyTokenUsageProviding {
    private struct DailyTokenEvent {
        let inputTokens: Int
        let outputTokens: Int
        let cachedInputTokens: Int
        let observedAt: Date
    }

    private static let readChunkSize = 64 * 1024
    private static let lineFeed: UInt8 = 10
    private static let carriageReturn: UInt8 = 13

    private let sessionDirectories: [URL]
    private let archiveDirectories: [URL]
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        sessionDirectories: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")],
        archiveDirectories: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/archived_sessions")],
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sessionDirectories = sessionDirectories
        self.archiveDirectories = archiveDirectories
        self.calendar = calendar
        self.now = now
    }

    public func currentStatus() -> DailyTokenStatus {
        guard let dayInterval = calendar.dateInterval(of: .day, for: now()) else {
            return .unknown
        }

        var inputTokens = 0
        var outputTokens = 0
        var cachedInputTokens = 0
        var observedAt: Date?

        for file in candidateFiles() {
            for event in events(in: file, dayInterval: dayInterval) {
                inputTokens += event.inputTokens
                outputTokens += event.outputTokens
                cachedInputTokens += event.cachedInputTokens

                if observedAt == nil || event.observedAt > observedAt! {
                    observedAt = event.observedAt
                }
            }
        }

        guard let observedAt else {
            return .unknown
        }

        return DailyTokenStatus(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: cachedInputTokens,
            observedAt: observedAt
        )
    }

    private func candidateFiles() -> [URL] {
        let directories = sessionDirectories + archiveDirectories
        let fileManager = FileManager.default
        var files: [URL] = []

        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else {
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true
                else {
                    continue
                }

                files.append(url)
            }
        }

        return files
    }

    private func events(in file: URL, dayInterval: DateInterval) -> [DailyTokenEvent] {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer {
                try? handle.close()
            }

            var events: [DailyTokenEvent] = []
            var lineData = Data()

            while true {
                guard let chunk = try handle.read(upToCount: Self.readChunkSize),
                      !chunk.isEmpty
                else {
                    break
                }

                for byte in chunk {
                    if byte == Self.lineFeed || byte == Self.carriageReturn {
                        appendEvent(from: lineData, dayInterval: dayInterval, events: &events)
                        lineData.removeAll(keepingCapacity: true)
                    } else {
                        lineData.append(byte)
                    }
                }
            }

            appendEvent(from: lineData, dayInterval: dayInterval, events: &events)
            return events
        } catch {
            return []
        }
    }

    private func appendEvent(from lineData: Data, dayInterval: DateInterval, events: inout [DailyTokenEvent]) {
        guard !lineData.isEmpty,
              let line = String(data: lineData, encoding: .utf8),
              let event = Self.event(fromJSONLine: line, dayInterval: dayInterval)
        else {
            return
        }

        events.append(event)
    }

    private static func event(fromJSONLine line: String, dayInterval: DateInterval) -> DailyTokenEvent? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestamp = Self.timestamp(from: object["timestamp"] as? String),
              dayInterval.contains(timestamp),
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any],
              let inputTokens = Self.integer(from: usage["input_tokens"]),
              let outputTokens = Self.integer(from: usage["output_tokens"])
        else {
            return nil
        }

        return DailyTokenEvent(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedInputTokens: Self.integer(from: usage["cached_input_tokens"]) ?? 0,
            observedAt: timestamp
        )
    }

    private static func integer(from value: Any?) -> Int? {
        if let integer = value as? Int {
            return integer
        }

        if let double = value as? Double {
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
