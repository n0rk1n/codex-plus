import QuickAIDashboardCore
import SwiftUI

struct CompactEntryHostView: View {
    @ObservedObject var batteryMonitor: BatteryStatusMonitor
    let onSubmit: (String) -> Void

    var body: some View {
        CompactEntryView(
            batteryStatus: batteryMonitor.status,
            onSubmit: onSubmit
        )
    }
}
