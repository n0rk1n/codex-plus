import Foundation
import XCTest
@testable import CodexPlusCore

final class PromptTemplatePersistenceTests: XCTestCase {
    func testSchemaCreatesPromptTemplatesTableAndBumpsVersion() throws {
        let database = try temporaryDatabase()

        try CodexPlusSchema.migrate(database)

        let versionRows = try database.query("PRAGMA user_version;")
        XCTAssertEqual(versionRows.first?["user_version"], .integer(Int64(CodexPlusSchema.version)))

        let tableRows = try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'prompt_templates';"
        )
        XCTAssertEqual(tableRows.count, 1)
    }

    func testRepositoryRoundTripsUserCustomPromptTemplates() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let template = PromptTemplate(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            source: .userCustom,
            type: .archiveConversationSummary,
            name: "项目复盘摘要",
            systemPrompt: "整理归档对话",
            userPrompt: "",
            note: "用于项目复盘",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try repository.savePromptTemplate(template)
        XCTAssertEqual(try repository.loadPromptTemplates(), [template])

        var renamed = template
        renamed.name = "项目复盘摘要 v2"
        renamed.updatedAt = Date(timeIntervalSince1970: 30)
        try repository.savePromptTemplate(renamed)

        XCTAssertEqual(try repository.loadPromptTemplates(), [renamed])

        try repository.deletePromptTemplate(template.id)
        XCTAssertTrue(try repository.loadPromptTemplates().isEmpty)
    }

    func testRepositoryRejectsSavingBuiltInPromptTemplates() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let builtIn = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100)).first!

        XCTAssertThrowsError(try repository.savePromptTemplate(builtIn))
    }

    func testRepositoryRoundTripsOneDefaultPromptTemplatePerType() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let first = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let second = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let optimize = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!

        try repository.setDefaultPromptTemplateID(first, for: .archiveConversationSummary)
        XCTAssertEqual(
            try repository.loadDefaultPromptTemplateIDs(),
            [.archiveConversationSummary: first]
        )

        try repository.setDefaultPromptTemplateID(second, for: .archiveConversationSummary)
        try repository.setDefaultPromptTemplateID(optimize, for: .optimizeUserInputPrompt)

        XCTAssertEqual(
            try repository.loadDefaultPromptTemplateIDs(),
            [
                .archiveConversationSummary: second,
                .optimizeUserInputPrompt: optimize
            ]
        )
    }

    private func temporaryDatabase() throws -> SQLiteDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-plus-\(UUID().uuidString).sqlite")
        return try SQLiteDatabase(path: url.path)
    }
}
