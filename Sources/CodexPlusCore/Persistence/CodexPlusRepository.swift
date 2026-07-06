import Foundation

public protocol CodexPlusRepository: Sendable {
    func saveProject(_ project: WorkspaceSessionGroup) throws
    func loadProjects() throws -> [WorkspaceSessionGroup]
    func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws
    func loadConversations() throws -> [ConversationSession]
    func saveArchiveRecord(_ record: ConversationArchiveRecord) throws
    func searchArchiveRecords(query: String) throws -> [ConversationArchiveRecord]
    func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws
    func archiveConversation(record: ConversationArchiveRecord, archiveMarkdownPath: String, archivedAt: Date) throws
    func saveMemoryCard(_ card: MemoryCard) throws
    func loadMemoryCards(scope: String?) throws -> [MemoryCard]
    func deleteMemoryCard(_ id: UUID) throws
    func saveMemorySource(_ source: MemorySource) throws
    func loadMemorySources(memoryCardID: UUID) throws -> [MemorySource]
    func deleteMemorySource(_ id: UUID) throws
    func saveAttachment(_ attachment: CodexPlusAttachment) throws
    func loadAttachments(ownerKind: String, ownerID: UUID?) throws -> [CodexPlusAttachment]
    func deleteAttachment(_ id: UUID) throws
}

public extension CodexPlusRepository {
    func saveMemoryCard(_ card: MemoryCard) throws {
        throw UnsupportedRepositoryOperation()
    }

    func loadMemoryCards(scope: String?) throws -> [MemoryCard] {
        throw UnsupportedRepositoryOperation()
    }

    func deleteMemoryCard(_ id: UUID) throws {
        throw UnsupportedRepositoryOperation()
    }

    func saveMemorySource(_ source: MemorySource) throws {
        throw UnsupportedRepositoryOperation()
    }

    func loadMemorySources(memoryCardID: UUID) throws -> [MemorySource] {
        throw UnsupportedRepositoryOperation()
    }

    func deleteMemorySource(_ id: UUID) throws {
        throw UnsupportedRepositoryOperation()
    }

    func saveAttachment(_ attachment: CodexPlusAttachment) throws {
        throw UnsupportedRepositoryOperation()
    }

    func loadAttachments(ownerKind: String, ownerID: UUID?) throws -> [CodexPlusAttachment] {
        throw UnsupportedRepositoryOperation()
    }

    func deleteAttachment(_ id: UUID) throws {
        throw UnsupportedRepositoryOperation()
    }
}

private struct UnsupportedRepositoryOperation: Error {}

public final class SQLiteCodexPlusRepository: CodexPlusRepository, @unchecked Sendable {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func saveProject(_ project: WorkspaceSessionGroup) throws {
        try database.execute(
            """
            INSERT INTO projects (id, display_name, path, created_at, last_activity_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                path = excluded.path,
                last_activity_at = excluded.last_activity_at;
            """,
            [
                .text(project.id.uuidString.lowercased()),
                .text(project.displayName),
                .text(project.path),
                .real(project.lastActivityAt.timeIntervalSince1970),
                .real(project.lastActivityAt.timeIntervalSince1970)
            ]
        )
    }

    public func loadProjects() throws -> [WorkspaceSessionGroup] {
        let projectRows = try database.query(
            """
            SELECT id, display_name, path, last_activity_at
            FROM projects
            ORDER BY rowid ASC;
            """
        )

        let conversationRows = try database.query(
            """
            SELECT project_id, id
            FROM conversations
            WHERE is_archived = 0
            ORDER BY project_id ASC, created_at ASC, id ASC;
            """
        )

        var conversationIDsByProjectID: [String: [UUID]] = [:]
        for conversationRow in conversationRows {
            let projectID = try uuidString(for: "project_id", in: conversationRow)
            let conversationID = try uuid(for: "id", in: conversationRow)
            conversationIDsByProjectID[projectID, default: []].append(conversationID)
        }

        return try projectRows.map { row in
            let projectID = try uuid(for: "id", in: row)
            let conversationIDs = conversationIDsByProjectID[projectID.uuidString.lowercased()] ?? []

            return WorkspaceSessionGroup(
                id: projectID,
                path: try text(for: "path", in: row),
                displayName: try text(for: "display_name", in: row),
                conversationIDs: conversationIDs,
                lastActivityAt: Date(timeIntervalSince1970: try double(for: "last_activity_at", in: row))
            )
        }
    }

