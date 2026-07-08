import CodexPlusCore
import SwiftUI

struct DailyTokenTileView: View {
    let status: DailyTokenStatus
    let isRefreshing: Bool

    var body: some View {
        LiquidGlassContainer(cornerRadius: CodexRadius.card) {
            ZStack {
                VStack(spacing: CompactDashboardMetricTileLayout.footerSpacing) {
                    HStack(spacing: 6) {
                        DailyTokenMetricColumn(label: "IN", value: status.inputText, color: inputOutputColor)
                        DailyTokenMetricColumn(label: "OUT", value: status.outputText, color: inputOutputColor)
                        DailyTokenMetricColumn(label: "HIT", value: status.hitRateText, color: hitRateColor)
                    }
                    .frame(height: CompactDashboardMetricTileLayout.metricRowHeight)

                    Text("Today Tokens")
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
            .frame(
                width: CGFloat(CompactDashboardTileDragPolicy.dailyTokensTileWidth),
                height: CGFloat(CompactDashboardTileDragPolicy.tileStripHeight)
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var placeholderValueColor: Color {
        CodexColors.secondaryText
    }

    private var inputOutputColor: Color {
        status.observedAt == nil ? placeholderValueColor : .primary
    }

    private var successValueColor: Color {
        CodexUsageColors.lowUsage
    }

    private var hitRateColor: Color {
        status.hitRatePercent == nil ? placeholderValueColor : successValueColor
    }

    private var accessibilityText: String {
        "Today tokens, input \(status.inputText), output \(status.outputText), cache hit \(status.hitRateText)"
    }

}

private struct DailyTokenMetricColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(CodexTypography.usageMetricLabel)
                .foregroundStyle(.primary)
                .frame(height: CompactDashboardMetricTileLayout.labelRowHeight)

            Text(value)
                .font(CodexTypography.usageMetricValue)
                .foregroundStyle(color)
                .frame(height: CompactDashboardMetricTileLayout.valueRowHeight)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .frame(maxWidth: .infinity)
        .frame(height: CompactDashboardMetricTileLayout.metricRowHeight)
    }
}
