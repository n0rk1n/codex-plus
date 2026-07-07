import Foundation
import CodexPlusCore

@MainActor
func runWorkbenchStoreTests() {
    runFreshWorkbenchSubmitTests()
    runWorkbenchDraftWorkspaceSelectionTests()
    runWorkbenchSmokeTests()
    runArchiveLifecycleTests()
    runArchiveRestoreTests()
    runArchiveRestartConsistencyTests()
    runRunningArchiveConfirmationTests()
    runRunningStopPersistenceFailureTests()
    runArchivePersistenceFailureTests()
}

@MainActor
private func runWorkbenchDraftWorkspaceSelectionTests() {
    withSQLiteRepositoryTest("new workbench draft defaults to generated workspace") { _, repository in
        let engine = ManualExecutionEngine()
        let defaultWorkspacePath = "/tmp/codex-plus-generated-draft"
        let store = WorkbenchStore(
            repository: repository,
            engine: engine,
            defaultWorkspacePathProvider: { defaultWorkspacePath }
        )

        store.createProject(path: "/tmp/codex-plus-existing", displayName: "codex-plus-existing")

        store.beginNewConversationDraft()

        expect(
            !store.snapshot.projectCards.contains(where: { $0.isActive }),
            "new conversation draft starts without a selected workspace"
        )

        store.submitPrompt("draft without workspace")

        expect(
            store.snapshot.activeConversation?.workspacePath == defaultWorkspacePath,
            "unselected new draft submit uses a generated default workspace"
        )
        expect(
            engine.requests.first?.workingDirectoryURL.path == defaultWorkspacePath,
            "engine starts unselected new draft in the generated default workspace"
        )
    }

    withSQLiteRepositoryTest("new workbench draft can use selected workspace") { _, repository in
        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(
            repository: repository,
            engine: engine,
            defaultWorkspacePathProvider: { "/tmp/codex-plus-generated-draft" }
        )

        store.createProject(path: "/tmp/codex-plus-existing", displayName: "codex-plus-existing")
        store.beginNewConversationDraft()
        store.createProject(path: "/tmp/codex-plus-selected", displayName: "codex-plus-selected")
        store.submitPrompt("draft with workspace")

        expect(
            store.snapshot.activeConversation?.workspacePath == "/tmp/codex-plus-selected",
            "selected new draft submit uses the user-selected workspace"
        )
        expect(
            engine.requests.first?.workingDirectoryURL.path == "/tmp/codex-plus-selected",
            "engine starts selected new draft in the user-selected workspace"
        )
    }

    withSQLiteRepositoryTest("new workbench draft can clear selected workspace") { _, repository in
        let engine = ManualExecutionEngine()
        let defaultWorkspacePath = "/tmp/codex-plus-generated-after-clear"
        let store = WorkbenchStore(
            repository: repository,
            engine: engine,
            defaultWorkspacePathProvider: { defaultWorkspacePath }
        )

        store.beginNewConversationDraft()
        store.createProject(path: "/tmp/codex-plus-selected", displayName: "codex-plus-selected")
        store.clearDraftWorkspaceSelection()

        expect(
            !store.snapshot.projectCards.contains(where: { $0.projectPath == "/tmp/codex-plus-selected" }),
            "clearing the draft workspace hides empty project cards from the top strip"
        )
        expect(
            !store.snapshot.projectCards.contains(where: { $0.isActive }),
            "clearing the draft workspace removes the active project selection"
        )

        store.submitPrompt("draft after clearing workspace")

        expect(
            store.snapshot.activeConversation?.workspacePath == defaultWorkspacePath,
            "cleared new draft submit uses a generated default workspace"
        )
        expect(
            engine.requests.first?.workingDirectoryURL.path == defaultWorkspacePath,
            "engine starts cleared new draft in the generated default workspace"
        )
    }
}

