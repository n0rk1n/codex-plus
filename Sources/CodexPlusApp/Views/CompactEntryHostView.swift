import CodexPlusCore
import SwiftUI

struct CompactEntryHostView: View {
    @ObservedObject var batteryMonitor: BatteryStatusMonitor
    @ObservedObject var codexUsageMonitor: CodexUsageMonitor
    @ObservedObject var dailyTokenUsageMonitor: DailyTokenUsageMonitor
    let onOpenDraft: (String) -> Void
    let onOpenCodexDesktop: () -> Void
    let onSubmit: (String) -> Void

    var body: some View {
        CompactEntryView(
            batteryStatus: batteryMonitor.status,
            codexUsageStatus: codexUsageMonitor.status,
            codexUsageIsRefreshing: codexUsageMonitor.isRefreshing,
            dailyTokenStatus: dailyTokenUsageMonitor.status,
            dailyTokenIsRefreshing: dailyTokenUsageMonitor.isRefreshing,
            onOpenDraft: onOpenDraft,
            onOpenCodexDesktop: onOpenCodexDesktop,
            onSubmit: onSubmit
        )
    }
}
