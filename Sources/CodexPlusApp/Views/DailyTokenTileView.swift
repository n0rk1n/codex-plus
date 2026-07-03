import CodexPlusCore
import SwiftUI

struct DailyTokenTileView: View {
    let status: DailyTokenStatus

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    DailyTokenMetricColumn(label: "IN", value: status.inputText, color: .primary)
                    DailyTokenMetricColumn(label: "OUT", value: status.outputText, color: .primary)
                    DailyTokenMetricColumn(label: "HIT", value: status.hitRateText, color: hitRateColor)
                }

                Text("Today Tokens")
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

    private var hitRateColor: Color {
        status.hitRatePercent == nil ? .secondary : .green
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
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.58)
        .frame(maxWidth: .infinity)
    }
}
