import Combine
import Foundation

@MainActor
public final class ConversationCoordinator: ObservableObject {
    public static let maxStoredEvents = 500

    @Published public private(set) var workspaces: [WorkspaceSessionGroup] = []
    @Published public private(set) var conversations: [ConversationSession] = []
    @Published public private(set) var activeWorkspaceID: UUID?
    @Published public private(set) var activeConversationID: UUID?
    @Published public private(set) var draft: ConversationDraft?
    @Published public private(set) var preferredSide: SideAttachment = .right

    private var titleGenerator: ConversationTitleGenerator

    public init(titleGenerator: ConversationTitleGenerator = ConversationTitleGenerator()) {
        self.titleGenerator = titleGenerator
    }

    public var snapshot: ConversationCoordinatorSnapshot {
        ConversationCoordinatorSnapshot(
            workspaces: workspaces,
            conversations: conversations,
            activeWorkspaceID: activeWorkspaceID,
            activeConversationID: activeConversationID,
            draft: draft
        )
    }

    public var activeConversation: ConversationSession? {
        guard let activeConversationID else {
            return nil
        }

        return conversations.first { $0.id == activeConversationID && !$0.isArchived }
    }

    public func conversation(with id: UUID) -> ConversationSession? {
        conversations.first { $0.id == id }
    }

    @discardableResult
    public func startConversation(
        prompt: String,
        workspacePath: String = ".",
        now: Date = Date()
    ) -> ConversationSession {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = ConversationWorkspacePolicy.normalizedPath(workspacePath)
        let title = titleGenerator.nextTitle(existingTitles: conversations.map(\.title))
        let session = ConversationSession(
            title: title,
            prompt: trimmedPrompt,
            workspacePath: normalizedPath,
            state: .idle,
            permissionMode: .semiAutomatic,
            createdAt: now,
            lastActivityAt: now,
            events: [
                .userPrompt(id: UUID(), text: trimmedPrompt)
            ]
        )

        conversations.append(session)
        attachConversation(session.id, toWorkspacePath: normalizedPath, now: now)
        activeConversationID = session.id
        draft = nil
        return session
    }

    public func shortcutDecision() -> ShortcutDecision {
        if let activeConversation {
            return .recallConversation(activeConversation.id)
        }

        if let visibleConversation = conversations.first(where: { !$0.isArchived }) {
            return .recallConversation(visibleConversation.id)
        }

        return .openFreshEntry
    }

    public func beginDraft(selectedWorkspacePath: String? = nil, prompt: String = "") {
        draft = ConversationDraft(
            selectedWorkspacePath: selectedWorkspacePath.map(ConversationWorkspacePolicy.normalizedPath),
            prompt: prompt
        )
        activeConversationID = nil
    }

    public func setDraftWorkspacePath(_ path: String?) {
        var nextDraft = draft ?? ConversationDraft()
        nextDraft.selectedWorkspacePath = path.map(ConversationWorkspacePolicy.normalizedPath)
        nextDraft.errorMessage = nil
        draft = nextDraft
    }

    public func setDraftPrompt(_ prompt: String) {
        var nextDraft = draft ?? ConversationDraft()
        nextDraft.prompt = prompt
        nextDraft.errorMessage = nil
        draft = nextDraft
    }

    public func setDraftError(_ message: String) {
        var nextDraft = draft ?? ConversationDraft()
        nextDraft.errorMessage = message
        draft = nextDraft
    }

    public func selectWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else {
            return
        }

