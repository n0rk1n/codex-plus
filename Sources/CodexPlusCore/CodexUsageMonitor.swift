import Combine
import Foundation

@MainActor
public final class CodexUsageMonitor: ObservableObject {
    public static let defaultRefreshInterval: TimeInterval = 180

    @Published public private(set) var status: CodexUsageStatus
    @Published public private(set) var isRefreshing = false

    private let provider: any CodexUsageProviding
    private let statusCache: (any CodexUsageStatusCaching)?
    private let interval: TimeInterval
    private let refreshQueue = DispatchQueue(label: "CodexPlusCore.CodexUsageMonitor.refresh", qos: .utility)
    private var timer: Timer?
    private var refreshID = UUID()

    public init(
        provider: any CodexUsageProviding,
        initialStatus: CodexUsageStatus = .unknown,
        statusCache: (any CodexUsageStatusCaching)? = FileCodexUsageStatusCache(),
        interval: TimeInterval = CodexUsageMonitor.defaultRefreshInterval
    ) {
        self.provider = provider
        self.statusCache = statusCache
        self.status = initialStatus == .unknown ? statusCache?.loadStatus() ?? initialStatus : initialStatus
        self.interval = interval
    }

    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
            refreshID = UUID()
        }
    }

    public func start() {
        refresh()

        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        refreshID = UUID()
        isRefreshing = false
    }

    public func refresh() {
        let requestedRefreshID = UUID()
        refreshID = requestedRefreshID
        isRefreshing = true
        let provider = provider

        refreshQueue.async { [provider, requestedRefreshID, weak self] in
            let nextStatus = provider.currentStatus()

            Task { @MainActor [weak self] in
                guard let self, self.refreshID == requestedRefreshID else {
                    return
                }

                if nextStatus != .unknown {
                    self.statusCache?.saveStatus(nextStatus)
                }
                self.status = self.statusCache?.loadStatus() ?? nextStatus
                self.isRefreshing = false
            }
        }
    }
}
