import CodexPlusCore
import SwiftUI

struct BatteryTileView: View {
    let status: BatteryStatus

    var body: some View {
        LiquidGlassContainer(cornerRadius: CodexRadius.card) {
            VStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(CodexTypography.batteryPercentValue)
                    .symbolRenderingMode(.hierarchical)

                Text(percentageText)
                    .font(CodexTypography.batteryStateValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(stateText)
                    .font(CodexTypography.caption2Medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(foregroundStyle)
            .frame(width: CGFloat(CompactDashboardTileDragPolicy.batteryTileWidth), height: CGFloat(CompactDashboardTileDragPolicy.tileStripHeight))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var percentageText: String {
        guard let percentage = status.percentage else {
            return "--%"
        }

        return "\(percentage)%"
    }

    private var stateText: String {
        switch status.state {
        case .charging:
            return "Charging"
        case .discharging:
            return "Discharging"
        case .full:
            return "Full"
        case .pluggedIn:
            return "Plugged In"
        case .unknown:
            return "Unknown"
        }
    }

    private var symbolName: String {
        switch status.state {
        case .charging:
            return "battery.100percent.bolt"
        case .discharging:
            return "battery.75percent"
        case .full:
            return "battery.100percent"
        case .pluggedIn:
            return "powerplug"
        case .unknown:
            return "battery.0percent"
        }
    }

    private var foregroundStyle: Color {
        switch status.state {
        case .charging, .full, .pluggedIn:
            return CodexColors.stateCompleted
        case .discharging:
            return .primary
        case .unknown:
            return .secondary
        }
    }

    private var accessibilityText: String {
        "Battery \(percentageText), \(stateText)"
    }
}
