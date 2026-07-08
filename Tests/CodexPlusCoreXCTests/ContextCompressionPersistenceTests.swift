import Foundation
import XCTest
@testable import CodexPlusCore

final class ContextCompressionPersistenceTests: XCTestCase {
    func testSchemaCreatesCompressionTablesAndBumpsVersion() throws {
        let database = try temporaryDatabase()

        try CodexPlusSchema.migrate(database)

        let versionRows = try database.query("PRAGMA user_version;")
        XCTAssertEqual(versionRows.first?["user_version"], .integer(4))

        for tableName in [
            "compression_rounds",
            "compression_round_events",
            "compression_versions",
            "compression_version_sources",
            "compression_lineage_edges",
            "compression_active_versions",
            "compression_inputs",
            "compression_tombstones"
        ] {
            let tableRows = try database.query(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
                [.text(tableName)]
            )
            XCTAssertEqual(tableRows.count, 1, "Missing table \(tableName)")
        }
    }

    func testSchemaCreatesCompressionIndexes() throws {
        let database = try temporaryDatabase()

        try CodexPlusSchema.migrate(database)

        for indexName in [
            "idx_compression_rounds_conversation",
            "idx_compression_round_events_round",
            "idx_compression_versions_conversation",
            "idx_compression_active_versions_conversation",
            "idx_compression_version_sources_version"
        ] {
            let indexRows = try database.query(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?;",
                [.text(indexName)]
            )
            XCTAssertEqual(indexRows.count, 1, "Missing index \(indexName)")
        }
    }

    func testCompressionSchemaRejectsInvalidVersionStatusAndOperation() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        try insertConversationFixture(into: database)

        XCTAssertThrowsError(
            try database.execute(
                """
                INSERT INTO compression_versions (
                    id,
                    conversation_id,
                    scope_kind,
                    operation,
                    status,
                    content,
                    created_at,
                    updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                [
                    .text("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
                    .text("11111111-1111-1111-1111-111111111111"),
                    .text("round"),
                    .text("not_real"),
                    .text("active"),
                    .text("content"),
                    .real(10),
                    .real(20)
                ]
            )
        )

        XCTAssertThrowsError(
            try database.execute(
                """
                INSERT INTO compression_versions (
                    id,
                    conversation_id,
                    scope_kind,
                    operation,
                    status,
                    content,
                    created_at,
                    updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """,
                [
                    .text("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
                    .text("11111111-1111-1111-1111-111111111111"),
                    .text("round"),
                    .text("manual_edit"),
                    .text("not_real"),
                    .text("content"),
                    .real(10),
                    .real(20)
                ]
            )
        )
    }

    func testCompressionRoundsAreUniqueByConversationAndRoundIndex() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        try insertConversationFixture(into: database)
        try insertConversationEventFixture(
            id: "22222222-2222-2222-2222-222222222222",
            ordinal: 0,
            into: database
        )

        try insertCompressionRound(
            id: "33333333-3333-3333-3333-333333333333",
            roundIndex: 0,
            userEventID: "22222222-2222-2222-2222-222222222222",
            into: database
        )

        XCTAssertThrowsError(
            try insertCompressionRound(
                id: "44444444-4444-4444-4444-444444444444",
                roundIndex: 0,
                userEventID: "22222222-2222-2222-2222-222222222222",
                into: database
            )
        )
    }

    private func temporaryDatabase() throws -> SQLiteDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-plus-\(UUID().uuidString).sqlite")
        return try SQLiteDatabase(path: url.path)
    }

    private func insertConversationFixture(into database: SQLiteDatabase) throws {
        try database.execute(
            """
            INSERT INTO projects (id, display_name, path, created_at, last_activity_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            [
                .text("00000000-0000-0000-0000-000000000000"),
                .text("Project"),
                .text("/tmp/project"),
                .real(1),
                .real(1)
            ]
        )
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
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .text("11111111-1111-1111-1111-111111111111"),
                .text("00000000-0000-0000-0000-000000000000"),
                .text("Conversation"),
                .text("Prompt"),
                .text("/tmp/project"),
                .text("idle"),
                .text("semiAutomatic"),
                .integer(0),
                .integer(0),
                .integer(0),
                .real(1),
                .real(1),
                .null,
                .null
            ]
        )
    }

    private func insertConversationEventFixture(id: String, ordinal: Int, into database: SQLiteDatabase) throws {
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
                .text(id),
                .text("11111111-1111-1111-1111-111111111111"),
                .integer(Int64(ordinal)),
                .text("userPrompt"),
                .text("Hello"),
                .text("{}"),
                .null,
                .real(1),
                .text("Hello")
            ]
        )
    }

    private func insertCompressionRound(
        id: String,
        roundIndex: Int,
        userEventID: String,
        into database: SQLiteDatabase
    ) throws {
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
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            [
                .text(id),
                .text("11111111-1111-1111-1111-111111111111"),
                .integer(Int64(roundIndex)),
                .text(userEventID),
                .null,
                .null,
                .text("idle"),
                .null,
                .null,
                .real(1),
                .real(1)
            ]
        )
    }
}
