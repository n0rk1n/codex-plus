import Foundation
import XCTest
@testable import CodexPlusCore

final class ArchiveContextCompressionTests: XCTestCase {
    func testArchiveMarkdownIncludesCompressionMetadataButSearchIndexesOriginalText() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-plus-archive-compression-\(UUID().uuidString).sqlite")
        let archiveRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-plus-archive-compression-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(at: archiveRootURL)
        }

        let database = try SQLiteDatabase(path: databaseURL.path)
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let project = WorkspaceSessionGroup(
            id: uuid(1),
            path: "/tmp/project",
            displayName: "Project",
            conversationIDs: [uuid(2)],
            lastActivityAt: Date(timeIntervalSince1970: 1)
        )
        let conversation = ConversationSession(
            id: uuid(2),
            title: "Compression Archive",
            prompt: "Prompt",
            workspacePath: project.path,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 2),
            lastActivityAt: Date(timeIntervalSince1970: 3),
            events: [
                .userPrompt(id: uuid(10), text: "Original source question"),
                .assistantMessage(id: uuid(11), text: "Original source answer")
            ]
        )
        try repository.saveProject(project)
        try repository.saveConversation(conversation, projectID: project.id)
        let compressionState = try repository.loadCompressionState(conversationID: conversation.id)
        let round = try XCTUnwrap(compressionState.rounds.first)
        let version = CompressionVersion(
            id: uuid(20),
            conversationID: conversation.id,
            scopeKind: .round,
            operation: .manualEdit,
            status: .active,
            content: "Compressed model input only",
            templateID: nil,
            compressionInputID: nil,
            errorMessage: nil,
            createdAt: Date(timeIntervalSince1970: 4),
            updatedAt: Date(timeIntervalSince1970: 5)
        )
        try repository.saveCompressionVersion(version)
        try repository.saveCompressionVersionSources([
            CompressionVersionSource(id: uuid(21), versionID: version.id, sourceKind: .round, sourceID: round.id, ordinal: 0)
        ])
        try repository.setActiveCompressionVersion(
            CompressionActiveVersion(
                id: uuid(22),
                conversationID: conversation.id,
                roundID: round.id,
                rangeID: nil,
                activeVersionID: version.id
            )
        )

        let archiveService = ArchiveSearchService(
            repository: repository,
            archiveRootPath: archiveRootURL.path,
            now: { Date(timeIntervalSince1970: 6) }
        )
        let record = try archiveService.archive(conversation: conversation, project: project)
        let archiveMarkdownPath = ArchiveSearchService.defaultArchiveMarkdownPath(
            conversation: conversation,
            archiveRootPath: archiveRootURL.path
        )
        let markdown = try String(contentsOfFile: archiveMarkdownPath, encoding: .utf8)

        XCTAssertTrue(markdown.contains("## Context Compression"))
        XCTAssertTrue(markdown.contains("### Active Model Input At Archive Time"))
        XCTAssertTrue(markdown.contains("Compressed model input only"))
        XCTAssertTrue(markdown.contains(version.id.uuidString.lowercased()))
        XCTAssertTrue(record.searchableText.contains("Original source question"))
        XCTAssertFalse(record.searchableText.contains("Compressed model input only"))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
