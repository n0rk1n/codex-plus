import Foundation
import CodexPlusCore

func runPromptTemplatePersistenceLegacyTests() {
    let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-plus-prompt-templates-\(UUID().uuidString).sqlite")

    defer {
        try? FileManager.default.removeItem(at: dbURL)
    }

    do {
        let database = try SQLiteDatabase(path: dbURL.path)
        try CodexPlusSchema.migrate(database)

        let versionRows = try database.query("PRAGMA user_version;")
        if case let .integer(userVersion)? = versionRows.first?["user_version"] {
            expect(
                userVersion == Int64(CodexPlusSchema.version),
                "prompt template schema migration persists user_version"
            )
        } else {
            expect(false, "prompt template schema migration exposes user_version")
        }

        let tableRows = try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'prompt_templates';"
        )
        expect(tableRows.count == 1, "prompt template schema creates the prompt_templates table")

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
        let loadedTemplates = try repository.loadPromptTemplates()
        expect(
            loadedTemplates == [template],
            "prompt template repository saves and loads user custom templates"
        )

        var renamed = template
        renamed.name = "项目复盘摘要 v2"
        renamed.updatedAt = Date(timeIntervalSince1970: 30)
        try repository.savePromptTemplate(renamed)
        let updatedTemplates = try repository.loadPromptTemplates()
        expect(
            updatedTemplates == [renamed],
            "prompt template repository updates existing templates"
        )

        try repository.deletePromptTemplate(template.id)
        let templatesAfterDelete = try repository.loadPromptTemplates()
        expect(
            templatesAfterDelete.isEmpty,
            "prompt template repository deletes saved templates"
        )

        let builtIn = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100)).first!
        do {
            try repository.savePromptTemplate(builtIn)
            expect(false, "prompt template repository rejects built-in templates for persistence")
        } catch {
            expect(true, "prompt template repository rejects built-in templates for persistence")
        }
    } catch {
        expect(false, "prompt template persistence tests should not throw: \(error)")
    }
}
