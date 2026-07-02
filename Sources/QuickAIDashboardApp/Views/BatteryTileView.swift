import QuickAIDashboardCore
import SwiftUI

struct BatteryTileView: View {
    let status: BatteryStatus

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            VStack(spacing: 7) {
                Image(systemName: symbolName)
                    .font(.system(size: 27, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(percentageText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(stateText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(foregroundStyle)
            .frame(width: 92, height: 92)
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
        case .unknown:
            return "battery.0percent"
        }
    }

    private var foregroundStyle: Color {
        switch status.state {
        case .charging, .full:
            return .green
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
