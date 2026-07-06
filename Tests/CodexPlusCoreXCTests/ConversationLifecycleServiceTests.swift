import XCTest
@testable import CodexPlusCore

final class ConversationLifecycleServiceTests: XCTestCase {
    func testCreateConversationPersistsProjectAndConversation() throws {
        let repository = MemoryLifecycleRepository()
        let service = ConversationLifecycleService(
            projectRepository: repository,
            conversationRepository: repository,
            titleGenerator: ConversationTitleGenerator(randomSuffixes: [1234])
        )

        let state = try service.createConversation(
            prompt: "build it",
            workspacePath: "/tmp/codex-plus",
            in: .empty
        )

        XCTAssertEqual(state.workspaces.count, 1)
        XCTAssertEqual(state.conversations.count, 1)
        XCTAssertEqual(state.activeConversationID, state.conversations.first?.id)
        XCTAssertEqual(repository.savedProjects.count, 1)
        XCTAssertEqual(repository.savedConversations.count, 1)
        XCTAssertEqual(state.conversations.first?.state, .running)
    }

    func testSaveFailureDoesNotMutateState() {
        let repository = MemoryLifecycleRepository()
        repository.failSavingConversations = true
        let service = ConversationLifecycleService(
            projectRepository: repository,
            conversationRepository: repository,
            titleGenerator: ConversationTitleGenerator(randomSuffixes: [1234])
        )

        XCTAssertThrowsError(
            try service.createConversation(prompt: "build it", workspacePath: "/tmp/codex-plus", in: .empty)
        )
        XCTAssertTrue(repository.conversations.isEmpty)
    }
}

private final class MemoryLifecycleRepository: ProjectRepository, ConversationRepository, @unchecked Sendable {
    var projects: [WorkspaceSessionGroup] = []
    var conversations: [ConversationSession] = []
    var savedProjects: [WorkspaceSessionGroup] = []
    var savedConversations: [ConversationSession] = []
    var failSavingConversations = false

    func saveProject(_ project: WorkspaceSessionGroup) throws {
        savedProjects.append(project)
        projects.removeAll { $0.id == project.id }
        projects.append(project)
    }

    func loadProjects() throws -> [WorkspaceSessionGroup] {
        projects
    }

    func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws {
        if failSavingConversations {
            throw WorkbenchDomainError.persistenceFailed("save conversation failed")
        }

        savedConversations.append(conversation)
        conversations.removeAll { $0.id == conversation.id }
        conversations.append(conversation)
    }

    func loadConversations() throws -> [ConversationSession] {
        conversations
    }

    func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }

        conversations[index].isArchived = true
    }
}
