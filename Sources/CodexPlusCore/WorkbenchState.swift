import Foundation

public struct WorkbenchErrorState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var message: String
    public var recoverySuggestion: String?

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        recoverySuggestion: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

public struct WorkbenchState: Equatable, Sendable {
    public var workspaces: [WorkspaceSessionGroup]
    public var conversations: [ConversationSession]
    public var activeWorkspaceID: UUID?
    public var activeConversationID: UUID?
    public var archiveSearchResults: [ConversationArchiveRecord]
    public var openedArchiveConversation: ConversationSession?
    public var isShowingArchiveSearch: Bool
    public var pendingArchiveConfirmationConversationID: UUID?
    public var isPinned: Bool
    public var error: WorkbenchErrorState?

    public static var empty: WorkbenchState {
        WorkbenchState()
    }

    public init(
        workspaces: [WorkspaceSessionGroup] = [],
        conversations: [ConversationSession] = [],
        activeWorkspaceID: UUID? = nil,
        activeConversationID: UUID? = nil,
        archiveSearchResults: [ConversationArchiveRecord] = [],
        openedArchiveConversation: ConversationSession? = nil,
        isShowingArchiveSearch: Bool = false,
        pendingArchiveConfirmationConversationID: UUID? = nil,
        isPinned: Bool = false,
        error: WorkbenchErrorState? = nil
    ) {
        self.workspaces = workspaces
        self.conversations = conversations
        self.activeWorkspaceID = activeWorkspaceID
        self.activeConversationID = activeConversationID
        self.archiveSearchResults = archiveSearchResults
        self.openedArchiveConversation = openedArchiveConversation
        self.isShowingArchiveSearch = isShowingArchiveSearch
        self.pendingArchiveConfirmationConversationID = pendingArchiveConfirmationConversationID
        self.isPinned = isPinned
        self.error = error
    }
}
