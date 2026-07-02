import Foundation

public enum CodexCommandStatus: String, Equatable, Sendable {
    case inProgress
    case completed
    case failed
    case unknown

    public static func from(jsonStatus: String?) -> CodexCommandStatus {
        switch jsonStatus {
        case "in_progress":
            return .inProgress
        case "completed":
            return .completed
        case "failed":
            return .failed
        default:
            return .unknown
        }
    }
}

public enum CodexEvent: Equatable, Sendable {
    case threadStarted(String)
    case turnStarted
    case turnCompleted
    case turnFailed(String)
    case agentMessage(String)
    case command(id: String?, command: String, status: CodexCommandStatus)
    case error(String)
    case raw(String)
    case parseWarning(String)
}

public enum CodexEventParser {
    public static func parseLine(_ line: String) -> CodexEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .raw("")
        }

        guard let data = trimmed.data(using: .utf8) else {
            return .parseWarning(trimmed)
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .parseWarning(trimmed)
        }

        guard let object = json as? [String: Any] else {
            return .parseWarning(trimmed)
        }

        guard let type = object["type"] as? String else {
            return .raw(trimmed)
        }

        switch type {
        case "thread.started":
            guard let threadID = object["thread_id"] as? String else {
                return .parseWarning(trimmed)
            }
            return .threadStarted(threadID)
        case "turn.started":
            return .turnStarted
        case "turn.completed":
            return .turnCompleted
        case "turn.failed":
            return .turnFailed(message(from: object, fallback: "Turn failed"))
        case "error":
            return .error(message(from: object, fallback: "Unknown error"))
        case "item.started", "item.completed":
            return parseItemEvent(type: type, object: object, rawLine: trimmed)
        default:
            return .raw(trimmed)
        }
    }

    private static func parseItemEvent(
        type: String,
        object: [String: Any],
        rawLine: String
    ) -> CodexEvent {
        guard let item = object["item"] as? [String: Any],
              let itemType = item["type"] as? String else {
            return .raw(rawLine)
        }

        switch itemType {
        case "agent_message":
            guard let text = item["text"] as? String, !text.isEmpty else {
                return .raw(rawLine)
            }
            return .agentMessage(text)
        case "command_execution":
            guard let command = item["command"] as? String else {
                return .parseWarning(rawLine)
            }
            return .command(
                id: item["id"] as? String,
                command: command,
                status: commandStatus(for: type, item: item)
            )
        default:
            return .raw(rawLine)
        }
    }

    private static func commandStatus(for eventType: String, item: [String: Any]) -> CodexCommandStatus {
        if eventType == "item.started" {
            return .inProgress
        }

        if let status = item["status"] as? String {
            return CodexCommandStatus.from(jsonStatus: status)
        }

        if eventType == "item.completed" {
            return .completed
        }

        return .unknown
    }

    private static func message(from object: [String: Any], fallback: String) -> String {
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }

        return fallback
    }
}
