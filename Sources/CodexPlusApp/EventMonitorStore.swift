import AppKit

final class EventMonitorStore: @unchecked Sendable {
    private var monitors: [Any] = []

    var isEmpty: Bool {
        monitors.isEmpty
    }

    func append(_ monitor: Any) {
        monitors.append(monitor)
    }

    func removeAll() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }

        monitors.removeAll()
    }

    deinit {
        removeAll()
    }
}
