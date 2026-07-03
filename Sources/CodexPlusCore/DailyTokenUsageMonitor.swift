import Combine
import Foundation

@MainActor
public final class DailyTokenUsageMonitor: ObservableObject {
    public static let defaultLowVolumeRefreshInterval: TimeInterval = 30
    public static let defaultHighVolumeRefreshInterval: TimeInterval = 60
    public static let highVolumeTokenThreshold = 1_000_000

    @Published public private(set) var status: DailyTokenStatus

    private let provider: any DailyTokenUsageProviding
    private let refreshQueue = DispatchQueue(label: "CodexPlusCore.DailyTokenUsageMonitor.refresh", qos: .utility)
    private var timer: Timer?
    private var refreshID = UUID()

    public init(
        provider: any DailyTokenUsageProviding,
        initialStatus: DailyTokenStatus = .unknown
    ) {
        self.provider = provider
        self.status = initialStatus
    }

    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
            refreshID = UUID()
        }
    }

    public func start() {
        guard timer == nil else {
            return
        }

        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        refreshID = UUID()
    }

    public func refresh() {
        timer?.invalidate()
        timer = nil

        let requestedRefreshID = UUID()
        refreshID = requestedRefreshID
        let provider = provider

        refreshQueue.async { [provider, requestedRefreshID, weak self] in
            let nextStatus = provider.currentStatus()

            Task { @MainActor [weak self] in
                guard let self, self.refreshID == requestedRefreshID else {
                    return
                }

                self.status = nextStatus
                self.scheduleNextRefresh(for: nextStatus)
            }
        }
    }

    public static func refreshInterval(for status: DailyTokenStatus) -> TimeInterval {
        if status.totalTokens >= highVolumeTokenThreshold {
            return defaultHighVolumeRefreshInterval
        }

        return defaultLowVolumeRefreshInterval
    }

    private func scheduleNextRefresh(for status: DailyTokenStatus) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval(for: status), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}
