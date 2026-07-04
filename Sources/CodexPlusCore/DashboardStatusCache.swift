import Foundation

public protocol CodexUsageStatusCaching: Sendable {
    func loadStatus() -> CodexUsageStatus?
    func saveStatus(_ status: CodexUsageStatus)
}

public protocol DailyTokenStatusCaching: Sendable {
    func loadStatus() -> DailyTokenStatus?
    func saveStatus(_ status: DailyTokenStatus)
}

public final class UserDefaultsCodexUsageStatusCache: CodexUsageStatusCaching, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "CodexPlus.codexUsageStatus"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func loadStatus() -> CodexUsageStatus? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(CodexUsageStatus.self, from: data)
    }

    public func saveStatus(_ status: CodexUsageStatus) {
        guard let data = try? JSONEncoder().encode(status) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

public final class UserDefaultsDailyTokenStatusCache: DailyTokenStatusCaching, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        defaults: UserDefaults = .standard,
        key: String = "CodexPlus.dailyTokenStatus",
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.key = key
        self.calendar = calendar
        self.now = now
    }

    public func loadStatus() -> DailyTokenStatus? {
        guard let data = defaults.data(forKey: key),
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

        defaults.set(data, forKey: key)
    }
}
