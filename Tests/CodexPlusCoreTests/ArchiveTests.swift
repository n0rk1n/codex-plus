import Foundation
import CodexPlusCore

@MainActor
func runArchiveTests() {
    let conversationID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    let conversation = ConversationSession(
        id: conversationID,
        title: "Git 提交 & 推送",
        prompt: "commit",
        workspacePath: "/tmp/codex-plus",
        state: .completed,
        createdAt: Date(timeIntervalSince1970: 100),
        lastActivityAt: Date(timeIntervalSince1970: 120),
        events: [
            .userPrompt(id: UUID(), text: "提交所有设计文档"),
            .command(id: UUID(), executionID: "cmd-1", command: "git status --short", status: .completed),
            .assistantMessage(id: UUID(), text: "已经提交。")
        ]
    )

    let markdown = MarkdownArchiveRenderer.render(conversation: conversation, projectName: "codex-plus")
    expect(markdown.contains("# Git 提交 & 推送"), "archive markdown contains title")
    expect(markdown.contains("项目：codex-plus"), "archive markdown contains project")
    expect(markdown.contains("git status --short"), "archive markdown contains command")
    expect(markdown.contains("已经提交。"), "archive markdown contains assistant message")

    let record = ArchiveSearchService.indexRecord(
        conversation: conversation,
        projectID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        projectName: "codex-plus",
        archivedAt: Date(timeIntervalSince1970: 130)
    )
    expect(record.searchableText.contains("提交所有设计文档"), "archive index includes user text")
    expect(record.commandText.contains("git status --short"), "archive index includes command text")
    expect(record.title == "Git 提交 & 推送", "archive index preserves title")

    let project = WorkspaceSessionGroup(
        id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        path: "/tmp/codex-plus",
        displayName: "codex-plus",
        lastActivityAt: Date(timeIntervalSince1970: 130)
    )

    let defaultArchiveRoot = ArchiveSearchService.defaultArchiveRootPath(homeDirectoryPath: "/Users/tester")
    expect(
        defaultArchiveRoot == "/Users/tester/.codex-plus/Archives",
        "default archive root path uses the unified .codex-plus archives directory"
    )
    expect(
        ArchiveSearchService.legacyArchiveRootPath(homeDirectoryPath: "/Users/tester") ==
            "/Users/tester/Library/Application Support/CodexPlus/Archives",
        "legacy archive root remains available only for one-time migration"
    )

    let defaultArchivePath = ArchiveSearchService.defaultArchiveMarkdownPath(
        conversation: conversation,
        archiveRootPath: defaultArchiveRoot
    )
    expect(
        !defaultArchivePath.hasPrefix(project.path),
        "default archive markdown path does not live under project path"
    )
    expect(
        defaultArchivePath.contains("/Archives/"),
        "default archive markdown path stays under Archives root"
    )
    expect(
        defaultArchivePath.hasSuffix("/\(conversation.id.uuidString.lowercased()).md"),
        "default archive markdown path includes conversation id filename"
    )

    let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-plus-archive-\(UUID().uuidString).sqlite")
    let archiveRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("codex-plus-global-archives-\(UUID().uuidString)", isDirectory: true)

    do {
        let database = try SQLiteDatabase(path: dbURL.path)
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        try repository.saveProject(project)
        try repository.saveConversation(conversation, projectID: project.id)

        let archiveService = ArchiveSearchService(
            repository: repository,
            archiveRootPath: archiveRootURL.path,
            now: { Date(timeIntervalSince1970: 130) }
        )
        let archivedRecord = try archiveService.archive(conversation: conversation, project: project)
        expect(archivedRecord == record, "archive service returns expected index record")

        let archiveMarkdownPath = ArchiveSearchService.defaultArchiveMarkdownPath(
            conversation: conversation,
            archiveRootPath: archiveRootURL.path
        )
        expect(
            FileManager.default.fileExists(atPath: archiveMarkdownPath),
            "archive service writes readable markdown export"
        )
        let writtenMarkdown = (try? String(contentsOfFile: archiveMarkdownPath, encoding: .utf8)) ?? ""
        expect(writtenMarkdown == markdown, "archive markdown export matches rendered content")

        let searchResults = try archiveService.search("设计文档")
        expect(searchResults.map(\.conversationID) == [conversation.id], "archive search finds matching conversation")
        let defaultSearchResults = try archiveService.search("")
        expect(
            defaultSearchResults.map(\.conversationID) == [conversation.id],
            "archive search without a query lists archived conversations"
        )

        let archivedConversation = try repository.loadConversations().first { $0.id == conversation.id }
        expect(archivedConversation?.isArchived == true, "archive mark persists archived conversation state")
        expect(
            archivedConversation?.lastActivityAt == conversation.lastActivityAt,
            "archive operation does not alter conversation last activity"
        )

        try repository.archiveConversation(
            record: record,
            archiveMarkdownPath: "/tmp/codex-plus-global-archives/\(conversation.id.uuidString.lowercased()).md",
            archivedAt: Date(timeIntervalSince1970: 131)
        )
        let secondSearchResults = try repository.searchArchiveRecords(query: "git status")
        expect(secondSearchResults.count == 1, "atomic archive repository method upserts archive record")
    } catch {
        expect(false, "archive repository test should not throw: \(error)")
    }

    try? FileManager.default.removeItem(at: dbURL)
    try? FileManager.default.removeItem(at: archiveRootURL)
}