@MainActor
private func runFreshWorkbenchSubmitTests() {
    withSQLiteRepositoryTest("fresh workbench submit test") { _, repository in
        let engine = ManualExecutionEngine()
        let defaultWorkspacePath = "/tmp/codex-plus-default"
        let store = WorkbenchStore(
            repository: repository,
            engine: engine,
            defaultWorkspacePathProvider: { defaultWorkspacePath }
        )

        expect(store.snapshot.activeConversation == nil, "fresh workbench starts without active conversation")
        expect(store.snapshot.projectCards.isEmpty, "fresh workbench starts without project cards")
        expect(store.snapshot.canSubmitPrompt, "fresh workbench can submit the first prompt")
        expect(!store.snapshot.canStartNewConversation, "fresh blank workbench disables redundant new conversation")

        store.submitPrompt("first prompt")

        expect(engine.requests.count == 1, "fresh submit starts the engine")
        expect(store.snapshot.activeConversation?.prompt == "first prompt", "fresh submit creates an active conversation")
        expect(store.snapshot.activeConversation?.workspacePath == defaultWorkspacePath, "fresh submit uses default workspace")
        expect(store.snapshot.projectCards.first?.projectPath == defaultWorkspacePath, "fresh submit creates a project card")
    }

    withSQLiteRepositoryTest("fresh workbench default directory creation test") { _, repository in
        let tempHome = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("codex-plus-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let fixedDate = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: 2026,
            month: 7,
            day: 5
        ).date!
        let expectedWorkspacePath = tempHome
            .appendingPathComponent(".codex-plus", isDirectory: true)
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent("2026-07-05", isDirectory: true)
            .appendingPathComponent("2217", isDirectory: true)
            .path

        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(
            repository: repository,
            engine: engine,
            defaultWorkspacePathProvider: {
                try ConversationWorkspacePolicy.createDefaultWorkspaceDirectory(
                    homeDirectoryPath: tempHome.path,
                    date: fixedDate,
                    randomSuffixes: [2217],
                    calendar: Calendar(identifier: .gregorian)
                )
            }
        )

        store.submitPrompt("first prompt")

        expect(store.snapshot.activeConversation?.workspacePath == expectedWorkspacePath, "fresh submit uses generated default workspace")
        expect(engine.requests.first?.workingDirectoryURL.path == expectedWorkspacePath, "engine starts in generated default workspace")
        expect(FileManager.default.fileExists(atPath: expectedWorkspacePath), "fresh submit creates generated default workspace directory")
    }
}

@MainActor
private func runWorkbenchSmokeTests() {
    withSQLiteRepositoryTest("workbench smoke test") { _, repository in
        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(repository: repository, engine: engine)

        store.createProject(path: "/tmp/codex-plus", displayName: "codex-plus")
        store.startConversation(prompt: "start", workspacePath: "/tmp/codex-plus")

        expect(store.snapshot.activeConversation?.state == .running, "store marks new conversation running")
        expect(engine.requests.count == 1, "store starts engine")
        expect(store.snapshot.projectCards.count == 1, "store produces project cards")
        expect(store.snapshot.projectCards[0].conversationTitle != "暂无对话", "store card shows active conversation")
        expect(store.snapshot.composerAction == .stop, "store shows stop while running")
        expect(!store.snapshot.canStartNewConversation, "running workbench disables new conversation")

        let runningID = store.snapshot.activeConversation?.id
        store.beginNewConversationDraft()
        expect(store.snapshot.activeConversation?.id == runningID, "new conversation draft keeps running task visible")
        expect(store.snapshot.composerAction == .stop, "running task still shows stop after draft request")

        store.sendFollowUp("second")
        let lastEvent = store.snapshot.activeConversation?.events.last
        if case let .some(.error(_, text)) = lastEvent {
            expect(text == "任务运行中，当前不能发送新的消息。", "store rejects follow-up while running")
        } else {
            expect(false, "store appends an error when follow-up is sent while running")
        }

        store.stopActiveRun()
        expect(store.snapshot.activeConversation?.state == .stopped, "store marks stopped")
        expect(engine.stopCount == 1, "store stops active engine handle")
        expect(store.snapshot.composerAction == .send, "store shows send after stop")
        expect(store.snapshot.canStartNewConversation, "stopped workbench can open a new conversation draft")

        store.beginNewConversationDraft()
        expect(store.snapshot.activeConversation == nil, "new conversation draft clears terminal active conversation")
        expect(store.snapshot.canSubmitPrompt, "new conversation draft can submit a first prompt")
        expect(!store.snapshot.canStartNewConversation, "blank new conversation draft disables redundant new conversation")

        store.submitPrompt("fresh task")
        expect(engine.requests.count == 2, "submitting a new draft starts a new engine run")
        expect(store.snapshot.activeConversation?.prompt == "fresh task", "new draft submit becomes active conversation prompt")
        expect(store.snapshot.activeConversation?.state == .running, "new draft submit starts running")
    }
}

