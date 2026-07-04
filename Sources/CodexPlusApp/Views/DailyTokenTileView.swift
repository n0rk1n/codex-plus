import CodexPlusCore
import SwiftUI

struct DailyTokenTileView: View {
    let status: DailyTokenStatus
    let isRefreshing: Bool

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            ZStack {
                VStack(spacing: CompactDashboardMetricTileLayout.footerSpacing) {
                    HStack(spacing: 6) {
                        DailyTokenMetricColumn(label: "IN", value: status.inputText, color: inputOutputColor)
                        DailyTokenMetricColumn(label: "OUT", value: status.outputText, color: inputOutputColor)
                        DailyTokenMetricColumn(label: "HIT", value: status.hitRateText, color: hitRateColor)
                    }
                    .frame(height: CompactDashboardMetricTileLayout.metricRowHeight)

                    Text("Today Tokens")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
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
                                .tint(.secondary)
                                .frame(width: 16, height: 16)
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 7)
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
        .secondary
    }

    private var inputOutputColor: Color {
        status.observedAt == nil ? placeholderValueColor : .primary
    }

    private var successValueColor: Color {
        color(from: CodexUsageRingColor.lowUsageGreen)
    }

    private var hitRateColor: Color {
        status.hitRatePercent == nil ? placeholderValueColor : successValueColor
    }

    private var accessibilityText: String {
        "Today tokens, input \(status.inputText), output \(status.outputText), cache hit \(status.hitRateText)"
    }

    private func color(from ringColor: CodexUsageRingColor) -> Color {
        Color(
            red: ringColor.red,
            green: ringColor.green,
            blue: ringColor.blue,
            opacity: ringColor.opacity
        )
    }
}

private struct DailyTokenMetricColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(height: CompactDashboardMetricTileLayout.labelRowHeight)

            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .frame(height: CompactDashboardMetricTileLayout.valueRowHeight)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .frame(maxWidth: .infinity)
        .frame(height: CompactDashboardMetricTileLayout.metricRowHeight)
    }
}
