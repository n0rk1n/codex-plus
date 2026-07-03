import QuickAIDashboardCore
import SwiftUI

struct CodexUsageRingTileView: View {
    let status: CodexUsageStatus

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
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
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 138, height: 92)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var labelText: String {
        "Codex Usage"
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
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .frame(maxWidth: .infinity)
    }
}
