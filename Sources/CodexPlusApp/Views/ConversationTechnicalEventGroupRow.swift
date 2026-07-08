import CodexPlusCore
import SwiftUI

struct ConversationTechnicalEventGroupRow: View {
    let events: [ConversationDisplayEvent]
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CodexButton(rule: .rowRectangle, accessibilityLabel: accessibilityText, action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(CodexTypography.compactBadge)
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Details · \(eventCountText)")
                            .font(CodexTypography.captionStrong)
                            .foregroundStyle(.secondary)

                        Text(summaryText)
                            .font(CodexTypography.compactTechnicalSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(events) { event in
                        ConversationEventRow(event: event)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    private var summaryText: String {
        var parts: [String] = []
        let statusCount = events.filter(\.isStatusTimelineEvent).count
        let commandCount = events.filter(\.isCommandTimelineEvent).count
        let warningCount = events.filter(\.isParseWarningTimelineEvent).count

        if statusCount > 0 {
            parts.append(countLabel(statusCount, singular: "status", plural: "statuses"))
        }

        if commandCount > 0 {
            parts.append(countLabel(commandCount, singular: "command", plural: "commands"))
        }

        if warningCount > 0 {
            parts.append(countLabel(warningCount, singular: "warning", plural: "warnings"))
        }

        return parts.joined(separator: ", ")
    }

    private var eventCountText: String {
        countLabel(events.count, singular: "event", plural: "events")
    }

    private var accessibilityText: String {
        isExpanded ? "Hide technical details" : "Show technical details"
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