        activeWorkspaceID = workspace.id
        activeConversationID = visibleConversations(in: workspace.id).first?.id
        draft = nil
    }

    public func selectConversation(_ id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id && !$0.isArchived }),
              let workspace = workspaces.first(where: { $0.path == conversation.workspacePath })
        else {
            return
        }

        activeWorkspaceID = workspace.id
        activeConversationID = conversation.id
        draft = nil
    }

    public func visibleConversations(in workspaceID: UUID) -> [ConversationSession] {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return []
        }

        return workspace.conversationIDs.compactMap { id in
            conversations.first { $0.id == id && !$0.isArchived }
        }
    }

    public func markRunning(_ id: UUID, now: Date = Date()) {
        updateConversation(id, now: now) { session in
            session.state = .running
        }
    }

    public func markCompleted(_ id: UUID, now: Date = Date()) {
        markTerminal(id, state: .completed, now: now)
    }

    public func markFailed(_ id: UUID, now: Date = Date()) {
        markFailed(id, message: "Conversation failed", now: now)
    }

    public func markFailed(_ id: UUID, message: String, now: Date = Date()) {
        updateConversation(id, now: now) { session in
            session.state = .failed
            session.permissionMode = .semiAutomatic
            session.events.append(.error(id: UUID(), text: message))
            Self.trimEvents(&session.events)
        }
    }

    public func markStopped(_ id: UUID, now: Date = Date()) {
        markTerminal(id, state: .stopped, now: now)
    }

    public func setPermissionMode(_ permissionMode: PermissionMode, for id: UUID) {
        updateConversation(id) { session in
            session.permissionMode = permissionMode
        }
    }

    public func setPinned(_ isPinned: Bool, for id: UUID) {
        updateConversation(id) { session in
            session.isPinned = isPinned
        }
    }

    public func setExplicitlyKept(_ isExplicitlyKept: Bool, for id: UUID) {
        updateConversation(id) { session in
            session.isExplicitlyKept = isExplicitlyKept
        }
    }

    public func togglePreferredSide() {
        preferredSide.toggle()
    }

    public func appendUserPrompt(_ prompt: String, to id: UUID, now: Date = Date()) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        updateConversation(id, now: now) { session in
            session.events.append(.userPrompt(id: UUID(), text: trimmedPrompt))
            Self.trimEvents(&session.events)
        }
    }

    public func appendCodexEvent(_ event: CodexEvent, to id: UUID, now: Date = Date()) {
        updateConversation(id, now: now) { session in
            session.events.append(Self.displayEvent(from: event))
            Self.trimEvents(&session.events)
        }
    }

    public func closeConversation(_ id: UUID) {
        guard activeConversationID == id else {
            return
        }

        activeConversationID = nil
    }

    public func reorderWorkspace(_ id: UUID, to targetIndex: Int) {
        guard let sourceIndex = workspaces.firstIndex(where: { $0.id == id }),
              workspaces.indices.contains(targetIndex),
              sourceIndex != targetIndex
        else {
            return
        }

        let workspace = workspaces.remove(at: sourceIndex)
        workspaces.insert(workspace, at: targetIndex)
    }

    public func reorderConversation(_ id: UUID, to targetIndex: Int) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.conversationIDs.contains(id) }) else {
            return
        }

        var ids = workspaces[workspaceIndex].conversationIDs
        guard let sourceIndex = ids.firstIndex(of: id),
              ids.indices.contains(targetIndex),
              sourceIndex != targetIndex
        else {
            return
        }

        let conversationID = ids.remove(at: sourceIndex)
        ids.insert(conversationID, at: targetIndex)
        workspaces[workspaceIndex].conversationIDs = ids
    }

    @discardableResult
    public func archiveConversation(_ id: UUID, now: Date = Date()) -> ConversationArchiveResult? {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == id }),
              let workspaceIndex = workspaces.firstIndex(where: { $0.path == conversations[conversationIndex].workspacePath })
        else {
            return nil
        }

        let archivedWorkspaceID = workspaces[workspaceIndex].id
        let wasDraftActive = draft != nil && activeConversationID == nil
        let neighborID = archiveFallbackNeighbor(
            archivedID: id,
            conversationIDs: workspaces[workspaceIndex].conversationIDs
        )

        conversations[conversationIndex].isArchived = true
        conversations[conversationIndex].lastActivityAt = now
        workspaces[workspaceIndex].conversationIDs.removeAll { $0 == id }

        if workspaces[workspaceIndex].conversationIDs.isEmpty {
            workspaces.remove(at: workspaceIndex)
        }

        if activeConversationID == id {
            if let neighborID, conversations.contains(where: { $0.id == neighborID && !$0.isArchived }) {
                selectConversation(neighborID)
            } else if let nextWorkspace = workspaces.max(by: { $0.lastActivityAt < $1.lastActivityAt }) {
                selectWorkspace(nextWorkspace.id)
            } else {
                activeWorkspaceID = nil
                activeConversationID = nil
                if !wasDraftActive {
                    draft = nil
                }
            }
        } else if workspaces.isEmpty {
            activeWorkspaceID = nil
            activeConversationID = nil
            if !wasDraftActive {
                draft = nil
            }
        } else if activeWorkspaceID == archivedWorkspaceID {
            let nextWorkspaceID = workspaces.max(by: { $0.lastActivityAt < $1.lastActivityAt })?.id
            activeWorkspaceID = nextWorkspaceID
            if !wasDraftActive {
                activeConversationID = nextWorkspaceID.flatMap { visibleConversations(in: $0).first?.id }
            }
        }

        return ConversationArchiveResult(
            archivedConversationID: id,
            activeWorkspaceID: activeWorkspaceID,
            activeConversationID: activeConversationID
        )
    }

    private func markTerminal(_ id: UUID, state: ConversationRunState, now: Date = Date()) {
        updateConversation(id, now: now) { session in
            session.state = state
            session.permissionMode = .semiAutomatic
        }
    }

    private func attachConversation(_ conversationID: UUID, toWorkspacePath path: String, now: Date) {
        if let workspaceIndex = workspaces.firstIndex(where: { $0.path == path }) {
            workspaces[workspaceIndex].conversationIDs.append(conversationID)
            workspaces[workspaceIndex].lastActivityAt = now
            activeWorkspaceID = workspaces[workspaceIndex].id
            return
        }

        let workspace = WorkspaceSessionGroup(
            path: path,
            displayName: ConversationWorkspacePolicy.displayName(for: path),
            conversationIDs: [conversationID],
            lastActivityAt: now
        )
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
    }

    private func updateConversation(
        _ id: UUID,
        now: Date = Date(),
        _ update: (inout ConversationSession) -> Void
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }

        update(&conversations[index])
        conversations[index].lastActivityAt = now
        touchWorkspace(for: conversations[index], now: now)
    }

    private func touchWorkspace(for conversation: ConversationSession, now: Date) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.path == conversation.workspacePath }) else {
            return
        }

        workspaces[workspaceIndex].lastActivityAt = now
    }

    private func archiveFallbackNeighbor(archivedID: UUID, conversationIDs: [UUID]) -> UUID? {
        guard let index = conversationIDs.firstIndex(of: archivedID) else {
            return nil
        }

        let leftID = index > 0 ? conversationIDs[index - 1] : nil
        let rightIndex = conversationIDs.index(after: index)
        let rightID = conversationIDs.indices.contains(rightIndex) ? conversationIDs[rightIndex] : nil

        switch (leftID.flatMap(conversation(with:)), rightID.flatMap(conversation(with:))) {
        case let (left?, right?):
            return left.lastActivityAt >= right.lastActivityAt ? left.id : right.id
        case let (left?, nil):
            return left.id
        case let (nil, right?):
            return right.id
        case (nil, nil):
            return nil
        }
    }

    private static func displayEvent(from event: CodexEvent) -> ConversationDisplayEvent {
        switch event {
        case let .threadStarted(threadID):
            return .status(id: UUID(), text: "Thread started: \(threadID)")
        case .turnStarted:
            return .status(id: UUID(), text: "Turn started")
        case .turnCompleted:
            return .status(id: UUID(), text: "Turn completed")
        case let .turnFailed(message):
            return .error(id: UUID(), text: message)
        case let .agentMessage(text):
            return .assistantMessage(id: UUID(), text: text)
        case let .command(executionID, command, status):
            return .command(id: UUID(), executionID: executionID, command: command, status: status)
        case let .error(message):
            return .error(id: UUID(), text: message)
        case let .raw(text):
            return .status(id: UUID(), text: text)
        case let .parseWarning(text):
            return .parseWarning(id: UUID(), text: text)
        }
    }

    private static func trimEvents(_ events: inout [ConversationDisplayEvent]) {
        guard events.count > maxStoredEvents else {
            return
        }

        events = Array(events.suffix(maxStoredEvents))
    }
}