@MainActor
private func runArchiveRestoreTests() {
    withSQLiteRepositoryTest("archive restore test") { dbURL, repository in
        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(repository: repository, engine: engine)

        store.createProject(path: "/tmp/codex-plus-restore", displayName: "codex-plus-restore")
        store.startConversation(prompt: "start restore", workspacePath: "/tmp/codex-plus-restore")
        guard let conversationID = store.snapshot.activeConversation?.id else {
            expect(false, "archive restore test creates an active conversation")
            return
        }

        engine.finish(
            conversationID: conversationID,
            result: CodexRunResult(exitCode: 0, stderr: "")
        )
        drainMainRunLoop()
        _ = store.archiveConversation(conversationID)

        store.showArchiveSearch()
        store.openArchive(conversationID)
        let restored = store.restoreArchive(conversationID)
        expect(restored, "archived conversation restores successfully")
        expect(store.snapshot.isShowingArchiveSearch, "restoring archive keeps archive page visible")
        expect(store.snapshot.openedArchiveConversation == nil, "restoring opened archive clears archive detail")
        expect(
            store.snapshot.projectCards.contains(where: { $0.conversationID == conversationID }),
            "restored archive returns to visible project cards"
        )
        expect(
            !store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
            "restored archive is removed from current archive results"
        )

        store.searchArchives("start restore")
        expect(
            !store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
            "restored archive is not searchable as archived"
        )
        expect(store.snapshot.isShowingArchiveSearch, "searching archives after restore still leaves the archive page visible")

        store.selectConversation(conversationID)
        expect(!store.snapshot.isShowingArchiveSearch, "jumping to restored conversation exits archive page")
        expect(store.snapshot.activeConversation?.id == conversationID, "jumping selects the restored conversation")

        do {
            let database = try SQLiteDatabase(path: dbURL.path)
            let restartedRepository = SQLiteCodexPlusRepository(database: database)
            let restartedStore = WorkbenchStore(repository: restartedRepository, engine: ManualExecutionEngine())
            expect(
                restartedStore.snapshot.projectCards.contains(where: { $0.conversationID == conversationID }),
                "restored archive stays visible after restart"
            )
            restartedStore.searchArchives("start restore")
            expect(
                !restartedStore.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
                "restored archive stays out of archive search after restart"
            )
        } catch {
            expect(false, "archive restore restart check should not throw: \(error)")
        }
    }
}