    public func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws {
        try database.execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try database.execute(
                """
                INSERT INTO conversations (
                    id,
                    project_id,
                    title,
                    prompt,
                    workspace_path,
                    state,
                    permission_mode,
                    is_pinned,
                    is_explicitly_kept,
                    is_archived,
                    created_at,
                    last_activity_at,
                    archived_at,
                    archive_markdown_path
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    project_id = excluded.project_id,
                    title = excluded.title,
                    prompt = excluded.prompt,
                    workspace_path = excluded.workspace_path,
                    state = excluded.state,
                    permission_mode = excluded.permission_mode,
                    is_pinned = excluded.is_pinned,
                    is_explicitly_kept = excluded.is_explicitly_kept,
                    is_archived = excluded.is_archived,
                    created_at = excluded.created_at,
                    last_activity_at = excluded.last_activity_at,
                    archived_at = excluded.archived_at,
                    archive_markdown_path = excluded.archive_markdown_path;
                """,
                [
                    .text(conversation.id.uuidString.lowercased()),
                    .text(projectID.uuidString.lowercased()),
                    .text(conversation.title),
                    .text(conversation.prompt),
                    .text(conversation.workspacePath),
                    .text(conversation.state.rawValue),
                    .text(conversation.permissionMode.rawValue),
                    .integer(boolToInteger(conversation.isPinned)),
                    .integer(boolToInteger(conversation.isExplicitlyKept)),
                    .integer(boolToInteger(conversation.isArchived)),
                    .real(conversation.createdAt.timeIntervalSince1970),
                    .real(conversation.lastActivityAt.timeIntervalSince1970),
                    conversation.isArchived ? .real(conversation.lastActivityAt.timeIntervalSince1970) : .null,
                    .null
                ]
            )

            try database.execute(
                "DELETE FROM conversation_events WHERE conversation_id = ?;",
                [.text(conversation.id.uuidString.lowercased())]
            )

            for (ordinal, event) in conversation.events.enumerated() {
                let record = try EncodedConversationEvent(event: event, ordinal: ordinal, fallbackDate: conversation.createdAt)
                try database.execute(
                    """
                    INSERT INTO conversation_events (
                        id,
                        conversation_id,
                        ordinal,
                        kind,
                        display_text,
                        payload_json,
                        raw_payload_json,
                        created_at,
                        searchable_text
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    [
                        .text(record.id),
                        .text(conversation.id.uuidString.lowercased()),
                        .integer(Int64(record.ordinal)),
                        .text(record.kind),
                        .text(record.displayText),
                        .text(record.payloadJSON),
                        record.rawPayloadJSON.map(SQLiteValue.text) ?? .null,
                        .real(record.createdAt.timeIntervalSince1970),
                        .text(record.searchableText)
                    ]
                )
            }

            try database.execute("COMMIT TRANSACTION;")
        } catch {
            try? database.execute("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    public func loadConversations() throws -> [ConversationSession] {
        let conversationRows = try database.query(
            """
            SELECT
                id,
                title,
                prompt,
                workspace_path,
                state,
                permission_mode,
                is_pinned,
                is_explicitly_kept,
                is_archived,
                created_at,
                last_activity_at
            FROM conversations
            ORDER BY created_at ASC, id ASC;
            """
        )

        let eventRows = try database.query(
            """
            SELECT
                id,
                conversation_id,
                ordinal,
                kind,
                payload_json
            FROM conversation_events
            ORDER BY conversation_id ASC, ordinal ASC, id ASC;
            """
        )

        var eventRowsByConversationID: [String: [[String: SQLiteValue]]] = [:]
        for row in eventRows {
            let conversationID = try uuidString(for: "conversation_id", in: row)
            eventRowsByConversationID[conversationID, default: []].append(row)
        }

        return try conversationRows.map { row in
            let conversationID = try uuid(for: "id", in: row)
            let conversationKey = conversationID.uuidString.lowercased()
            let events = try (eventRowsByConversationID[conversationKey] ?? []).map(DecodedConversationEvent.init(row:)).map(\.event)

            return ConversationSession(
                id: conversationID,
                title: try text(for: "title", in: row),
                prompt: try text(for: "prompt", in: row),
                workspacePath: try text(for: "workspace_path", in: row),
                state: try state(for: "state", in: row),
                permissionMode: try permissionMode(for: "permission_mode", in: row),
                isPinned: try bool(for: "is_pinned", in: row),
                isExplicitlyKept: try bool(for: "is_explicitly_kept", in: row),
                isArchived: try bool(for: "is_archived", in: row),
                createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row)),
                lastActivityAt: Date(timeIntervalSince1970: try double(for: "last_activity_at", in: row)),
                events: events
            )
        }
    }

    public func saveArchiveRecord(_ record: ConversationArchiveRecord) throws {
        try database.execute(
            """
            INSERT INTO archive_index (
                id,
                conversation_id,
                project_id,
                title,
                searchable_text,
                command_text,
                error_text,
                project_path,
                archived_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                conversation_id = excluded.conversation_id,
                project_id = excluded.project_id,
                title = excluded.title,
                searchable_text = excluded.searchable_text,
                command_text = excluded.command_text,
                error_text = excluded.error_text,
                project_path = excluded.project_path,
                archived_at = excluded.archived_at;
            """,
            [
                .text(record.id.uuidString.lowercased()),
                .text(record.conversationID.uuidString.lowercased()),
                .text(record.projectID.uuidString.lowercased()),
                .text(record.title),
                .text(record.searchableText),
                .text(record.commandText),
                .text(record.errorText),
                .text(record.projectPath),
                .real(record.archivedAt.timeIntervalSince1970)
            ]
        )
    }

    public func searchArchiveRecords(query: String) throws -> [ConversationArchiveRecord] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            let rows = try database.query(
                """
                SELECT
                    id,
                    conversation_id,
                    project_id,
                    title,
                    searchable_text,
                    command_text,
                    error_text,
                    project_path,
                    archived_at
                FROM archive_index
                ORDER BY archived_at DESC, id ASC;
                """
            )

            return try rows.map(decodeArchiveRecord)
        }

        let pattern = "%\(escapeLikePattern(trimmedQuery))%"
        let bindings = Array(repeating: SQLiteValue.text(pattern), count: 5)
        let rows = try database.query(
            """
            SELECT
                id,
                conversation_id,
                project_id,
                title,
                searchable_text,
                command_text,
                error_text,
                project_path,
                archived_at
            FROM archive_index
            WHERE title LIKE ? ESCAPE '!'
               OR searchable_text LIKE ? ESCAPE '!'
               OR command_text LIKE ? ESCAPE '!'
               OR error_text LIKE ? ESCAPE '!'
               OR project_path LIKE ? ESCAPE '!'
            ORDER BY archived_at DESC, id ASC;
            """,
            bindings
        )

        return try rows.map(decodeArchiveRecord)
    }

    public func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws {
        try database.execute(
            """
            UPDATE conversations
            SET is_archived = 1,
                archived_at = ?,
                archive_markdown_path = ?
            WHERE id = ?;
            """,
            [
                .real(archivedAt.timeIntervalSince1970),
                .text(archiveMarkdownPath),
                .text(id.uuidString.lowercased())
            ]
        )
    }

    public func archiveConversation(
        record: ConversationArchiveRecord,
        archiveMarkdownPath: String,
        archivedAt: Date
    ) throws {
        try database.execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try database.execute(
                """
                INSERT INTO archive_index (
                    id,
                    conversation_id,
                    project_id,
                    title,
                    searchable_text,
                    command_text,
                    error_text,
                    project_path,
                    archived_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    conversation_id = excluded.conversation_id,
                    project_id = excluded.project_id,
                    title = excluded.title,
                    searchable_text = excluded.searchable_text,
                    command_text = excluded.command_text,
                    error_text = excluded.error_text,
                    project_path = excluded.project_path,
                    archived_at = excluded.archived_at;
                """,
                [
                    .text(record.id.uuidString.lowercased()),
                    .text(record.conversationID.uuidString.lowercased()),
                    .text(record.projectID.uuidString.lowercased()),
                    .text(record.title),
                    .text(record.searchableText),
                    .text(record.commandText),
                    .text(record.errorText),
                    .text(record.projectPath),
                    .real(archivedAt.timeIntervalSince1970)
                ]
            )

            try database.execute(
                """
                UPDATE conversations
                SET is_archived = 1,
                    archived_at = ?,
                    archive_markdown_path = ?
                WHERE id = ?;
                """,
                [
                    .real(archivedAt.timeIntervalSince1970),
                    .text(archiveMarkdownPath),
                    .text(record.conversationID.uuidString.lowercased())
                ]
            )

            try database.execute("COMMIT TRANSACTION;")
        } catch {
            try? database.execute("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    public func saveMemoryCard(_ card: MemoryCard) throws {
        try database.execute(
            """
            INSERT INTO memory_cards (
                id,
                scope,
                type,
                title,
                summary,
                body,
                content_shape,
                status,
                created_at,
                updated_at,
                source_metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                scope = excluded.scope,
                type = excluded.type,
                title = excluded.title,
                summary = excluded.summary,
                body = excluded.body,
                content_shape = excluded.content_shape,
                status = excluded.status,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at,
                source_metadata_json = excluded.source_metadata_json;
            """,
            [
                .text(card.id.uuidString.lowercased()),
                .text(card.scope),
                .text(card.type),
                .text(card.title),
                .text(card.summary),
                .text(card.body),
                .text(card.contentShape),
                .text(card.status),
                .real(card.createdAt.timeIntervalSince1970),
                .real(card.updatedAt.timeIntervalSince1970),
                .text(card.sourceMetadataJSON)
            ]
        )
    }

    public func loadMemoryCards(scope: String?) throws -> [MemoryCard] {
        let rows: [[String: SQLiteValue]]
        if let scope {
            rows = try database.query(
                """
                SELECT id, scope, type, title, summary, body, content_shape, status, created_at, updated_at, source_metadata_json
                FROM memory_cards
                WHERE scope = ?
                ORDER BY updated_at DESC, id ASC;
                """,
                [.text(scope)]
            )
        } else {
            rows = try database.query(
                """
                SELECT id, scope, type, title, summary, body, content_shape, status, created_at, updated_at, source_metadata_json
                FROM memory_cards
                ORDER BY updated_at DESC, id ASC;
                """
            )
        }

        return try rows.map(decodeMemoryCard)
    }

    public func deleteMemoryCard(_ id: UUID) throws {
        try database.execute("DELETE FROM memory_sources WHERE memory_card_id = ?;", [.text(id.uuidString.lowercased())])
        try database.execute("DELETE FROM attachments WHERE owner_kind = ? AND owner_id = ?;", [.text("memory_card"), .text(id.uuidString.lowercased())])
        try database.execute("DELETE FROM memory_cards WHERE id = ?;", [.text(id.uuidString.lowercased())])
    }

    public func saveMemorySource(_ source: MemorySource) throws {
        try database.execute(
            """
            INSERT INTO memory_sources (
                id,
                memory_card_id,
                source_kind,
                source_id,
                source_path,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                memory_card_id = excluded.memory_card_id,
                source_kind = excluded.source_kind,
                source_id = excluded.source_id,
                source_path = excluded.source_path,
                created_at = excluded.created_at;
            """,
            [
                .text(source.id.uuidString.lowercased()),
                .text(source.memoryCardID.uuidString.lowercased()),
                .text(source.sourceKind),
                .text(source.sourceID),
                source.sourcePath.map(SQLiteValue.text) ?? .null,
                .real(source.createdAt.timeIntervalSince1970)
            ]
        )
    }

    public func loadMemorySources(memoryCardID: UUID) throws -> [MemorySource] {
        let rows = try database.query(
            """
            SELECT id, memory_card_id, source_kind, source_id, source_path, created_at
            FROM memory_sources
            WHERE memory_card_id = ?
            ORDER BY created_at ASC, id ASC;
            """,
            [.text(memoryCardID.uuidString.lowercased())]
        )

        return try rows.map(decodeMemorySource)
    }

    public func deleteMemorySource(_ id: UUID) throws {
        try database.execute("DELETE FROM memory_sources WHERE id = ?;", [.text(id.uuidString.lowercased())])
    }

    public func saveAttachment(_ attachment: CodexPlusAttachment) throws {
        try database.execute(
            """
            INSERT INTO attachments (
                id,
                owner_kind,
                owner_id,
                file_path,
                original_file_path,
                content_type,
                byte_count,
                checksum,
                is_snapshot,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                owner_kind = excluded.owner_kind,
                owner_id = excluded.owner_id,
                file_path = excluded.file_path,
                original_file_path = excluded.original_file_path,
                content_type = excluded.content_type,
                byte_count = excluded.byte_count,
                checksum = excluded.checksum,
                is_snapshot = excluded.is_snapshot,
                created_at = excluded.created_at;
            """,
            [
                .text(attachment.id.uuidString.lowercased()),
                .text(attachment.ownerKind),
                .text(attachment.ownerID.uuidString.lowercased()),
                .text(attachment.filePath),
                attachment.originalFilePath.map(SQLiteValue.text) ?? .null,
                .text(attachment.contentType),
                .integer(attachment.byteCount),
                .text(attachment.checksum),
                .integer(boolToInteger(attachment.isSnapshot)),
                .real(attachment.createdAt.timeIntervalSince1970)
            ]
        )
    }

    public func loadAttachments(ownerKind: String, ownerID: UUID?) throws -> [CodexPlusAttachment] {
        let rows: [[String: SQLiteValue]]
        if let ownerID {
            rows = try database.query(
                """
                SELECT id, owner_kind, owner_id, file_path, original_file_path, content_type, byte_count, checksum, is_snapshot, created_at
                FROM attachments
                WHERE owner_kind = ? AND owner_id = ?
                ORDER BY created_at ASC, id ASC;
                """,
                [.text(ownerKind), .text(ownerID.uuidString.lowercased())]
            )
        } else {
            rows = try database.query(
                """
                SELECT id, owner_kind, owner_id, file_path, original_file_path, content_type, byte_count, checksum, is_snapshot, created_at
                FROM attachments
                WHERE owner_kind = ?
                ORDER BY created_at ASC, id ASC;
                """,
                [.text(ownerKind)]
            )
        }

        return try rows.map(decodeAttachment)
    }

    public func deleteAttachment(_ id: UUID) throws {
        try database.execute("DELETE FROM attachments WHERE id = ?;", [.text(id.uuidString.lowercased())])
    }
}

private struct EncodedConversationEvent {
    let id: String
    let ordinal: Int
    let kind: String
    let displayText: String
    let payloadJSON: String
    let rawPayloadJSON: String?
    let createdAt: Date
    let searchableText: String

    init(event: ConversationDisplayEvent, ordinal: Int, fallbackDate: Date) throws {
        self.id = event.id.uuidString.lowercased()
        self.ordinal = ordinal
        self.createdAt = fallbackDate.addingTimeInterval(Double(ordinal) / 1000.0)

        switch event {
        case let .userPrompt(id, text):
            kind = "user_prompt"
            displayText = text
            payloadJSON = try stableJSONString(["id": id.uuidString.lowercased(), "text": text])
            rawPayloadJSON = nil
            searchableText = text
        case let .status(id, text):
            kind = "status"
            displayText = text
            payloadJSON = try stableJSONString(["id": id.uuidString.lowercased(), "text": text])
            rawPayloadJSON = nil
            searchableText = text
        case let .assistantMessage(id, text):
            kind = "assistant_message"
            displayText = text
            payloadJSON = try stableJSONString(["id": id.uuidString.lowercased(), "text": text])
            rawPayloadJSON = nil
            searchableText = text
        case let .command(id, executionID, command, status):
            kind = "command"
            displayText = command
            var payload: [String: Any] = [
                "command": command,
                "id": id.uuidString.lowercased(),
                "status": status.rawValue
            ]
            payload["execution_id"] = executionID ?? NSNull()
            payloadJSON = try stableJSONString(payload)
            rawPayloadJSON = nil
            searchableText = command
        case let .error(id, text):
            kind = "error"
            displayText = text
            payloadJSON = try stableJSONString(["id": id.uuidString.lowercased(), "text": text])
            rawPayloadJSON = nil
            searchableText = text
        case let .parseWarning(id, text):
            kind = "parse_warning"
            displayText = text
            payloadJSON = try stableJSONString(["id": id.uuidString.lowercased(), "text": text])
            rawPayloadJSON = nil
            searchableText = text
        }
    }
}

private struct DecodedConversationEvent {
    let event: ConversationDisplayEvent

    init(row: [String: SQLiteValue]) throws {
        let kind = try text(for: "kind", in: row)
        let payloadObject = try jsonObject(from: try text(for: "payload_json", in: row))

        switch kind {
        case "user_prompt":
            event = .userPrompt(id: try payloadUUID(payloadObject), text: try payloadText(payloadObject))
        case "status":
            event = .status(id: try payloadUUID(payloadObject), text: try payloadText(payloadObject))
        case "assistant_message":
            event = .assistantMessage(id: try payloadUUID(payloadObject), text: try payloadText(payloadObject))
        case "command":
            event = .command(
                id: try payloadUUID(payloadObject),
                executionID: payloadObject["execution_id"] as? String,
                command: try payloadRequiredString(payloadObject, key: "command"),
                status: try payloadCommandStatus(payloadObject)
            )
        case "error":
            event = .error(id: try payloadUUID(payloadObject), text: try payloadText(payloadObject))
        case "parse_warning":
            event = .parseWarning(id: try payloadUUID(payloadObject), text: try payloadText(payloadObject))
        default:
            throw RepositoryError.invalidEventKind(kind)
        }
    }
}

private enum RepositoryError: Error, CustomStringConvertible {
    case missingColumn(String)
    case invalidValue(column: String, value: SQLiteValue)
    case invalidUUID(String)
    case invalidState(String)
    case invalidPermissionMode(String)
    case invalidCommandStatus(String)
    case invalidPayload(String)
    case invalidEventKind(String)

    var description: String {
        switch self {
        case let .missingColumn(name):
            return "Missing column \(name)"
        case let .invalidValue(column, value):
            return "Invalid value for \(column): \(value)"
        case let .invalidUUID(value):
            return "Invalid UUID: \(value)"
        case let .invalidState(value):
            return "Invalid conversation state: \(value)"
        case let .invalidPermissionMode(value):
            return "Invalid permission mode: \(value)"
        case let .invalidCommandStatus(value):
            return "Invalid command status: \(value)"
        case let .invalidPayload(value):
            return "Invalid payload JSON: \(value)"
        case let .invalidEventKind(value):
            return "Invalid event kind: \(value)"
        }
    }
}

private func boolToInteger(_ value: Bool) -> Int64 {
    value ? 1 : 0
}

private func bool(for column: String, in row: [String: SQLiteValue]) throws -> Bool {
    switch try value(for: column, in: row) {
    case let .integer(integer):
        return integer != 0
    default:
        throw RepositoryError.invalidValue(column: column, value: try value(for: column, in: row))
    }
}

private func double(for column: String, in row: [String: SQLiteValue]) throws -> Double {
    switch try value(for: column, in: row) {
    case let .real(real):
        return real
    case let .integer(integer):
        return Double(integer)
    default:
        throw RepositoryError.invalidValue(column: column, value: try value(for: column, in: row))
    }
}

private func text(for column: String, in row: [String: SQLiteValue]) throws -> String {
    switch try value(for: column, in: row) {
    case let .text(text):
        return text
    default:
        throw RepositoryError.invalidValue(column: column, value: try value(for: column, in: row))
    }
}

private func optionalText(for column: String, in row: [String: SQLiteValue]) throws -> String? {
    switch try value(for: column, in: row) {
    case let .text(text):
        return text
    case .null:
        return nil
    default:
        throw RepositoryError.invalidValue(column: column, value: try value(for: column, in: row))
    }
}

private func int64(for column: String, in row: [String: SQLiteValue]) throws -> Int64 {
    switch try value(for: column, in: row) {
    case let .integer(integer):
        return integer
    default:
        throw RepositoryError.invalidValue(column: column, value: try value(for: column, in: row))
    }
}

private func uuid(for column: String, in row: [String: SQLiteValue]) throws -> UUID {
    let string = try text(for: column, in: row)
    guard let uuid = UUID(uuidString: string) else {
        throw RepositoryError.invalidUUID(string)
    }

    return uuid
}

private func uuidString(for column: String, in row: [String: SQLiteValue]) throws -> String {
    try uuid(for: column, in: row).uuidString.lowercased()
}

private func state(for column: String, in row: [String: SQLiteValue]) throws -> ConversationRunState {
    let rawValue = try text(for: column, in: row)
    guard let state = ConversationRunState(rawValue: rawValue) else {
        throw RepositoryError.invalidState(rawValue)
    }

    return state
}

private func permissionMode(for column: String, in row: [String: SQLiteValue]) throws -> PermissionMode {
    let rawValue = try text(for: column, in: row)
    guard let mode = PermissionMode(rawValue: rawValue) else {
        throw RepositoryError.invalidPermissionMode(rawValue)
    }

    return mode
}

private func value(for column: String, in row: [String: SQLiteValue]) throws -> SQLiteValue {
    guard let value = row[column] else {
        throw RepositoryError.missingColumn(column)
    }

    return value
}

private func stableJSONString(_ object: [String: Any]) throws -> String {
    guard JSONSerialization.isValidJSONObject(object) else {
        throw RepositoryError.invalidPayload(String(describing: object))
    }

    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    guard let string = String(data: data, encoding: .utf8) else {
        throw RepositoryError.invalidPayload(String(describing: object))
    }

    return string
}

private func jsonObject(from json: String) throws -> [String: Any] {
    guard let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RepositoryError.invalidPayload(json)
    }

    return object
}

private func payloadUUID(_ object: [String: Any]) throws -> UUID {
    let value = try payloadRequiredString(object, key: "id")
    guard let uuid = UUID(uuidString: value) else {
        throw RepositoryError.invalidUUID(value)
    }

    return uuid
}

private func payloadText(_ object: [String: Any]) throws -> String {
    try payloadRequiredString(object, key: "text")
}

private func payloadRequiredString(_ object: [String: Any], key: String) throws -> String {
    guard let value = object[key] as? String else {
        throw RepositoryError.invalidPayload(String(describing: object))
    }

    return value
}

private func payloadCommandStatus(_ object: [String: Any]) throws -> CodexCommandStatus {
    let rawValue = try payloadRequiredString(object, key: "status")
    guard let status = CodexCommandStatus(rawValue: rawValue) else {
        throw RepositoryError.invalidCommandStatus(rawValue)
    }

    return status
}

private func decodeArchiveRecord(_ row: [String: SQLiteValue]) throws -> ConversationArchiveRecord {
    ConversationArchiveRecord(
        id: try uuid(for: "id", in: row),
        conversationID: try uuid(for: "conversation_id", in: row),
        projectID: try uuid(for: "project_id", in: row),
        title: try text(for: "title", in: row),
        searchableText: try text(for: "searchable_text", in: row),
        commandText: try text(for: "command_text", in: row),
        errorText: try text(for: "error_text", in: row),
        projectPath: try text(for: "project_path", in: row),
        archivedAt: Date(timeIntervalSince1970: try double(for: "archived_at", in: row))
    )
}

private func decodeMemoryCard(_ row: [String: SQLiteValue]) throws -> MemoryCard {
    MemoryCard(
        id: try uuid(for: "id", in: row),
        scope: try text(for: "scope", in: row),
        type: try text(for: "type", in: row),
        title: try text(for: "title", in: row),
        summary: try text(for: "summary", in: row),
        body: try text(for: "body", in: row),
        contentShape: try text(for: "content_shape", in: row),
        status: try text(for: "status", in: row),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row)),
        updatedAt: Date(timeIntervalSince1970: try double(for: "updated_at", in: row)),
        sourceMetadataJSON: try text(for: "source_metadata_json", in: row)
    )
}

private func decodeMemorySource(_ row: [String: SQLiteValue]) throws -> MemorySource {
    MemorySource(
        id: try uuid(for: "id", in: row),
        memoryCardID: try uuid(for: "memory_card_id", in: row),
        sourceKind: try text(for: "source_kind", in: row),
        sourceID: try text(for: "source_id", in: row),
        sourcePath: try optionalText(for: "source_path", in: row),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row))
    )
}

private func decodeAttachment(_ row: [String: SQLiteValue]) throws -> CodexPlusAttachment {
    CodexPlusAttachment(
        id: try uuid(for: "id", in: row),
        ownerKind: try text(for: "owner_kind", in: row),
        ownerID: try uuid(for: "owner_id", in: row),
        filePath: try text(for: "file_path", in: row),
        originalFilePath: try optionalText(for: "original_file_path", in: row),
        contentType: try text(for: "content_type", in: row),
        byteCount: try int64(for: "byte_count", in: row),
        checksum: try text(for: "checksum", in: row),
        isSnapshot: try bool(for: "is_snapshot", in: row),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row))
    )
}

private func escapeLikePattern(_ value: String) -> String {
    value
        .replacingOccurrences(of: "!", with: "!!")
        .replacingOccurrences(of: "%", with: "!%")
        .replacingOccurrences(of: "_", with: "!_")
}
