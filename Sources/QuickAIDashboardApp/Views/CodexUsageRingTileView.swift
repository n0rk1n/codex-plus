import QuickAIDashboardCore
import SwiftUI

struct CodexUsageRingTileView: View {
    let status: CodexUsageStatus

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            VStack(spacing: 7) {
                HStack(spacing: 0) {
                    UsageMetricColumn(
                        label: "5h",
                        value: status.displayPercentText(for: .fiveHour),
                        color: color(for: .fiveHour)
                    )

                    UsageMetricColumn(
                        label: "1w",
                        value: status.displayPercentText(for: .weekly),
                        color: color(for: .weekly)
                    )
                }

                Text(labelText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 92, height: 92)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var labelText: String {
        if status.fiveHourPercent == nil && status.weeklyPercent == nil {
            return "No Data"
        }

        return "Codex"
    }

    private var accessibilityText: String {
        if status.fiveHourPercent == nil && status.weeklyPercent == nil {
            return "Codex usage, no data"
        }

        return "Codex usage, five hours \(accessibilityPercentText(status.fiveHourPercent)), one week \(accessibilityPercentText(status.weeklyPercent))"
    }

    private func accessibilityPercentText(_ percent: Int?) -> String {
        guard let percent else {
            return "no data"
        }

        return "\(percent) percent"
    }

    private func color(for window: CodexUsageWindow) -> Color {
        let ringColor = status.ringColor(for: window)

        return Color(
            red: ringColor.red,
            green: ringColor.green,
            blue: ringColor.blue,
            opacity: ringColor.opacity
        )
    }
}

private struct UsageMetricColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
    }
}
