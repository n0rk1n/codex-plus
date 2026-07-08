import CodexPlusCore
import SwiftUI

struct CodexUsageRingTileView: View {
    let status: CodexUsageStatus
    let isRefreshing: Bool

    var body: some View {
        LiquidGlassContainer(cornerRadius: CodexRadius.card) {
            ZStack {
                VStack(spacing: CompactDashboardMetricTileLayout.footerSpacing) {
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
                    .frame(height: CompactDashboardMetricTileLayout.metricRowHeight)

                    Text(labelText)
                        .font(CodexTypography.statusBarValue)
                        .foregroundStyle(CodexColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(height: CompactDashboardMetricTileLayout.footerRowHeight)
                }

                if isRefreshing {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .tint(CodexColors.secondaryText)
                                .frame(width: CGFloat(CompactDashboardTileDragPolicy.tileProgressIndicatorSize), height: CGFloat(CompactDashboardTileDragPolicy.tileProgressIndicatorSize))
                        }
                    }
                    .padding(.trailing, CompactDashboardMetricTileLayout.refreshIndicatorTrailingPadding)
                    .padding(.bottom, CompactDashboardMetricTileLayout.refreshIndicatorBottomPadding)
                }
            }
            .frame(width: CGFloat(CompactDashboardTileDragPolicy.codexUsageTileWidth), height: CGFloat(CompactDashboardTileDragPolicy.tileStripHeight))
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
        status.color(for: window)
    }
}

private struct UsageMetricColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(CodexTypography.usageMetricLabel)
                .foregroundStyle(.primary)
                .frame(height: CompactDashboardMetricTileLayout.labelRowHeight)

            Text(value)
                .font(CodexTypography.usageMetricValue)
                .foregroundStyle(color)
                .frame(height: CompactDashboardMetricTileLayout.valueRowHeight)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.62)
        .frame(maxWidth: .infinity)
        .frame(height: CompactDashboardMetricTileLayout.metricRowHeight)
    }
}
