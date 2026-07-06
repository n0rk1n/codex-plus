import Foundation

public struct PersistedConversationEvent: Equatable, Sendable {
    public var id: String
    public var ordinal: Int
    public var kind: String
    public var displayText: String
    public var payloadJSON: String
    public var rawPayloadJSON: String?
    public var createdAt: Date
    public var searchableText: String
}

public enum ConversationEventCodec {
    public static func encode(
        _ event: ConversationDisplayEvent,
        ordinal: Int,
        fallbackDate: Date
    ) throws -> PersistedConversationEvent {
        let createdAt = fallbackDate.addingTimeInterval(Double(ordinal) / 1000.0)

        switch event {
        case let .userPrompt(id, text):
            return try record(
                id: id,
                ordinal: ordinal,
                kind: "user_prompt",
                text: text,
                payload: TextPayload(id: id, text: text),
                createdAt: createdAt
            )
        case let .status(id, text):
            return try record(
                id: id,
                ordinal: ordinal,
                kind: "status",
                text: text,
                payload: TextPayload(id: id, text: text),
                createdAt: createdAt
            )
        case let .assistantMessage(id, text):
            return try record(
                id: id,
                ordinal: ordinal,
                kind: "assistant_message",
                text: text,
                payload: TextPayload(id: id, text: text),
                createdAt: createdAt
            )
        case let .command(id, executionID, command, status):
            return try record(
                id: id,
                ordinal: ordinal,
                kind: "command",
                text: command,
                payload: CommandPayload(id: id, executionID: executionID, command: command, status: status),
                createdAt: createdAt
            )
        case let .error(id, text):
            return try record(
                id: id,
                ordinal: ordinal,
                kind: "error",
                text: text,
                payload: TextPayload(id: id, text: text),
                createdAt: createdAt
            )
        case let .parseWarning(id, text):
            return try record(
                id: id,
                ordinal: ordinal,
                kind: "parse_warning",
                text: text,
                payload: TextPayload(id: id, text: text),
                createdAt: createdAt
            )
        }
    }

    public static func decode(kind: String, payloadJSON: String) throws -> ConversationDisplayEvent {
        let data = Data(payloadJSON.utf8)
        let decoder = JSONDecoder()

        switch kind {
        case "user_prompt":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .userPrompt(id: payload.id, text: payload.text)
        case "status":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .status(id: payload.id, text: payload.text)
        case "assistant_message":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .assistantMessage(id: payload.id, text: payload.text)
        case "command":
            let payload = try decoder.decode(CommandPayload.self, from: data)
            return .command(
                id: payload.id,
                executionID: payload.executionID,
                command: payload.command,
                status: payload.status
            )
        case "error":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .error(id: payload.id, text: payload.text)
        case "parse_warning":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .parseWarning(id: payload.id, text: payload.text)
        default:
            throw ConversationEventCodecError.invalidEventKind(kind)
        }
    }

    private static func record<Payload: Encodable>(
        id: UUID,
        ordinal: Int,
        kind: String,
        text: String,
        payload: Payload,
        createdAt: Date
    ) throws -> PersistedConversationEvent {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)

        return PersistedConversationEvent(
            id: id.uuidString.lowercased(),
            ordinal: ordinal,
            kind: kind,
            displayText: text,
            payloadJSON: String(decoding: data, as: UTF8.self),
            rawPayloadJSON: nil,
            createdAt: createdAt,
            searchableText: text
        )
    }
}

public enum ConversationEventCodecError: Error, Equatable, CustomStringConvertible {
    case invalidEventKind(String)

    public var description: String {
        switch self {
        case let .invalidEventKind(kind):
            return "Invalid event kind: \(kind)"
        }
    }
}

private struct TextPayload: Codable {
    var id: UUID
    var text: String
}

private struct CommandPayload: Codable {
    var id: UUID
    var executionID: String?
    var command: String
    var status: CodexCommandStatus

    enum CodingKeys: String, CodingKey {
        case id
        case executionID = "execution_id"
        case command
        case status
    }

    init(id: UUID, executionID: String?, command: String, status: CodexCommandStatus) {
        self.id = id
        self.executionID = executionID
        self.command = command
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let statusRawValue = try container.decode(String.self, forKey: .status)
        guard let status = CodexCommandStatus(rawValue: statusRawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Invalid command status: \(statusRawValue)"
            )
        }

        self.id = try container.decode(UUID.self, forKey: .id)
        self.executionID = try container.decodeIfPresent(String.self, forKey: .executionID)
        self.command = try container.decode(String.self, forKey: .command)
        self.status = status
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(executionID, forKey: .executionID)
        try container.encode(command, forKey: .command)
        try container.encode(status.rawValue, forKey: .status)
    }
}
