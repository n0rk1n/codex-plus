import Combine
import Foundation

@MainActor
public final class CodexUsageMonitor: ObservableObject {
    public static let defaultRefreshInterval: TimeInterval = 120

    @Published public private(set) var status: CodexUsageStatus

    private let provider: any CodexUsageProviding
    private let interval: TimeInterval
    private let refreshQueue = DispatchQueue(label: "QuickAIDashboardCore.CodexUsageMonitor.refresh", qos: .utility)
    private var timer: Timer?
    private var refreshID = UUID()

    public init(
        provider: any CodexUsageProviding,
        initialStatus: CodexUsageStatus = .unknown,
        interval: TimeInterval = CodexUsageMonitor.defaultRefreshInterval
    ) {
        self.provider = provider
        self.status = initialStatus
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
    }

    public func refresh() {
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
            }
        }
    }
}
