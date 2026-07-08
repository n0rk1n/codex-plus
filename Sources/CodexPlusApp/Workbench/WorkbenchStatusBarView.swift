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
        .font(CodexTypography.statusBar)
        .foregroundStyle(CodexColors.secondaryText)
        .padding(.horizontal, 4)
    }

    private func usageLimitSummary(status: CodexUsageStatus) -> some View {
        HStack(spacing: 14) {
            StatusUsageLimitText(
                label: "5h",
                value: status.displayPercentText(for: .fiveHour),
                color: status.color(for: .fiveHour)
            )
            StatusUsageLimitText(
                label: "1w",
                value: status.displayPercentText(for: .weekly),
                color: status.color(for: .weekly)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex usage, five hours \(accessibilityPercentText(status.fiveHourPercent)), one week \(accessibilityPercentText(status.weeklyPercent))")
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
                .foregroundStyle(CodexColors.secondaryText)

            Text(value)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}
