import Combine
import Foundation

@MainActor
public final class WorkbenchStore: ObservableObject {
    @Published public private(set) var snapshot: WorkbenchSnapshot

    private let repository: CodexPlusRepository
    private let archiveService: ArchiveSearchService
    private let lifecycle: ConversationLifecycleService
    private let runOrchestrator: ConversationRunOrchestrator
    private let contextBudgetProvider: (any ContextBudgetProvider)?
    private let defaultWorkspacePathProvider: () throws -> String

    private var workspaces: [WorkspaceSessionGroup]
    private var conversations: [ConversationSession]
    private var activeWorkspaceID: UUID?
    private var activeConversationID: UUID?

    public init(
        repository: CodexPlusRepository,
        engine: ExecutionEngine,
        contextBudgetProvider: (any ContextBudgetProvider)? = nil,
        defaultWorkspacePathProvider: @escaping () throws -> String = {
            try ConversationWorkspacePolicy.createDefaultWorkspaceDirectory()
        }
    ) {
        self.repository = repository
        self.archiveService = ArchiveSearchService(repository: repository)
        let lifecycle = ConversationLifecycleService(
            projectRepository: repository,
            conversationRepository: repository
        )
        self.lifecycle = lifecycle
        self.runOrchestrator = ConversationRunOrchestrator(engine: engine)
        self.contextBudgetProvider = contextBudgetProvider
        self.defaultWorkspacePathProvider = defaultWorkspacePathProvider

        let initialState = (try? lifecycle.loadInitialState()) ?? .empty
        self.workspaces = initialState.workspaces
        self.conversations = initialState.conversations
        self.activeWorkspaceID = initialState.activeWorkspaceID
        self.activeConversationID = initialState.activeConversationID
        self.snapshot = WorkbenchSnapshot()
        refreshSnapshot()
    }

    public func createProject(path: String, displayName: String) {
        let normalizedPath = ConversationWorkspacePolicy.normalizedPath(path)
        let now = Date()

        if let index = workspaces.firstIndex(where: { $0.path == normalizedPath }) {
            var updatedWorkspace = workspaces[index]
            updatedWorkspace.displayName = displayName
            updatedWorkspace.lastActivityAt = now

            guard saveProject(updatedWorkspace) else {
                return
            }

            workspaces[index] = updatedWorkspace
            activeWorkspaceID = updatedWorkspace.id
            refreshSnapshot()
            return
        }

        let project = WorkspaceSessionGroup(
            path: normalizedPath,
            displayName: displayName,
            conversationIDs: [],
            lastActivityAt: now
        )

        guard saveProject(project) else {
            return
        }

        workspaces.append(project)
        activeWorkspaceID = project.id
        refreshSnapshot()
    }

    public func beginNewConversationDraft() {
        if snapshot.activeConversation?.state == .running {
            return
        }

        activeWorkspaceID = nil
        activeConversationID = nil
        snapshot.openedArchiveConversation = nil
        snapshot.isShowingArchiveSearch = false
        refreshSnapshot()
    }

    public func clearDraftWorkspaceSelection() {
        guard activeConversationID == nil else {
            return
        }

        activeWorkspaceID = nil
        refreshSnapshot()
    }

    public func selectProject(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }

        activeWorkspaceID = workspace.id
        activeConversationID = visibleConversations(in: workspace.id).first?.id
        snapshot.openedArchiveConversation = nil
        snapshot.isShowingArchiveSearch = false
        refreshSnapshot()
    }

    public func selectConversation(_ id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id && !$0.isArchived }),
              let workspace = workspace(containing: id) else {
            return
        }

        activeWorkspaceID = workspace.id
        activeConversationID = conversation.id
        snapshot.openedArchiveConversation = nil
        snapshot.isShowingArchiveSearch = false
        refreshSnapshot()
    }

    public func startConversation(prompt: String, workspacePath: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        do {
            let nextState = try lifecycle.createConversation(
                prompt: trimmedPrompt,
                workspacePath: workspacePath,
                in: currentStateFromStore()
            )
            apply(nextState)
        } catch {
            setError(title: "无法创建对话", error: error)
            return
        }

        refreshSnapshot()
        if let conversation = snapshot.activeConversation {
            startEngineRun(for: conversation.id, prompt: conversation.prompt)
        }
    }

    public func submitPrompt(_ prompt: String) {
        if let activeConversationID,
           conversations.contains(where: { $0.id == activeConversationID && !$0.isArchived }) {
            sendFollowUp(prompt)
            return
        }

        let workspacePath: String
        if let activeWorkspace {
            workspacePath = activeWorkspace.path
        } else {
            do {
                workspacePath = try defaultWorkspacePathProvider()
            } catch {
                setError(title: "无法准备工作区", error: error)
                return
            }
        }

        startConversation(prompt: prompt, workspacePath: workspacePath)
    }

    public func sendFollowUp(_ prompt: String) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, let conversationID = activeConversationID else {
            return
        }

        guard let conversation = conversations.first(where: { $0.id == conversationID && !$0.isArchived }) else {
            return
        }

        if conversation.state == .running {
            appendEvent(.error(id: UUID(), text: "任务运行中，当前不能发送新的消息。"), to: conversationID)
            return
        }

        let runPrompt: String
        do {
            runPrompt = try modelInputPrompt(for: conversation, pendingPrompt: trimmedPrompt)
        } catch {
            setError(title: "无法装配压缩上下文", error: error)
            return
        }

        guard persistUpdatedConversation(conversationID, mutation: { session in
            session.state = .running
            session.prompt = trimmedPrompt
            session.events.append(.userPrompt(id: UUID(), text: trimmedPrompt))
        }) else {
            return
        }
        refreshSnapshot()
        startEngineRun(for: conversationID, prompt: runPrompt)
    }

    public func stopActiveRun() {
        guard let conversationID = activeConversationID else {
            return
        }

        _ = stopRun(for: conversationID)
    }

    public func refreshCompressionBudget(
        pendingPrompt: String,
        reservedOutputTokens: Int = 4_096,
        modelName: String? = nil
    ) async {
        guard let contextBudgetProvider,
              let activeConversation = conversations.first(where: { $0.id == activeConversationID && !$0.isArchived }) else {
            refreshSnapshot()
            return
        }

        let assembledInput: String
        do {
            let compressionState = try repository.loadCompressionState(conversationID: activeConversation.id)
            assembledInput = try ContextCompressionAssemblerV2.assemble(
                ContextCompressionAssemblyInput(
                    conversation: activeConversation,
                    compressionState: compressionState,
                    pendingUserPrompt: pendingPrompt
                )
            ).text
        } catch {
            setError(title: "无法测量压缩上下文", error: error)
            return
        }

        let snapshot = await contextBudgetProvider.measure(
            ContextBudgetRequest(
                modelName: modelName,
                assembledInput: assembledInput,
                reservedOutputTokens: reservedOutputTokens,
                workingDirectoryURL: URL(fileURLWithPath: activeConversation.workspacePath, isDirectory: true)
            )
        )

        var compression = self.snapshot.compression
        compression.conversationID = activeConversation.id
        compression.budgetSnapshot = snapshot
        compression.sendBlockReason = snapshot.state == .hardLimit ? "需要压缩后继续" : nil
        compression.assembledPreview = assembledInput
        self.snapshot.compression = compression
        self.snapshot.canSubmitPrompt = activeConversation.state != .running && compression.sendBlockReason == nil
    }

    public func archiveConversation(_ id: UUID) -> ArchiveRequestResult {
        guard let conversation = conversations.first(where: { $0.id == id }) else {
            return .notFound
        }

        if WorkbenchInteractionPolicies.requiresStopBeforeArchive(state: conversation.state) {
            snapshot.pendingArchiveConfirmationConversationID = id
            refreshSnapshot()
            return .needsStopConfirmation(id)
        }

        return archiveConversationNow(id) ? .archived : .notFound
    }

    public func confirmStopAndArchive(_ id: UUID) {
        guard stopRun(for: id) else {
            return
        }

        snapshot.pendingArchiveConfirmationConversationID = nil
        _ = archiveConversationNow(id)
    }

    public func cancelArchiveConfirmation() {
        snapshot.pendingArchiveConfirmationConversationID = nil
        refreshSnapshot()
    }

    public func confirmPendingStopAndArchive() {
        guard let id = snapshot.pendingArchiveConfirmationConversationID else {
            return
        }

        confirmStopAndArchive(id)
    }

    public func clearError() {
        snapshot.error = nil
        refreshSnapshot()
    }

    public func searchArchives(_ query: String) {
        do {
            snapshot.archiveSearchResults = try archiveService.search(query)
        } catch {
            setError(title: "无法搜索归档", error: error)
            snapshot.archiveSearchResults = []
        }
        snapshot.isShowingArchiveSearch = true
        if snapshot.openedArchiveConversation != nil {
            snapshot.openedArchiveConversation = nil
        }
        refreshSnapshot()
    }

    public func openArchive(_ archiveID: UUID) {
        let archivedConversation = conversations.first { $0.id == archiveID && $0.isArchived }
        snapshot.openedArchiveConversation = archivedConversation
        snapshot.isShowingArchiveSearch = true
        refreshSnapshot()
    }

    public func deleteArchive(_ archiveID: UUID) {
        guard conversations.contains(where: { $0.id == archiveID && $0.isArchived }) else {
            snapshot.archiveSearchResults.removeAll { $0.id == archiveID || $0.conversationID == archiveID }
            if snapshot.openedArchiveConversation?.id == archiveID {
                snapshot.openedArchiveConversation = nil
            }
            snapshot.isShowingArchiveSearch = true
            refreshSnapshot()
            return
        }

        do {
            try archiveService.deleteArchive(archiveID)
        } catch {
            setError(title: "无法删除归档", error: error)
            return
        }

        conversations.removeAll { $0.id == archiveID && $0.isArchived }
        for index in workspaces.indices {
            workspaces[index].conversationIDs.removeAll { $0 == archiveID }
        }
        snapshot.archiveSearchResults.removeAll { $0.id == archiveID || $0.conversationID == archiveID }
        if snapshot.openedArchiveConversation?.id == archiveID {
            snapshot.openedArchiveConversation = nil
        }
        snapshot.isShowingArchiveSearch = true
        refreshSnapshot()
    }

    @discardableResult
    public func restoreArchive(_ archiveID: UUID) -> Bool {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == archiveID && $0.isArchived }) else {
            snapshot.archiveSearchResults.removeAll { $0.id == archiveID || $0.conversationID == archiveID }
            if snapshot.openedArchiveConversation?.id == archiveID {
                snapshot.openedArchiveConversation = nil
            }
            snapshot.isShowingArchiveSearch = true
            refreshSnapshot()
            return false
        }

        do {
            try archiveService.restoreArchive(archiveID)
        } catch {
            setError(title: "无法恢复归档", error: error)
            return false
        }

        conversations[conversationIndex].isArchived = false
        let restoredConversation = conversations[conversationIndex]
        if let workspaceIndex = workspaces.firstIndex(where: { $0.path == restoredConversation.workspacePath }),
           !workspaces[workspaceIndex].conversationIDs.contains(archiveID) {
            workspaces[workspaceIndex].conversationIDs.append(archiveID)
            workspaces[workspaceIndex].lastActivityAt = max(
                workspaces[workspaceIndex].lastActivityAt,
                restoredConversation.lastActivityAt
            )
        }

        snapshot.archiveSearchResults.removeAll { $0.id == archiveID || $0.conversationID == archiveID }
        if snapshot.openedArchiveConversation?.id == archiveID {
            snapshot.openedArchiveConversation = nil
        }
        snapshot.isShowingArchiveSearch = true
        refreshSnapshot()
        return true
    }

    public func showArchiveSearch() {
        searchArchives("")
    }

    public func returnToConversationPage() {
        snapshot.openedArchiveConversation = nil
        snapshot.isShowingArchiveSearch = false
        refreshSnapshot()
    }

    public func togglePin() {
        snapshot.isPinned.toggle()
        refreshSnapshot()
    }

    private func startEngineRun(for conversationID: UUID, prompt: String) {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
            return
        }

        do {
            try runOrchestrator.start(
                conversation: conversation,
                prompt: prompt,
                onEvent: { [weak self] event in
                    self?.appendEvent(event, to: conversationID)
                },
                onFinish: { [weak self] result in
                    self?.finishRun(for: conversationID, result: result)
                }
            )
        } catch {
            setError(title: "无法启动 Codex", error: error)
        }
    }

    private func modelInputPrompt(
        for conversation: ConversationSession,
        pendingPrompt: String
    ) throws -> String {
        let compressionState = try repository.loadCompressionState(conversationID: conversation.id)
        guard !compressionState.activeVersions.isEmpty else {
            return pendingPrompt
        }

        return try ContextCompressionAssemblerV2.assemble(
            ContextCompressionAssemblyInput(
                conversation: conversation,
                compressionState: compressionState,
                pendingUserPrompt: pendingPrompt
            )
        ).text
    }

    private func finishRun(for conversationID: UUID, result: CodexRunResult) {
        guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
            return
        }

        guard conversation.state == .running else {
            refreshSnapshot()
            return
        }

        guard persistUpdatedConversation(conversationID, mutation: { session in
            session.state = result.succeeded ? .completed : .failed
            if !result.succeeded, !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.events.append(.error(id: UUID(), text: result.stderr))
            }
        }) else {
            return
        }
        refreshSnapshot()
    }

    @discardableResult
    private func stopRun(for conversationID: UUID) -> Bool {
        guard runOrchestrator.isRunning(conversationID: conversationID) else {
            return false
        }

        guard persistUpdatedConversation(conversationID, mutation: { session in
            session.state = .stopped
        }) else {
            setError(title: "无法停止任务", message: "对话状态保存失败，任务仍在运行。")
            return false
        }

        _ = runOrchestrator.stop(conversationID: conversationID)
        refreshSnapshot()
        return true
    }

    @discardableResult
    private func archiveConversationNow(_ id: UUID) -> Bool {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == id }),
              let workspaceIndex = workspaces.firstIndex(where: { $0.conversationIDs.contains(id) })
        else {
            return false
        }

        let conversation = conversations[conversationIndex]
        let workspace = workspaces[workspaceIndex]

        do {
            _ = try archiveService.archive(conversation: conversation, project: workspace)
        } catch {
            return false
        }

        var updatedConversations = conversations
        var updatedWorkspaces = workspaces
        updatedConversations[conversationIndex].isArchived = true
        updatedWorkspaces[workspaceIndex].conversationIDs.removeAll { $0 == id }

        var nextActiveWorkspaceID = activeWorkspaceID
        var nextActiveConversationID = activeConversationID == id ? nil : activeConversationID

        if nextActiveWorkspaceID == nil {
            nextActiveWorkspaceID = workspace.id
        }

        if let workspaceID = nextActiveWorkspaceID {
            let visibleConversationIDs = updatedWorkspaces
                .first(where: { $0.id == workspaceID })?
                .conversationIDs
                .filter { candidateID in
                    updatedConversations.contains(where: { $0.id == candidateID && !$0.isArchived })
                } ?? []

            if nextActiveConversationID == nil || !visibleConversationIDs.contains(nextActiveConversationID!) {
                nextActiveConversationID = visibleConversationIDs.first
            }
        }

        conversations = updatedConversations
        workspaces = updatedWorkspaces
        activeWorkspaceID = nextActiveWorkspaceID
        activeConversationID = nextActiveConversationID
        snapshot.pendingArchiveConfirmationConversationID = nil
        refreshSnapshot()
        return true
    }

    private func ensureProject(for workspacePath: String) -> WorkspaceSessionGroup? {
        let normalizedPath = ConversationWorkspacePolicy.normalizedPath(workspacePath)

        if let workspace = workspaces.first(where: { $0.path == normalizedPath }) {
            return workspace
        }

        let workspace = WorkspaceSessionGroup(
            path: normalizedPath,
            displayName: ConversationWorkspacePolicy.displayName(for: normalizedPath),
            conversationIDs: [],
            lastActivityAt: Date()
        )

        guard saveProject(workspace) else {
            return nil
        }

        workspaces.append(workspace)
        return workspace
    }

    private func workspace(containing conversationID: UUID) -> WorkspaceSessionGroup? {
        workspaces.first { $0.conversationIDs.contains(conversationID) }
    }

    private func visibleConversations(in workspaceID: UUID) -> [ConversationSession] {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return []
        }

        return workspace.conversationIDs.compactMap { id in
            conversations.first { $0.id == id && !$0.isArchived }
        }
    }

    private var activeWorkspace: WorkspaceSessionGroup? {
        guard let activeWorkspaceID else {
            return nil
        }

        return workspaces.first { $0.id == activeWorkspaceID }
    }

    private func currentStateFromStore() -> WorkbenchState {
        WorkbenchState(
            workspaces: workspaces,
            conversations: conversations,
            activeWorkspaceID: activeWorkspaceID,
            activeConversationID: activeConversationID,
            archiveSearchResults: snapshot.archiveSearchResults,
            openedArchiveConversation: snapshot.openedArchiveConversation,
            isShowingArchiveSearch: snapshot.isShowingArchiveSearch,
            pendingArchiveConfirmationConversationID: snapshot.pendingArchiveConfirmationConversationID,
            isPinned: snapshot.isPinned,
            error: snapshot.error
        )
    }

    private func apply(_ state: WorkbenchState) {
        workspaces = state.workspaces
        conversations = state.conversations
        activeWorkspaceID = state.activeWorkspaceID
        activeConversationID = state.activeConversationID
        snapshot.archiveSearchResults = state.archiveSearchResults
        snapshot.openedArchiveConversation = state.openedArchiveConversation
        snapshot.isShowingArchiveSearch = state.isShowingArchiveSearch
        snapshot.pendingArchiveConfirmationConversationID = state.pendingArchiveConfirmationConversationID
        snapshot.isPinned = state.isPinned
        snapshot.error = state.error
    }

    private func setError(title: String, error: Error, recoverySuggestion: String? = nil) {
        setError(
            title: title,
            message: String(describing: error),
            recoverySuggestion: recoverySuggestion
        )
    }

    private func setError(title: String, message: String, recoverySuggestion: String? = nil) {
        snapshot.error = WorkbenchErrorState(
            title: title,
            message: message,
            recoverySuggestion: recoverySuggestion
        )
        refreshSnapshot()
    }

    private func appendEvent(_ event: ConversationDisplayEvent, to conversationID: UUID) {
        guard persistUpdatedConversation(conversationID, mutation: { session in
            session.events.append(event)
        }) else {
            return
        }

        refreshSnapshot()
    }

    @discardableResult
    private func persistUpdatedConversation(
        _ id: UUID,
        mutation: (inout ConversationSession) -> Void
    ) -> Bool {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let now = Date()
        var updatedConversation = conversations[index]
        mutation(&updatedConversation)
        updatedConversation.lastActivityAt = now

        var updatedWorkspaces = workspaces
        if let workspaceIndex = updatedWorkspaces.firstIndex(where: { $0.path == updatedConversation.workspacePath }) {
            updatedWorkspaces[workspaceIndex].lastActivityAt = updatedConversation.lastActivityAt
            guard saveProject(updatedWorkspaces[workspaceIndex]) else {
                return false
            }
        }

        guard let projectID = updatedWorkspaces.first(where: { $0.path == updatedConversation.workspacePath })?.id,
              saveConversation(updatedConversation, projectID: projectID) else {
            return false
        }

        workspaces = updatedWorkspaces
        conversations[index] = updatedConversation
        return true
    }

    private func attachedWorkspaces(
        adding conversationID: UUID,
        to workspaceID: UUID,
        now: Date
    ) -> [WorkspaceSessionGroup]? {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return nil
        }

        var updatedWorkspaces = workspaces
        updatedWorkspaces[index].conversationIDs.append(conversationID)
        updatedWorkspaces[index].lastActivityAt = now

        guard saveProject(updatedWorkspaces[index]) else {
            return nil
        }

        return updatedWorkspaces
    }

    private func saveProject(_ project: WorkspaceSessionGroup) -> Bool {
        do {
            try repository.saveProject(project)
            return true
        } catch {
            setError(title: "无法保存项目", error: error)
            return false
        }
    }

    private func saveConversation(_ conversation: ConversationSession, projectID: UUID) -> Bool {
        do {
            try repository.saveConversation(conversation, projectID: projectID)
            return true
        } catch {
            setError(title: "无法保存对话", error: error)
            return false
        }
    }

    private func refreshSnapshot() {
        let activeConversation = conversations.first { $0.id == activeConversationID && !$0.isArchived }
        let selectedDraftWorkspace = activeConversation == nil ? activeWorkspace.map {
            WorkbenchDraftWorkspaceSelection(projectName: $0.displayName, projectPath: $0.path)
        } : nil
        let compression = compressionSnapshotState(for: activeConversation)

        snapshot = WorkbenchSnapshot(
            projectCards: WorkbenchProjection.projectCards(
                workspaces: workspaces,
                conversations: conversations,
                activeWorkspaceID: activeWorkspaceID,
                activeConversationID: activeConversationID
            ),
            selectedDraftWorkspace: selectedDraftWorkspace,
            activeConversation: activeConversation,
            composerAction: WorkbenchInteractionPolicies.composerAction(for: activeConversation?.state),
            statusBar: snapshot.statusBar,
            canSubmitPrompt: activeConversation?.state != .running,
            canStartNewConversation: WorkbenchInteractionPolicies.canStartNewConversation(
                activeConversationState: activeConversation?.state
            ),
            archiveSearchResults: snapshot.archiveSearchResults,
            isPinned: snapshot.isPinned,
            pendingArchiveConfirmationConversationID: snapshot.pendingArchiveConfirmationConversationID,
            isShowingArchiveSearch: snapshot.isShowingArchiveSearch,
            openedArchiveConversation: snapshot.openedArchiveConversation,
            compression: compression,
            error: snapshot.error
        )
    }

    private func compressionSnapshotState(
        for conversation: ConversationSession?
    ) -> WorkbenchContextCompressionState {
        guard let conversation else {
            return WorkbenchContextCompressionState()
        }

        do {
            let compressionState = try repository.loadCompressionState(conversationID: conversation.id)
            let assembledPreview = try ContextCompressionAssemblerV2.assemble(
                ContextCompressionAssemblyInput(
                    conversation: conversation,
                    compressionState: compressionState
                )
            ).text
            let canReusePreviousBudget = snapshot.compression.conversationID == conversation.id
            return WorkbenchContextCompressionState(
                conversationID: conversation.id,
                rounds: compressionState.rounds,
                activeVersions: compressionState.activeVersions,
                budgetSnapshot: canReusePreviousBudget ? snapshot.compression.budgetSnapshot : nil,
                sendBlockReason: canReusePreviousBudget ? snapshot.compression.sendBlockReason : nil,
                assembledPreview: assembledPreview,
                activeOperationDescription: activeOperationDescription(in: compressionState)
            )
        } catch {
            return WorkbenchContextCompressionState(
                sendBlockReason: "无法读取压缩状态",
                activeOperationDescription: String(describing: error)
            )
        }
    }

    private func activeOperationDescription(
        in state: ConversationCompressionState
    ) -> String? {
        let versionsByID = Dictionary(uniqueKeysWithValues: state.versions.map { ($0.id, $0) })
        let operations = state.activeVersions.compactMap { active in
            versionsByID[active.activeVersionID]?.operation.rawValue
        }
        guard !operations.isEmpty else {
            return nil
        }
        return operations.joined(separator: ",")
    }
}
