import Foundation

public enum CodexPlusSchema {
    public static let version = 2

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
