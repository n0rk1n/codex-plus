import Foundation

public protocol CodexPlusRepository: ProjectRepository, ConversationRepository, ArchiveRepository, MemoryRepository, AttachmentRepository, PromptTemplateRepository, ContextCompressionRepository, Sendable {}

public extension CodexPlusRepository {
    func deleteArchivedConversation(_ id: UUID) throws -> String? {
        throw UnsupportedRepositoryOperation()
    }

    func restoreArchivedConversation(_ id: UUID) throws -> String? {
        throw UnsupportedRepositoryOperation()
    }

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

    func savePromptTemplate(_ template: PromptTemplate) throws {
        throw UnsupportedRepositoryOperation()
    }

    func loadPromptTemplates() throws -> [PromptTemplate] {
        throw UnsupportedRepositoryOperation()
    }

    func deletePromptTemplate(_ id: UUID) throws {
        throw UnsupportedRepositoryOperation()
    }

    func setDefaultPromptTemplateID(_ id: UUID, for type: PromptTemplateType) throws {
        throw UnsupportedRepositoryOperation()
    }

    func loadDefaultPromptTemplateIDs() throws -> [PromptTemplateType: UUID] {
        throw UnsupportedRepositoryOperation()
    }

    func loadCompressionState(conversationID: UUID) throws -> ConversationCompressionState {
        throw UnsupportedRepositoryOperation()
    }

    func replaceCompressionRounds(
        _ rounds: [CompressionRound],
        events: [CompressionRoundEvent],
        conversationID: UUID
    ) throws {
        throw UnsupportedRepositoryOperation()
    }

    func saveCompressionVersion(_ version: CompressionVersion) throws {
        throw UnsupportedRepositoryOperation()
    }

    func saveCompressionVersionSources(_ sources: [CompressionVersionSource]) throws {
        throw UnsupportedRepositoryOperation()
    }

    func saveCompressionLineageEdges(_ edges: [CompressionLineageEdge]) throws {
        throw UnsupportedRepositoryOperation()
    }

    func saveCompressionInput(_ input: CompressionInputRecord) throws {
        throw UnsupportedRepositoryOperation()
    }

    func saveCompressionTombstones(_ tombstones: [CompressionTombstone]) throws {
        throw UnsupportedRepositoryOperation()
    }

    func setActiveCompressionVersion(_ active: CompressionActiveVersion) throws {
        throw UnsupportedRepositoryOperation()
    }

    func clearActiveCompressionVersion(conversationID: UUID, roundID: UUID?, rangeID: UUID?) throws {
        throw UnsupportedRepositoryOperation()
    }
}

private struct UnsupportedRepositoryOperation: Error {}

