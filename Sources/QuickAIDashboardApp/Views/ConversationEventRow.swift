import QuickAIDashboardCore
import SwiftUI

struct ConversationEventRow: View {
    let event: ConversationDisplayEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)

                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch event {
        case .userPrompt:
            return "You"
        case .status:
            return "Status"
        case .assistantMessage:
            return "Assistant"
        case .command:
            return "Command"
        case .error:
            return "Error"
        case .parseWarning:
            return "Parse Warning"
        }
    }

    private var message: String {
        switch event {
        case let .userPrompt(_, text),
             let .status(_, text),
             let .assistantMessage(_, text),
             let .error(_, text),
             let .parseWarning(_, text):
            return text
        case let .command(_, _, command, _):
            return command
        }
    }

    private var detail: String? {
        switch event {
        case let .command(_, executionID, _, status):
            if let executionID, !executionID.isEmpty {
                return "\(status.displayName) \(executionID)"
            }

            return status.displayName
        default:
            return nil
        }
    }

    private var iconName: String {
        switch event {
        case .userPrompt:
            return "person.fill"
        case .status:
            return "circle.dotted"
        case .assistantMessage:
            return "sparkles"
        case let .command(_, _, _, status):
            return status == .inProgress ? "terminal.fill" : "terminal"
        case .error:
            return "exclamationmark.triangle.fill"
        case .parseWarning:
            return "text.badge.xmark"
        }
    }

    private var tint: Color {
        switch event {
        case .userPrompt:
            return .accentColor
        case .status:
            return .secondary
        case .assistantMessage:
            return .primary
        case let .command(_, _, _, status):
            return status.tint
        case .error:
            return .red
        case .parseWarning:
            return .orange
        }
    }
}

private extension CodexCommandStatus {
    var displayName: String {
        switch self {
        case .inProgress:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .unknown:
            return "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .unknown:
            return .secondary
        }
    }
}
