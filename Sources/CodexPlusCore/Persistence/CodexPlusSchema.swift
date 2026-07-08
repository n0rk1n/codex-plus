import Foundation

public enum CodexPlusSchema {
    public static let version = 4

    public static func migrate(_ database: SQLiteDatabase) throws {
        let currentVersion = try userVersion(database)
        guard currentVersion <= version else {
            throw CodexPlusSchemaError.unsupportedFutureVersion(currentVersion)
        }

        try database.execute("""
        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            last_activity_at REAL NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            prompt TEXT NOT NULL,
            workspace_path TEXT NOT NULL,
            state TEXT NOT NULL,
            permission_mode TEXT NOT NULL,
            is_pinned INTEGER NOT NULL,
            is_explicitly_kept INTEGER NOT NULL,
            is_archived INTEGER NOT NULL,
            created_at REAL NOT NULL,
            last_activity_at REAL NOT NULL,
            archived_at REAL,
            archive_markdown_path TEXT,
            FOREIGN KEY(project_id) REFERENCES projects(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS conversation_events (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            kind TEXT NOT NULL,
            display_text TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            raw_payload_json TEXT,
            created_at REAL NOT NULL,
            searchable_text TEXT NOT NULL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS archive_index (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            searchable_text TEXT NOT NULL,
            command_text TEXT NOT NULL,
            error_text TEXT NOT NULL,
            project_path TEXT NOT NULL,
            archived_at REAL NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS memory_cards (
            id TEXT PRIMARY KEY,
            scope TEXT NOT NULL,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            body TEXT NOT NULL,
            content_shape TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            source_metadata_json TEXT NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS memory_sources (
            id TEXT PRIMARY KEY,
            memory_card_id TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            source_id TEXT NOT NULL,
            source_path TEXT,
            created_at REAL NOT NULL,
            FOREIGN KEY(memory_card_id) REFERENCES memory_cards(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS attachments (
            id TEXT PRIMARY KEY,
            owner_kind TEXT NOT NULL,
            owner_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            original_file_path TEXT,
            content_type TEXT NOT NULL,
            byte_count INTEGER NOT NULL,
            checksum TEXT NOT NULL,
            is_snapshot INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS prompt_templates (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            name TEXT NOT NULL,
            system_prompt TEXT NOT NULL,
            user_prompt TEXT NOT NULL,
            note TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS prompt_template_defaults (
            type TEXT PRIMARY KEY,
            template_id TEXT NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS compression_rounds (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            round_index INTEGER NOT NULL CHECK (round_index >= 0),
            user_event_id TEXT NOT NULL,
            first_assistant_event_id TEXT,
            last_assistant_event_id TEXT,
            run_state TEXT NOT NULL,
            run_started_at REAL,
            run_finished_at REAL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(conversation_id, round_index),
            FOREIGN KEY(conversation_id) REFERENCES conversations(id),
            FOREIGN KEY(user_event_id) REFERENCES conversation_events(id),
            FOREIGN KEY(first_assistant_event_id) REFERENCES conversation_events(id),
            FOREIGN KEY(last_assistant_event_id) REFERENCES conversation_events(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS compression_round_events (
            id TEXT PRIMARY KEY,
            round_id TEXT NOT NULL,
            event_id TEXT NOT NULL,
            segment_kind TEXT NOT NULL CHECK (segment_kind IN ('user', 'assistant')),
            ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
            UNIQUE(round_id, event_id),
            FOREIGN KEY(round_id) REFERENCES compression_rounds(id),
            FOREIGN KEY(event_id) REFERENCES conversation_events(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS compression_inputs (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            mode TEXT NOT NULL CHECK (mode IN ('default_template', 'custom_template', 'system')),
            template_id TEXT,
            user_instruction TEXT NOT NULL,
            input_snapshot TEXT NOT NULL,
            provider_name TEXT NOT NULL,
            provider_model TEXT NOT NULL,
            created_at REAL NOT NULL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id),
            FOREIGN KEY(template_id) REFERENCES prompt_templates(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS compression_versions (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            scope_kind TEXT NOT NULL CHECK (scope_kind IN ('round', 'range', 'assembled')),
            operation TEXT NOT NULL CHECK (operation IN (
                'original',
                'manual_edit',
                'default_compression',
                'custom_compression',
                'system_compression',
                'exclude',
                'failed_compression',
                'tombstone'
            )),
            status TEXT NOT NULL CHECK (status IN ('active', 'historical', 'failed', 'tombstoned')),
            content TEXT NOT NULL,
            template_id TEXT,
            compression_input_id TEXT,
            error_message TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id),
            FOREIGN KEY(template_id) REFERENCES prompt_templates(id),
            FOREIGN KEY(compression_input_id) REFERENCES compression_inputs(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS compression_version_sources (
            id TEXT PRIMARY KEY,
            version_id TEXT NOT NULL,
            source_kind TEXT NOT NULL CHECK (source_kind IN ('round', 'version', 'range')),
            source_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
            UNIQUE(version_id, source_kind, source_id),
            FOREIGN KEY(version_id) REFERENCES compression_versions(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS compression_lineage_edges (
            id TEXT PRIMARY KEY,
            parent_version_id TEXT NOT NULL,
            child_version_id TEXT NOT NULL,
            edge_kind TEXT NOT NULL CHECK (edge_kind IN (
                'edit',
                'compress',
                'join',
                'exclude',
                'rollback',
                'system_compress'
            )),
            created_at REAL NOT NULL,
            UNIQUE(parent_version_id, child_version_id, edge_kind),
            FOREIGN KEY(parent_version_id) REFERENCES compression_versions(id),
            FOREIGN KEY(child_version_id) REFERENCES compression_versions(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS compression_active_versions (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            round_id TEXT,
            range_id TEXT,
            active_version_id TEXT NOT NULL,
            UNIQUE(conversation_id, round_id),
            UNIQUE(conversation_id, range_id),
            FOREIGN KEY(conversation_id) REFERENCES conversations(id),
            FOREIGN KEY(round_id) REFERENCES compression_rounds(id),
            FOREIGN KEY(active_version_id) REFERENCES compression_versions(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS compression_tombstones (
            id TEXT PRIMARY KEY,
            version_id TEXT NOT NULL,
            reason TEXT NOT NULL,
            replaced_by_version_id TEXT,
            created_at REAL NOT NULL,
            FOREIGN KEY(version_id) REFERENCES compression_versions(id),
            FOREIGN KEY(replaced_by_version_id) REFERENCES compression_versions(id)
        );
        """)
        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_compression_rounds_conversation
        ON compression_rounds(conversation_id, round_index);
        """)
        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_compression_round_events_round
        ON compression_round_events(round_id, ordinal);
        """)
        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_compression_versions_conversation
        ON compression_versions(conversation_id, created_at);
        """)
        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_compression_active_versions_conversation
        ON compression_active_versions(conversation_id);
        """)
        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_compression_version_sources_version
        ON compression_version_sources(version_id, ordinal);
        """)
        try database.execute("PRAGMA user_version = \(version);")
    }

    private static func userVersion(_ database: SQLiteDatabase) throws -> Int {
        let rows = try database.query("PRAGMA user_version;")
        guard let value = rows.first?["user_version"] else {
            return 0
        }

        switch value {
        case let .integer(integer):
            return Int(integer)
        default:
            return 0
        }
    }
}

public enum CodexPlusSchemaError: Error, Equatable {
    case unsupportedFutureVersion(Int)
}