private enum PromptTemplatePersistenceError: Error {
    case builtInTemplatesAreReadOnly
    case invalidPromptTemplateType(String)
}

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
        try database.execute("PRAGMA defer_foreign_keys = ON;")

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
                let record = try ConversationEventCodec.encode(
                    event,
                    ordinal: ordinal,
                    fallbackDate: conversation.createdAt
                )
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

            try syncCompressionRounds(for: conversation)

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
            let events = try (eventRowsByConversationID[conversationKey] ?? []).map { eventRow in
                try ConversationEventCodec.decode(
                    kind: try text(for: "kind", in: eventRow),
                    payloadJSON: try text(for: "payload_json", in: eventRow)
                )
            }

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

    public func deleteArchivedConversation(_ id: UUID) throws -> String? {
        let conversationID = id.uuidString.lowercased()
        var archiveMarkdownPath: String?

        try database.execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            let rows = try database.query(
                """
                SELECT archive_markdown_path
                FROM conversations
                WHERE id = ?
                  AND is_archived = 1
                LIMIT 1;
                """,
                [.text(conversationID)]
            )

            guard let row = rows.first else {
                try database.execute("COMMIT TRANSACTION;")
                return nil
            }

            if case let .text(path)? = row["archive_markdown_path"], !path.isEmpty {
                archiveMarkdownPath = path
            }

            try database.execute(
                """
                DELETE FROM archive_index
                WHERE id = ?
                   OR conversation_id = ?;
                """,
                [.text(conversationID), .text(conversationID)]
            )
            try database.execute(
                """
                DELETE FROM conversation_events
                WHERE conversation_id = ?;
                """,
                [.text(conversationID)]
            )
            try database.execute(
                """
                DELETE FROM conversations
                WHERE id = ?
                  AND is_archived = 1;
                """,
                [.text(conversationID)]
            )

            try database.execute("COMMIT TRANSACTION;")
        } catch {
            try? database.execute("ROLLBACK TRANSACTION;")
            throw error
        }

        return archiveMarkdownPath
    }

    public func restoreArchivedConversation(_ id: UUID) throws -> String? {
        let conversationID = id.uuidString.lowercased()
        var archiveMarkdownPath: String?

        try database.execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            let rows = try database.query(
                """
                SELECT archive_markdown_path
                FROM conversations
                WHERE id = ?
                  AND is_archived = 1
                LIMIT 1;
                """,
                [.text(conversationID)]
            )

            guard let row = rows.first else {
                try database.execute("COMMIT TRANSACTION;")
                return nil
            }

            if case let .text(path)? = row["archive_markdown_path"], !path.isEmpty {
                archiveMarkdownPath = path
            }

            try database.execute(
                """
                DELETE FROM archive_index
                WHERE id = ?
                   OR conversation_id = ?;
                """,
                [.text(conversationID), .text(conversationID)]
            )
            try database.execute(
                """
                UPDATE conversations
                SET is_archived = 0,
                    archived_at = NULL,
                    archive_markdown_path = NULL
                WHERE id = ?
                  AND is_archived = 1;
                """,
                [.text(conversationID)]
            )

            try database.execute("COMMIT TRANSACTION;")
        } catch {
            try? database.execute("ROLLBACK TRANSACTION;")
            throw error
        }

        return archiveMarkdownPath
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

    public func savePromptTemplate(_ template: PromptTemplate) throws {
        guard template.source == .userCustom else {
            throw PromptTemplatePersistenceError.builtInTemplatesAreReadOnly
        }

        try database.execute(
            """
            INSERT INTO prompt_templates (
                id,
                type,
                name,
                system_prompt,
                user_prompt,
                note,
                created_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type = excluded.type,
                name = excluded.name,
                system_prompt = excluded.system_prompt,
                user_prompt = excluded.user_prompt,
                note = excluded.note,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at;
            """,
            [
                .text(template.id.uuidString.lowercased()),
                .text(template.type.rawValue),
                .text(template.name),
                .text(template.systemPrompt),
                .text(template.userPrompt),
                .text(template.note),
                .real(template.createdAt.timeIntervalSince1970),
                .real(template.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    public func loadPromptTemplates() throws -> [PromptTemplate] {
        let rows = try database.query(
            """
            SELECT id, type, name, system_prompt, user_prompt, note, created_at, updated_at
            FROM prompt_templates
            ORDER BY updated_at DESC, id ASC;
            """
        )

        return try rows.map(decodePromptTemplate)
    }

    public func deletePromptTemplate(_ id: UUID) throws {
        try database.execute(
            "DELETE FROM prompt_templates WHERE id = ?;",
            [.text(id.uuidString.lowercased())]
        )
    }

    public func setDefaultPromptTemplateID(_ id: UUID, for type: PromptTemplateType) throws {
        try database.execute(
            """
            INSERT INTO prompt_template_defaults (type, template_id)
            VALUES (?, ?)
            ON CONFLICT(type) DO UPDATE SET
                template_id = excluded.template_id;
            """,
            [
                .text(type.rawValue),
                .text(id.uuidString.lowercased())
            ]
        )
    }

    public func loadDefaultPromptTemplateIDs() throws -> [PromptTemplateType: UUID] {
        let rows = try database.query(
            """
            SELECT type, template_id
            FROM prompt_template_defaults
            ORDER BY type ASC;
            """
        )

        var defaults: [PromptTemplateType: UUID] = [:]
        for row in rows {
            let rawType = try text(for: "type", in: row)
            guard let type = PromptTemplateType(rawValue: rawType) else {
                throw PromptTemplatePersistenceError.invalidPromptTemplateType(rawType)
            }

            defaults[type] = try uuid(for: "template_id", in: row)
        }

        return defaults
    }

    public func loadCompressionState(conversationID: UUID) throws -> ConversationCompressionState {
        let conversationIDText = conversationID.uuidString.lowercased()
        let rounds = try database.query(
            """
            SELECT id, conversation_id, round_index, user_event_id, first_assistant_event_id, last_assistant_event_id,
                   run_state, run_started_at, run_finished_at, created_at, updated_at
            FROM compression_rounds
            WHERE conversation_id = ?
            ORDER BY round_index ASC, id ASC;
            """,
            [.text(conversationIDText)]
        ).map(decodeCompressionRound)
        let roundIDs = Set(rounds.map(\.id.uuidString).map { $0.lowercased() })
        let roundEvents = try database.query(
            """
            SELECT re.id, re.round_id, re.event_id, re.segment_kind, re.ordinal
            FROM compression_round_events re
            INNER JOIN compression_rounds r ON r.id = re.round_id
            WHERE r.conversation_id = ?
            ORDER BY r.round_index ASC, re.ordinal ASC, re.id ASC;
            """,
            [.text(conversationIDText)]
        ).map(decodeCompressionRoundEvent)
        let inputs = try database.query(
            """
            SELECT id, conversation_id, mode, template_id, user_instruction, input_snapshot,
                   provider_name, provider_model, created_at
            FROM compression_inputs
            WHERE conversation_id = ?
            ORDER BY created_at ASC, id ASC;
            """,
            [.text(conversationIDText)]
        ).map(decodeCompressionInput)
        let versions = try database.query(
            """
            SELECT id, conversation_id, scope_kind, operation, status, content, template_id,
                   compression_input_id, error_message, created_at, updated_at
            FROM compression_versions
            WHERE conversation_id = ?
            ORDER BY created_at ASC, id ASC;
            """,
            [.text(conversationIDText)]
        ).map(decodeCompressionVersion)
        let versionIDs = Set(versions.map(\.id.uuidString).map { $0.lowercased() })
        let versionSources = try database.query(
            """
            SELECT vs.id, vs.version_id, vs.source_kind, vs.source_id, vs.ordinal
            FROM compression_version_sources vs
            INNER JOIN compression_versions v ON v.id = vs.version_id
            WHERE v.conversation_id = ?
            ORDER BY v.created_at ASC, vs.ordinal ASC, vs.id ASC;
            """,
            [.text(conversationIDText)]
        ).map(decodeCompressionVersionSource)
        let lineageEdges = try database.query(
            """
            SELECT e.id, e.parent_version_id, e.child_version_id, e.edge_kind, e.created_at
            FROM compression_lineage_edges e
            INNER JOIN compression_versions v ON v.id = e.child_version_id
            WHERE v.conversation_id = ?
            ORDER BY e.created_at ASC, e.id ASC;
            """,
            [.text(conversationIDText)]
        ).map(decodeCompressionLineageEdge)
        let activeVersions = try database.query(
            """
            SELECT id, conversation_id, round_id, range_id, active_version_id
            FROM compression_active_versions
            WHERE conversation_id = ?
            ORDER BY id ASC;
            """,
            [.text(conversationIDText)]
        ).map(decodeCompressionActiveVersion)
        let tombstones = try database.query(
            """
            SELECT t.id, t.version_id, t.reason, t.replaced_by_version_id, t.created_at
            FROM compression_tombstones t
            INNER JOIN compression_versions v ON v.id = t.version_id
            WHERE v.conversation_id = ?
            ORDER BY t.created_at ASC, t.id ASC;
            """,
            [.text(conversationIDText)]
        ).map(decodeCompressionTombstone)

        return ConversationCompressionState(
            rounds: rounds,
            roundEvents: roundEvents.filter { roundIDs.contains($0.roundID.uuidString.lowercased()) },
            versions: versions,
            versionSources: versionSources.filter { versionIDs.contains($0.versionID.uuidString.lowercased()) },
            lineageEdges: lineageEdges,
            activeVersions: activeVersions,
            inputs: inputs,
            tombstones: tombstones
        )
    }

    public func replaceCompressionRounds(
        _ rounds: [CompressionRound],
        events: [CompressionRoundEvent],
        conversationID: UUID
    ) throws {
        let conversationIDText = conversationID.uuidString.lowercased()
        try database.execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try database.execute(
                """
                DELETE FROM compression_round_events
                WHERE round_id IN (
                    SELECT id FROM compression_rounds WHERE conversation_id = ?
                );
                """,
                [.text(conversationIDText)]
            )
            try database.execute(
                "DELETE FROM compression_rounds WHERE conversation_id = ?;",
                [.text(conversationIDText)]
            )

            for round in rounds {
                try saveCompressionRound(round)
            }

            for event in events {
                try saveCompressionRoundEvent(event)
            }

            try database.execute("COMMIT TRANSACTION;")
        } catch {
            try? database.execute("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    public func saveCompressionVersion(_ version: CompressionVersion) throws {
        try database.execute(
            """
            INSERT INTO compression_versions (
                id,
                conversation_id,
                scope_kind,
                operation,
                status,
                content,
                template_id,
                compression_input_id,
                error_message,
                created_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                conversation_id = excluded.conversation_id,
                scope_kind = excluded.scope_kind,
                operation = excluded.operation,
                status = excluded.status,
                content = excluded.content,
                template_id = excluded.template_id,
                compression_input_id = excluded.compression_input_id,
                error_message = excluded.error_message,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at;
            """,
            [
                .text(version.id.uuidString.lowercased()),
                .text(version.conversationID.uuidString.lowercased()),
                .text(version.scopeKind.rawValue),
                .text(version.operation.rawValue),
                .text(version.status.rawValue),
                .text(version.content),
                version.templateID.map { .text($0.uuidString.lowercased()) } ?? .null,
                version.compressionInputID.map { .text($0.uuidString.lowercased()) } ?? .null,
                version.errorMessage.map(SQLiteValue.text) ?? .null,
                .real(version.createdAt.timeIntervalSince1970),
                .real(version.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    public func saveCompressionVersionSources(_ sources: [CompressionVersionSource]) throws {
        for source in sources {
            try database.execute(
                """
                INSERT INTO compression_version_sources (id, version_id, source_kind, source_id, ordinal)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    version_id = excluded.version_id,
                    source_kind = excluded.source_kind,
                    source_id = excluded.source_id,
                    ordinal = excluded.ordinal;
                """,
                [
                    .text(source.id.uuidString.lowercased()),
                    .text(source.versionID.uuidString.lowercased()),
                    .text(source.sourceKind.rawValue),
                    .text(source.sourceID.uuidString.lowercased()),
                    .integer(Int64(source.ordinal))
                ]
            )
        }
    }

    public func saveCompressionLineageEdges(_ edges: [CompressionLineageEdge]) throws {
        for edge in edges {
            try database.execute(
                """
                INSERT INTO compression_lineage_edges (id, parent_version_id, child_version_id, edge_kind, created_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    parent_version_id = excluded.parent_version_id,
                    child_version_id = excluded.child_version_id,
                    edge_kind = excluded.edge_kind,
                    created_at = excluded.created_at;
                """,
                [
                    .text(edge.id.uuidString.lowercased()),
                    .text(edge.parentVersionID.uuidString.lowercased()),
                    .text(edge.childVersionID.uuidString.lowercased()),
                    .text(edge.edgeKind.rawValue),
                    .real(edge.createdAt.timeIntervalSince1970)
                ]
            )
        }
    }

    public func saveCompressionInput(_ input: CompressionInputRecord) throws {
        try database.execute(
            """
            INSERT INTO compression_inputs (
                id,
                conversation_id,
                mode,
                template_id,
                user_instruction,
                input_snapshot,
                provider_name,
                provider_model,
                created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                conversation_id = excluded.conversation_id,
                mode = excluded.mode,
                template_id = excluded.template_id,
                user_instruction = excluded.user_instruction,
                input_snapshot = excluded.input_snapshot,
                provider_name = excluded.provider_name,
                provider_model = excluded.provider_model,
                created_at = excluded.created_at;
            """,
            [
                .text(input.id.uuidString.lowercased()),
                .text(input.conversationID.uuidString.lowercased()),
                .text(input.mode.rawValue),
                input.templateID.map { .text($0.uuidString.lowercased()) } ?? .null,
                .text(input.userInstruction),
                .text(input.inputSnapshot),
                .text(input.providerName),
                .text(input.providerModel),
                .real(input.createdAt.timeIntervalSince1970)
            ]
        )
    }

    public func saveCompressionTombstones(_ tombstones: [CompressionTombstone]) throws {
        for tombstone in tombstones {
            try database.execute(
                """
                INSERT INTO compression_tombstones (id, version_id, reason, replaced_by_version_id, created_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    version_id = excluded.version_id,
                    reason = excluded.reason,
                    replaced_by_version_id = excluded.replaced_by_version_id,
                    created_at = excluded.created_at;
                """,
                [
                    .text(tombstone.id.uuidString.lowercased()),
                    .text(tombstone.versionID.uuidString.lowercased()),
                    .text(tombstone.reason),
                    tombstone.replacedByVersionID.map { .text($0.uuidString.lowercased()) } ?? .null,
                    .real(tombstone.createdAt.timeIntervalSince1970)
                ]
            )
        }
    }

    public func setActiveCompressionVersion(_ active: CompressionActiveVersion) throws {
        try database.execute("BEGIN IMMEDIATE TRANSACTION;")

        do {
            try clearActiveCompressionVersion(
                conversationID: active.conversationID,
                roundID: active.roundID,
                rangeID: active.rangeID
            )
            try database.execute(
                """
                INSERT INTO compression_active_versions (id, conversation_id, round_id, range_id, active_version_id)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    conversation_id = excluded.conversation_id,
                    round_id = excluded.round_id,
                    range_id = excluded.range_id,
                    active_version_id = excluded.active_version_id;
                """,
                [
                    .text(active.id.uuidString.lowercased()),
                    .text(active.conversationID.uuidString.lowercased()),
                    active.roundID.map { .text($0.uuidString.lowercased()) } ?? .null,
                    active.rangeID.map { .text($0.uuidString.lowercased()) } ?? .null,
                    .text(active.activeVersionID.uuidString.lowercased())
                ]
            )
            try database.execute("COMMIT TRANSACTION;")
        } catch {
            try? database.execute("ROLLBACK TRANSACTION;")
            throw error
        }
    }

    public func clearActiveCompressionVersion(conversationID: UUID, roundID: UUID?, rangeID: UUID?) throws {
        if let roundID {
            try database.execute(
                "DELETE FROM compression_active_versions WHERE conversation_id = ? AND round_id = ?;",
                [
                    .text(conversationID.uuidString.lowercased()),
                    .text(roundID.uuidString.lowercased())
                ]
            )
            return
        }

        if let rangeID {
            try database.execute(
                "DELETE FROM compression_active_versions WHERE conversation_id = ? AND range_id = ?;",
                [
                    .text(conversationID.uuidString.lowercased()),
                    .text(rangeID.uuidString.lowercased())
                ]
            )
            return
        }

        try database.execute(
            "DELETE FROM compression_active_versions WHERE conversation_id = ?;",
            [.text(conversationID.uuidString.lowercased())]
        )
    }

    private func saveCompressionRound(_ round: CompressionRound) throws {
        try database.execute(
            """
            INSERT INTO compression_rounds (
                id,
                conversation_id,
                round_index,
                user_event_id,
                first_assistant_event_id,
                last_assistant_event_id,
                run_state,
                run_started_at,
                run_finished_at,
                created_at,
                updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                conversation_id = excluded.conversation_id,
                round_index = excluded.round_index,
                user_event_id = excluded.user_event_id,
                first_assistant_event_id = excluded.first_assistant_event_id,
                last_assistant_event_id = excluded.last_assistant_event_id,
                run_state = excluded.run_state,
                run_started_at = excluded.run_started_at,
                run_finished_at = excluded.run_finished_at,
                created_at = excluded.created_at,
                updated_at = excluded.updated_at;
            """,
            [
                .text(round.id.uuidString.lowercased()),
                .text(round.conversationID.uuidString.lowercased()),
                .integer(Int64(round.roundIndex)),
                .text(round.userEventID.uuidString.lowercased()),
                round.firstAssistantEventID.map { .text($0.uuidString.lowercased()) } ?? .null,
                round.lastAssistantEventID.map { .text($0.uuidString.lowercased()) } ?? .null,
                .text(round.runState),
                round.runStartedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                round.runFinishedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                .real(round.createdAt.timeIntervalSince1970),
                .real(round.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    private func syncCompressionRounds(for conversation: ConversationSession) throws {
        let result = ConversationRoundBuilder.buildRounds(
            conversation: conversation,
            now: conversation.lastActivityAt
        )

        for round in result.rounds {
            try database.execute(
                "DELETE FROM compression_round_events WHERE round_id = ?;",
                [.text(round.id.uuidString.lowercased())]
            )
            try saveCompressionRound(round)
        }

        for event in result.events {
            try saveCompressionRoundEvent(event)
        }
    }

    private func saveCompressionRoundEvent(_ event: CompressionRoundEvent) throws {
        try database.execute(
            """
            INSERT INTO compression_round_events (id, round_id, event_id, segment_kind, ordinal)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                round_id = excluded.round_id,
                event_id = excluded.event_id,
                segment_kind = excluded.segment_kind,
                ordinal = excluded.ordinal;
            """,
            [
                .text(event.id.uuidString.lowercased()),
                .text(event.roundID.uuidString.lowercased()),
                .text(event.eventID.uuidString.lowercased()),
                .text(event.segmentKind.rawValue),
                .integer(Int64(event.ordinal))
            ]
        )
    }
}

private enum RepositoryError: Error, CustomStringConvertible {
    case missingColumn(String)
    case invalidValue(column: String, value: SQLiteValue)
    case invalidUUID(String)
    case invalidState(String)
    case invalidPermissionMode(String)

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

private func optionalDouble(for column: String, in row: [String: SQLiteValue]) throws -> Double? {
    switch try value(for: column, in: row) {
    case let .real(real):
        return real
    case let .integer(integer):
        return Double(integer)
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

private func optionalUUID(for column: String, in row: [String: SQLiteValue]) throws -> UUID? {
    guard let string = try optionalText(for: column, in: row) else {
        return nil
    }

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

private func decodePromptTemplate(_ row: [String: SQLiteValue]) throws -> PromptTemplate {
    let rawType = try text(for: "type", in: row)
    guard let type = PromptTemplateType(rawValue: rawType) else {
        throw PromptTemplatePersistenceError.invalidPromptTemplateType(rawType)
    }

    return PromptTemplate(
        id: try uuid(for: "id", in: row),
        source: .userCustom,
        type: type,
        name: try text(for: "name", in: row),
        systemPrompt: try text(for: "system_prompt", in: row),
        userPrompt: try text(for: "user_prompt", in: row),
        note: try text(for: "note", in: row),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row)),
        updatedAt: Date(timeIntervalSince1970: try double(for: "updated_at", in: row))
    )
}

private func decodeCompressionRound(_ row: [String: SQLiteValue]) throws -> CompressionRound {
    CompressionRound(
        id: try uuid(for: "id", in: row),
        conversationID: try uuid(for: "conversation_id", in: row),
        roundIndex: Int(try int64(for: "round_index", in: row)),
        userEventID: try uuid(for: "user_event_id", in: row),
        firstAssistantEventID: try optionalUUID(for: "first_assistant_event_id", in: row),
        lastAssistantEventID: try optionalUUID(for: "last_assistant_event_id", in: row),
        runState: try text(for: "run_state", in: row),
        runStartedAt: try optionalDouble(for: "run_started_at", in: row).map(Date.init(timeIntervalSince1970:)),
        runFinishedAt: try optionalDouble(for: "run_finished_at", in: row).map(Date.init(timeIntervalSince1970:)),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row)),
        updatedAt: Date(timeIntervalSince1970: try double(for: "updated_at", in: row))
    )
}

private func decodeCompressionRoundEvent(_ row: [String: SQLiteValue]) throws -> CompressionRoundEvent {
    let rawSegmentKind = try text(for: "segment_kind", in: row)
    guard let segmentKind = CompressionSegmentKind(rawValue: rawSegmentKind) else {
        throw RepositoryError.invalidValue(column: "segment_kind", value: .text(rawSegmentKind))
    }

    return CompressionRoundEvent(
        id: try uuid(for: "id", in: row),
        roundID: try uuid(for: "round_id", in: row),
        eventID: try uuid(for: "event_id", in: row),
        segmentKind: segmentKind,
        ordinal: Int(try int64(for: "ordinal", in: row))
    )
}

private func decodeCompressionVersion(_ row: [String: SQLiteValue]) throws -> CompressionVersion {
    let rawScopeKind = try text(for: "scope_kind", in: row)
    guard let scopeKind = CompressionVersionScopeKind(rawValue: rawScopeKind) else {
        throw RepositoryError.invalidValue(column: "scope_kind", value: .text(rawScopeKind))
    }

    let rawOperation = try text(for: "operation", in: row)
    guard let operation = CompressionVersionOperation(rawValue: rawOperation) else {
        throw RepositoryError.invalidValue(column: "operation", value: .text(rawOperation))
    }

    let rawStatus = try text(for: "status", in: row)
    guard let status = CompressionVersionStatus(rawValue: rawStatus) else {
        throw RepositoryError.invalidValue(column: "status", value: .text(rawStatus))
    }

    return CompressionVersion(
        id: try uuid(for: "id", in: row),
        conversationID: try uuid(for: "conversation_id", in: row),
        scopeKind: scopeKind,
        operation: operation,
        status: status,
        content: try text(for: "content", in: row),
        templateID: try optionalUUID(for: "template_id", in: row),
        compressionInputID: try optionalUUID(for: "compression_input_id", in: row),
        errorMessage: try optionalText(for: "error_message", in: row),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row)),
        updatedAt: Date(timeIntervalSince1970: try double(for: "updated_at", in: row))
    )
}

private func decodeCompressionVersionSource(_ row: [String: SQLiteValue]) throws -> CompressionVersionSource {
    let rawSourceKind = try text(for: "source_kind", in: row)
    guard let sourceKind = CompressionVersionSourceKind(rawValue: rawSourceKind) else {
        throw RepositoryError.invalidValue(column: "source_kind", value: .text(rawSourceKind))
    }

    return CompressionVersionSource(
        id: try uuid(for: "id", in: row),
        versionID: try uuid(for: "version_id", in: row),
        sourceKind: sourceKind,
        sourceID: try uuid(for: "source_id", in: row),
        ordinal: Int(try int64(for: "ordinal", in: row))
    )
}

private func decodeCompressionLineageEdge(_ row: [String: SQLiteValue]) throws -> CompressionLineageEdge {
    let rawEdgeKind = try text(for: "edge_kind", in: row)
    guard let edgeKind = CompressionLineageEdgeKind(rawValue: rawEdgeKind) else {
        throw RepositoryError.invalidValue(column: "edge_kind", value: .text(rawEdgeKind))
    }

    return CompressionLineageEdge(
        id: try uuid(for: "id", in: row),
        parentVersionID: try uuid(for: "parent_version_id", in: row),
        childVersionID: try uuid(for: "child_version_id", in: row),
        edgeKind: edgeKind,
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row))
    )
}

private func decodeCompressionActiveVersion(_ row: [String: SQLiteValue]) throws -> CompressionActiveVersion {
    CompressionActiveVersion(
        id: try uuid(for: "id", in: row),
        conversationID: try uuid(for: "conversation_id", in: row),
        roundID: try optionalUUID(for: "round_id", in: row),
        rangeID: try optionalUUID(for: "range_id", in: row),
        activeVersionID: try uuid(for: "active_version_id", in: row)
    )
}

private func decodeCompressionInput(_ row: [String: SQLiteValue]) throws -> CompressionInputRecord {
    let rawMode = try text(for: "mode", in: row)
    guard let mode = CompressionInputMode(rawValue: rawMode) else {
        throw RepositoryError.invalidValue(column: "mode", value: .text(rawMode))
    }

    return CompressionInputRecord(
        id: try uuid(for: "id", in: row),
        conversationID: try uuid(for: "conversation_id", in: row),
        mode: mode,
        templateID: try optionalUUID(for: "template_id", in: row),
        userInstruction: try text(for: "user_instruction", in: row),
        inputSnapshot: try text(for: "input_snapshot", in: row),
        providerName: try text(for: "provider_name", in: row),
        providerModel: try text(for: "provider_model", in: row),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row))
    )
}

private func decodeCompressionTombstone(_ row: [String: SQLiteValue]) throws -> CompressionTombstone {
    CompressionTombstone(
        id: try uuid(for: "id", in: row),
        versionID: try uuid(for: "version_id", in: row),
        reason: try text(for: "reason", in: row),
        replacedByVersionID: try optionalUUID(for: "replaced_by_version_id", in: row),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row))
    )
}

private func escapeLikePattern(_ value: String) -> String {
    value
        .replacingOccurrences(of: "!", with: "!!")
        .replacingOccurrences(of: "%", with: "!%")
        .replacingOccurrences(of: "_", with: "!_")
}
