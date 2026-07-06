import Foundation

public enum WorkbenchDomainError: Error, Equatable, CustomStringConvertible {
    case persistenceFailed(String)
    case conversationNotFound(UUID)
    case workspaceNotFound(String)

    public var description: String {
        switch self {
        case let .persistenceFailed(message):
            return message
        case let .conversationNotFound(id):
            return "Conversation not found: \(id)"
        case let .workspaceNotFound(path):
            return "Workspace not found: \(path)"
        }
    }
}

public final class ConversationLifecycleService: @unchecked Sendable {
    private let projectRepository: ProjectRepository
    private let conversationRepository: ConversationRepository
    private var titleGenerator: ConversationTitleGenerator

    public init(
        projectRepository: ProjectRepository,
        conversationRepository: ConversationRepository,
        titleGenerator: ConversationTitleGenerator = ConversationTitleGenerator()
    ) {
        self.projectRepository = projectRepository
        self.conversationRepository = conversationRepository
        self.titleGenerator = titleGenerator
    }

    public func loadInitialState() throws -> WorkbenchState {
        let workspaces = try projectRepository.loadProjects()
        let conversations = try conversationRepository.loadConversations()
        let state = WorkbenchState(workspaces: workspaces, conversations: conversations)
        return ProjectSelectionPolicy.repairActiveSelection(in: state)
    }

    public func createConversation(
        prompt: String,
        workspacePath: String,
        in state: WorkbenchState
    ) throws -> WorkbenchState {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return state
        }

        let normalizedPath = ConversationWorkspacePolicy.normalizedPath(workspacePath)
        let now = Date()
        var next = state
        let workspace = next.workspaces.first(where: { $0.path == normalizedPath }) ?? WorkspaceSessionGroup(
            path: normalizedPath,
            displayName: ConversationWorkspacePolicy.displayName(for: normalizedPath),
            conversationIDs: [],
            lastActivityAt: now
        )

        let session = ConversationSession(
            title: titleGenerator.nextTitle(existingTitles: next.conversations.map(\.title)),
            prompt: trimmedPrompt,
            workspacePath: normalizedPath,
            state: .running,
            permissionMode: .semiAutomatic,
            createdAt: now,
            lastActivityAt: now,
            events: [.userPrompt(id: UUID(), text: trimmedPrompt)]
        )

        var updatedWorkspace = workspace
        if !updatedWorkspace.conversationIDs.contains(session.id) {
            updatedWorkspace.conversationIDs.append(session.id)
        }
        updatedWorkspace.lastActivityAt = now

        do {
            try projectRepository.saveProject(updatedWorkspace)
            try conversationRepository.saveConversation(session, projectID: updatedWorkspace.id)
        } catch {
            throw WorkbenchDomainError.persistenceFailed(String(describing: error))
        }

        next.workspaces.removeAll { $0.id == updatedWorkspace.id }
        next.workspaces.append(updatedWorkspace)
        next.conversations.append(session)
        next.activeWorkspaceID = updatedWorkspace.id
        next.activeConversationID = session.id
        next.isShowingArchiveSearch = false
        next.openedArchiveConversation = nil
        return next
    }
}
