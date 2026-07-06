import Foundation

public protocol CodexUsageStatusCaching: Sendable {
    func loadStatus() -> CodexUsageStatus?
    func saveStatus(_ status: CodexUsageStatus)
}

public protocol DailyTokenStatusCaching: Sendable {
    func loadStatus() -> DailyTokenStatus?
    func saveStatus(_ status: DailyTokenStatus)
}

public final class FileCodexUsageStatusCache: CodexUsageStatusCaching, @unchecked Sendable {
    private let fileURL: URL

    public init(
        fileURL: URL = URL(fileURLWithPath: ApplicationSupportPaths.codexUsageStatusCachePath())
    ) {
        self.fileURL = fileURL
    }

    public func loadStatus() -> CodexUsageStatus? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? JSONDecoder().decode(CodexUsageStatus.self, from: data)
    }

    public func saveStatus(_ status: CodexUsageStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}

public final class FileDailyTokenStatusCache: DailyTokenStatusCaching, @unchecked Sendable {
    private let fileURL: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        fileURL: URL = URL(fileURLWithPath: ApplicationSupportPaths.dailyTokenStatusCachePath()),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
    }

    public func loadStatus() -> DailyTokenStatus? {
        guard let data = try? Data(contentsOf: fileURL),
              let status = try? JSONDecoder().decode(DailyTokenStatus.self, from: data),
              let observedAt = status.observedAt,
              calendar.isDate(observedAt, inSameDayAs: now())
        else {
            return nil
        }

        return status
    }

    public func saveStatus(_ status: DailyTokenStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }
}