@MainActor
private func runArchiveLifecycleTests() {
    withSQLiteRepositoryTest("archive lifecycle test") { dbURL, repository in
        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(repository: repository, engine: engine)

        store.createProject(path: "/tmp/codex-plus", displayName: "codex-plus")
        store.startConversation(prompt: "start archive", workspacePath: "/tmp/codex-plus")
        guard let conversationID = store.snapshot.activeConversation?.id else {
            expect(false, "archive lifecycle test creates an active conversation")
            return
        }

        engine.finish(
            conversationID: conversationID,
            result: CodexRunResult(exitCode: 0, stderr: "")
        )
        drainMainRunLoop()
        expect(store.snapshot.activeConversation?.state == .completed, "archive lifecycle setup finishes the conversation")
        let expectedEvents = store.snapshot.activeConversation?.events ?? []

        let result = store.archiveConversation(conversationID)
        expect(result == .archived, "completed conversation archives successfully")
        expect(store.snapshot.projectCards.isEmpty, "archiving the last conversation hides the empty project card")
        expect(
            !store.snapshot.projectCards.contains(where: { $0.conversationID == conversationID }),
            "archived conversation is removed from active project cards"
        )

        store.showArchiveSearch()
        expect(store.snapshot.isShowingArchiveSearch, "archived entry opens the archive page")
        expect(!store.snapshot.canStartNewConversation, "archive page keeps the top new conversation action disabled")
        expect(
            store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
            "archive page lists archived conversations by default"
        )

        store.searchArchives("start")
        expect(
            store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
            "archived conversation is searchable"
        )

        store.openArchive(conversationID)
        expect(store.snapshot.isShowingArchiveSearch, "opening an archive keeps the archived page visible")
        expect(store.snapshot.openedArchiveConversation?.id == conversationID, "archived conversation can be reopened")
        expect(
            store.snapshot.openedArchiveConversation?.events == expectedEvents,
            "reopened archived conversation exposes its event stream"
        )
        expect(
            store.snapshot.activeConversation == nil,
            "opening an archived conversation does not restore it to active conversations"
        )

        store.deleteArchive(conversationID)
        expect(store.snapshot.isShowingArchiveSearch, "deleting an archive keeps the archive page visible")
        expect(store.snapshot.openedArchiveConversation == nil, "deleting the opened archive clears the detail pane")
        expect(
            !store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
            "deleted archive is removed from current archive results"
        )

        store.searchArchives("start")
        expect(
            !store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
            "deleted archive is not searchable"
        )

        do {
            let database = try SQLiteDatabase(path: dbURL.path)
            let restartedRepository = SQLiteCodexPlusRepository(database: database)
            let restartedStore = WorkbenchStore(repository: restartedRepository, engine: ManualExecutionEngine())
            restartedStore.searchArchives("start")
            expect(
                !restartedStore.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
                "deleted archive does not reappear after restart"
            )
        } catch {
            expect(false, "archive deletion restart check should not throw: \(error)")
        }

        store.returnToConversationPage()
        expect(!store.snapshot.isShowingArchiveSearch, "return to conversation exits the archive page")
        expect(store.snapshot.openedArchiveConversation == nil, "return to conversation clears the opened archive detail")
        expect(!store.snapshot.canStartNewConversation, "blank conversation page keeps redundant new conversation disabled")
    }
}

@MainActor
private func runArchiveRestartConsistencyTests() {
    withSQLiteRepositoryTest("archive restart consistency test") { dbURL, repository in
        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(repository: repository, engine: engine)

        store.createProject(path: "/tmp/codex-plus", displayName: "codex-plus")
        store.startConversation(prompt: "start archive", workspacePath: "/tmp/codex-plus")
        guard let conversationID = store.snapshot.activeConversation?.id else {
            expect(false, "restart setup creates an active conversation")
            return
        }

        engine.finish(
            conversationID: conversationID,
            result: CodexRunResult(exitCode: 0, stderr: "")
        )
        drainMainRunLoop()
        expect(store.snapshot.activeConversation?.state == .completed, "restart setup finishes the conversation")
        _ = store.archiveConversation(conversationID)

        expect(
            !store.snapshot.projectCards.contains(where: { $0.projectPath == "/tmp/codex-plus" }),
            "empty project card stays hidden before restart"
        )

        do {
            let database = try SQLiteDatabase(path: dbURL.path)
            let restartedRepository = SQLiteCodexPlusRepository(database: database)
            let restartedStore = WorkbenchStore(repository: restartedRepository, engine: ManualExecutionEngine())

            expect(
                !restartedStore.snapshot.projectCards.contains(where: { $0.projectPath == "/tmp/codex-plus" }),
                "restart does not restore empty project cards"
            )
        } catch {
            expect(false, "restart consistency test should not throw: \(error)")
        }
    }
}

