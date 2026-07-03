import QuickAIDashboardCore
import SwiftUI

struct CodexUsageRingTileView: View {
    let status: CodexUsageStatus

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            ZStack {
                UsageRing(
                    percent: status.fiveHourPercent,
                    color: color(for: .fiveHour),
                    lineWidth: 7,
                    diameter: 72
                )

                UsageRing(
                    percent: status.weeklyPercent,
                    color: color(for: .weekly),
                    lineWidth: 5,
                    diameter: 52
                )

                VStack(spacing: 1) {
                    Text("5H \(percentText(status.fiveHourPercent))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("1W \(percentText(status.weeklyPercent))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(labelText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 54)
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
        "Codex usage, five hours \(percentText(status.fiveHourPercent)), one week \(percentText(status.weeklyPercent))"
    }

    private func percentText(_ percent: Int?) -> String {
        guard let percent else {
            return "--%"
        }

        return "\(percent)%"
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

private struct UsageRing: View {
    let percent: Int?
    let color: Color
    let lineWidth: CGFloat
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private var progress: CGFloat {
        guard let percent else {
            return 0
        }

        return CGFloat(max(0, min(100, percent))) / 100
    }
}
