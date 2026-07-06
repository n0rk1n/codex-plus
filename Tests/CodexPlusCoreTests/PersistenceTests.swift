import Foundation
import CodexPlusCore

@MainActor
func runPersistenceTests() {
    let appSupportDatabasePath = ApplicationSupportPaths.databasePath(
        bundleIdentifier: "com.example.CodexPlusTests",
        homeDirectoryPath: "/Users/test"
    )
    expect(
        appSupportDatabasePath == "/Users/test/Library/Application Support/com.example.CodexPlusTests/CodexPlus.sqlite",
        "application support database path is deterministic"
    )

    let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-plus-\(UUID().uuidString).sqlite")

    do {
        let database = try SQLiteDatabase(path: dbURL.path)
        try CodexPlusSchema.migrate(database)
        let versionRows = try database.query("PRAGMA user_version;")
        if case let .integer(userVersion)? = versionRows.first?["user_version"] {
            expect(userVersion == Int64(CodexPlusSchema.version), "schema migration persists user_version")
        } else {
            expect(false, "schema migration exposes user_version")
        }

        let repository = SQLiteCodexPlusRepository(database: database)

        let project = WorkspaceSessionGroup(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            path: "/tmp/codex-plus",
            displayName: "codex-plus",
            lastActivityAt: Date(timeIntervalSince1970: 10)
        )
        let conversation = ConversationSession(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "重设计 Codex 软件",
            prompt: "start",
            workspacePath: project.path,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 20),
            lastActivityAt: Date(timeIntervalSince1970: 30),
            events: [
                .userPrompt(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, text: "start"),
                .assistantMessage(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, text: "done")
            ]
        )
        let archivedConversation = ConversationSession(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "归档对话",
            prompt: "old prompt",
            workspacePath: project.path,
            state: .completed,
            isArchived: true,
            createdAt: Date(timeIntervalSince1970: 5),
            lastActivityAt: Date(timeIntervalSince1970: 6)
        )

        try repository.saveProject(project)
        try repository.saveConversation(conversation, projectID: project.id)
        try repository.saveConversation(archivedConversation, projectID: project.id)

        let loadedProjects = try repository.loadProjects()
        let loadedConversations = try repository.loadConversations()

        expect(loadedProjects.count == 1, "repository loads one saved project")
        expect(
            loadedProjects[0] == WorkspaceSessionGroup(
                id: project.id,
                path: project.path,
                displayName: project.displayName,
                conversationIDs: [conversation.id],
                lastActivityAt: project.lastActivityAt
            ),
            "repository restores project conversation IDs"
        )
        expect(loadedConversations.count == 2, "repository loads both saved conversations")
        guard let foundConversation = loadedConversations.first(where: { $0.id == conversation.id }) else {
            expect(false, "repository loads active conversation")
            return
        }
        expect(foundConversation.id == conversation.id, "repository preserves active conversation id")
        expect(foundConversation.events.count == 2, "repository preserves conversation events")

        guard let foundArchivedConversation = loadedConversations.first(where: { $0.id == archivedConversation.id }) else {
            expect(false, "repository loads archived conversation")
            return
        }
        expect(foundArchivedConversation.isArchived, "repository marks archived conversations as archived")
        expect(
            !loadedProjects[0].conversationIDs.contains(archivedConversation.id),
            "archived conversation is excluded from project membership"
        )

        let memoryCardID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let memoryCard = MemoryCard(
            id: memoryCardID,
            scope: "project",
            type: "text",
            title: "原型约束",
            summary: "悬浮窗口交互",
            body: "归档会话必须可搜索。",
            contentShape: "text",
            status: "active",
            createdAt: Date(timeIntervalSince1970: 40),
            updatedAt: Date(timeIntervalSince1970: 41),
            sourceMetadataJSON: #"{"source":"test"}"#
        )
        try repository.saveMemoryCard(memoryCard)
        let projectMemoryCards = try repository.loadMemoryCards(scope: "project")
        expect(projectMemoryCards == [memoryCard], "repository round trips memory cards by scope")

        var renamedMemoryCard = memoryCard
        renamedMemoryCard.title = "更新后的原型约束"
        renamedMemoryCard.updatedAt = Date(timeIntervalSince1970: 42)
        try repository.saveMemoryCard(renamedMemoryCard)
        let allMemoryCards = try repository.loadMemoryCards(scope: nil)
        expect(allMemoryCards == [renamedMemoryCard], "repository updates memory card records")

        let memorySource = MemorySource(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            memoryCardID: memoryCardID,
            sourceKind: "conversation",
            sourceID: conversation.id.uuidString.lowercased(),
            sourcePath: nil,
            createdAt: Date(timeIntervalSince1970: 43)
        )
        try repository.saveMemorySource(memorySource)
        let memorySources = try repository.loadMemorySources(memoryCardID: memoryCardID)
        expect(memorySources == [memorySource], "repository round trips memory sources")

        let attachment = CodexPlusAttachment(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            ownerKind: "memory_card",
            ownerID: memoryCardID,
            filePath: "/tmp/prototype.png",
            originalFilePath: "/Users/test/prototype.png",
            contentType: "image/png",
            byteCount: 1234,
            checksum: "sha256:test",
            isSnapshot: true,
            createdAt: Date(timeIntervalSince1970: 44)
        )
        try repository.saveAttachment(attachment)
        let attachments = try repository.loadAttachments(ownerKind: "memory_card", ownerID: memoryCardID)
        expect(
            attachments == [attachment],
            "repository round trips attachments by owner"
        )

        try repository.deleteAttachment(attachment.id)
        let attachmentsAfterDelete = try repository.loadAttachments(ownerKind: "memory_card", ownerID: memoryCardID)
        expect(
            attachmentsAfterDelete.isEmpty,
            "repository deletes attachments"
        )

        try repository.deleteMemorySource(memorySource.id)
        let sourcesAfterDelete = try repository.loadMemorySources(memoryCardID: memoryCardID)
        expect(sourcesAfterDelete.isEmpty, "repository deletes memory sources")

        try repository.deleteMemoryCard(memoryCardID)
        let cardsAfterDelete = try repository.loadMemoryCards(scope: nil)
        expect(cardsAfterDelete.isEmpty, "repository deletes memory cards")
    } catch {
        expect(false, "persistence test should not throw: \(error)")
    }

    try? FileManager.default.removeItem(at: dbURL)
}
