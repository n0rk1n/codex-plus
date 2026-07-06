import CodexPlusCore
import SwiftUI

struct WorkbenchStatusBarView: View {
    let state: WorkbenchStatusBarState
    let codexUsageStatus: CodexUsageStatus

    var body: some View {
        HStack(spacing: 18) {
            usageLimitSummary(status: codexUsageStatus)

            Spacer(minLength: 0)

            Text("Codex CLI 可用")
            Text("SQLite 已连接")
            Text("归档索引 待更新")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func usageLimitSummary(status: CodexUsageStatus) -> some View {
        HStack(spacing: 14) {
            StatusUsageLimitText(
                label: "5h",
                value: status.displayPercentText(for: .fiveHour),
                color: usageColor(for: .fiveHour, status: status)
            )
            StatusUsageLimitText(
                label: "1w",
                value: status.displayPercentText(for: .weekly),
                color: usageColor(for: .weekly, status: status)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex usage, five hours \(accessibilityPercentText(status.fiveHourPercent)), one week \(accessibilityPercentText(status.weeklyPercent))")
    }

    private func usageColor(for window: CodexUsageWindow, status: CodexUsageStatus) -> Color {
        guard status.percent(for: window) != nil else {
            return .secondary
        }

        let ringColor = status.ringColor(for: window)

        return Color(
            red: ringColor.red,
            green: ringColor.green,
            blue: ringColor.blue,
            opacity: ringColor.opacity
        )
    }

    private func accessibilityPercentText(_ percent: Int?) -> String {
        guard let percent else {
            return "no data"
        }

        return "\(percent) percent"
    }
}

private struct StatusUsageLimitText: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)

            Text(value)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}
