import Combine
import Foundation

@MainActor
public final class CodexUsageMonitor: ObservableObject {
    @Published public private(set) var status: CodexUsageStatus

    private let provider: any CodexUsageProviding
    private let interval: TimeInterval
    private var timer: Timer?

    public init(
        provider: any CodexUsageProviding,
        initialStatus: CodexUsageStatus = .unknown,
        interval: TimeInterval = 60
    ) {
        self.provider = provider
        self.status = initialStatus
        self.interval = interval
    }

    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
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
    }

    public func refresh() {
        status = provider.currentStatus()
    }
}