@MainActor
private func runRunningArchiveConfirmationTests() {
    withSQLiteRepositoryTest("running archive confirmation test") { _, repository in
        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(repository: repository, engine: engine)

        store.startConversation(prompt: "start running archive", workspacePath: "/tmp/codex-running")
        guard let conversationID = store.snapshot.activeConversation?.id else {
            expect(false, "running archive test creates active conversation")
            return
        }

        let result = store.archiveConversation(conversationID)
        expect(result == .needsStopConfirmation(conversationID), "running archive requires stop confirmation")
        expect(store.snapshot.activeConversation?.state == .running, "conversation stays running before confirmation")

        store.searchArchives("running archive")
        expect(
            !store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
            "running conversation is not archived before confirmation"
        )

        store.confirmPendingStopAndArchive()
        expect(engine.stopCount == 1, "confirming pending archive stops the run first")
        expect(store.snapshot.activeConversation == nil, "confirmed archive clears the active conversation")

        store.searchArchives("running archive")
        expect(
            store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
            "confirmed archive moves running conversation into archives"
        )
    }
}

@MainActor
private func runArchivePersistenceFailureTests() {
    let repository = FailingArchiveRepository()
    let engine = ManualExecutionEngine()
    let store = WorkbenchStore(repository: repository, engine: engine)

    store.createProject(path: "/tmp/failing-archive", displayName: "failing-archive")
    store.startConversation(prompt: "start failure case", workspacePath: "/tmp/failing-archive")
    guard let conversationID = store.snapshot.activeConversation?.id else {
        expect(false, "failing archive test creates active conversation")
        return
    }

    engine.finish(
        conversationID: conversationID,
        result: CodexRunResult(exitCode: 0, stderr: "")
    )
    drainMainRunLoop()
    expect(store.snapshot.activeConversation?.state == .completed, "failing archive setup finishes the conversation")

    let originalTitle = store.snapshot.activeConversation?.title
    let result = store.archiveConversation(conversationID)
    expect(result == .notFound, "archive persistence failure is not reported as archived")
    expect(store.snapshot.activeConversation?.isArchived == false, "failed archive keeps conversation active")
    expect(store.snapshot.projectCards.first?.conversationTitle == originalTitle, "failed archive keeps project card title")

    store.searchArchives("failure case")
    expect(
        !store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
        "failed archive does not become searchable"
    )
}

@MainActor
private func runRunningStopPersistenceFailureTests() {
    let repository = FailingStoppedConversationRepository()
    let engine = ManualExecutionEngine()
    let store = WorkbenchStore(repository: repository, engine: engine)

    store.startConversation(prompt: "start running stop persistence", workspacePath: "/tmp/failing-stop-persistence")
    guard let conversationID = store.snapshot.activeConversation?.id else {
        expect(false, "running stop persistence test creates active conversation")
        return
    }

    let originalTitle = store.snapshot.activeConversation?.title
    let result = store.archiveConversation(conversationID)
    expect(result == .needsStopConfirmation(conversationID), "running stop persistence still needs confirmation")

    store.confirmPendingStopAndArchive()
    expect(engine.stopCount == 0, "failed stop persistence keeps active run handle untouched")
    expect(store.snapshot.activeConversation?.state == .running, "running conversation remains running")
    expect(store.snapshot.activeConversation?.isArchived == false, "failed stop persistence keeps conversation active")

    store.searchArchives("start running stop persistence")
    expect(
        !store.snapshot.archiveSearchResults.contains(where: { $0.conversationID == conversationID }),
        "running stop persistence failure does not produce archive entry"
    )
    expect(store.snapshot.projectCards.first?.conversationTitle == originalTitle, "project card keeps running conversation title after failed stop persistence")
}

private final class ManualExecutionHandle: ExecutionHandle, @unchecked Sendable {
    private let onStop: @Sendable () -> Void

    init(onStop: @escaping @Sendable () -> Void) {
        self.onStop = onStop
    }

    func stop() {
        onStop()
    }
}

