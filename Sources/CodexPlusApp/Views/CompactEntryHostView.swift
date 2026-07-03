import CodexPlusCore
import SwiftUI

struct CompactEntryHostView: View {
    @ObservedObject var batteryMonitor: BatteryStatusMonitor
    @ObservedObject var codexUsageMonitor: CodexUsageMonitor
    @ObservedObject var dailyTokenUsageMonitor: DailyTokenUsageMonitor
    let onSubmit: (String) -> Void

    var body: some View {
        CompactEntryView(
            batteryStatus: batteryMonitor.status,
            codexUsageStatus: codexUsageMonitor.status,
            dailyTokenStatus: dailyTokenUsageMonitor.status,
            onSubmit: onSubmit
        )
    }
}
