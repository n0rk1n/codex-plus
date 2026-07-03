import QuickAIDashboardCore
import SwiftUI

struct CompactEntryHostView: View {
    @ObservedObject var batteryMonitor: BatteryStatusMonitor
    @ObservedObject var codexUsageMonitor: CodexUsageMonitor
    let onSubmit: (String) -> Void

    var body: some View {
        CompactEntryView(
            batteryStatus: batteryMonitor.status,
            codexUsageStatus: codexUsageMonitor.status,
            onSubmit: onSubmit
        )
    }
}