private final class ManualExecutionEngine: ExecutionEngine, @unchecked Sendable {
    struct Callbacks {
        let onEvent: @Sendable (CodexEvent) -> Void
        let onFinish: @Sendable (CodexRunResult) -> Void
    }

    var requests: [ExecutionRequest] = []
    var stopCount = 0
    private var callbacksByConversationID: [UUID: Callbacks] = [:]

    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        requests.append(request)
        callbacksByConversationID[request.sessionID] = Callbacks(onEvent: onEvent, onFinish: onFinish)
        onEvent(.raw("Codex CLI 已启动"))
        return ManualExecutionHandle { [weak self] in self?.stopCount += 1 }
    }

    func finish(conversationID: UUID, result: CodexRunResult) {
        callbacksByConversationID[conversationID]?.onFinish(result)
    }
}

private struct ArchivePersistenceFailure: Error {}

private struct StopPersistenceFailure: Error {}

private final class FailingStoppedConversationRepository: CodexPlusRepository, @unchecked Sendable {
    private var projects: [WorkspaceSessionGroup] = []
    private var conversations: [UUID: (projectID: UUID, conversation: ConversationSession)] = [:]

    func saveProject(_ project: WorkspaceSessionGroup) throws {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    func loadProjects() throws -> [WorkspaceSessionGroup] {
        projects
    }

    func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws {
        if conversation.state == .stopped {
            throw StopPersistenceFailure()
        }
        conversations[conversation.id] = (projectID, conversation)
    }

    func loadConversations() throws -> [ConversationSession] {
        conversations.values.map(\.conversation).sorted { $0.createdAt < $1.createdAt }
    }

    func saveArchiveRecord(_ record: ConversationArchiveRecord) throws {
        throw ArchivePersistenceFailure()
    }

    func searchArchiveRecords(query: String) throws -> [ConversationArchiveRecord] {
        []
    }

    func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws {
        // Should never be reached while running stop persistence failure test verifies stop persist path.
    }

    func archiveConversation(record: ConversationArchiveRecord, archiveMarkdownPath: String, archivedAt: Date) throws {
        // Should never be reached while running stop persistence failure test verifies stop persist path.
    }
}

private final class FailingArchiveRepository: CodexPlusRepository, @unchecked Sendable {
    private var projects: [WorkspaceSessionGroup] = []
    private var conversations: [UUID: (projectID: UUID, conversation: ConversationSession)] = [:]
    private var archiveRecords: [ConversationArchiveRecord] = []

    func saveProject(_ project: WorkspaceSessionGroup) throws {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    func loadProjects() throws -> [WorkspaceSessionGroup] {
        projects
    }

    func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws {
        conversations[conversation.id] = (projectID, conversation)
    }

    func loadConversations() throws -> [ConversationSession] {
        conversations.values.map(\.conversation).sorted { $0.createdAt < $1.createdAt }
    }

    func saveArchiveRecord(_ record: ConversationArchiveRecord) throws {
        archiveRecords.append(record)
    }

    func searchArchiveRecords(query: String) throws -> [ConversationArchiveRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return archiveRecords
        }

        return archiveRecords.filter { record in
            [record.title, record.searchableText, record.commandText, record.errorText, record.projectPath]
                .joined(separator: "\n")
                .localizedCaseInsensitiveContains(trimmed)
        }
    }

    func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws {
        throw ArchivePersistenceFailure()
    }

    func archiveConversation(record: ConversationArchiveRecord, archiveMarkdownPath: String, archivedAt: Date) throws {
        throw ArchivePersistenceFailure()
    }
}

@MainActor
private func drainMainRunLoop() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
}

@MainActor
private func withSQLiteRepositoryTest(
    _ name: String,
    body: (URL, SQLiteCodexPlusRepository) throws -> Void
) {
    let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-plus-store-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: dbURL) }

    do {
        let database = try SQLiteDatabase(path: dbURL.path)
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        try body(dbURL, repository)
    } catch {
        expect(false, "\(name) should not throw: \(error)")
    }
}
