import CodexPlusCore
import SwiftUI

extension ConversationDisplayEvent {
    var timelineTitle: String {
        switch self {
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

    var timelineMessage: String {
        switch self {
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

    var timelineIconName: String {
        switch self {
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

    var timelineTint: Color {
        switch self {
        case .userPrompt:
            return CodexColors.statePrimary
        case .status:
            return CodexColors.stateUnknown
        case .assistantMessage:
            return .primary
        case let .command(_, _, _, status):
            return status.tint
        case .error:
            return CodexColors.stateFailed
        case .parseWarning:
            return CodexColors.stateStopped
        }
    }

    var timelineDetailText: String? {
        switch self {
        case let .command(_, executionID, _, status):
            if let executionID, !executionID.isEmpty {
                return "\(status.labelText) \(executionID)"
            }

            return status.labelText
        default:
            return nil
        }
    }

    var shouldRenderTimelineMarkdown: Bool {
        switch self {
        case .userPrompt, .assistantMessage:
            return true
        case .status, .command, .error, .parseWarning:
            return false
        }
    }
}

