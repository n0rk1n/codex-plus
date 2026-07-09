import Foundation

public enum WorkbenchComposerAction: Equatable, Sendable {
    case send
    case stop
}

public struct WorkbenchProjectCard: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var projectName: String
    public var projectPath: String
    public var conversationID: UUID?
    public var conversationTitle: String
    public var conversationState: ConversationRunState?
    public var conversationSummaries: [WorkbenchConversationSummary]
    public var visibleConversationCount: Int
    public var overflowCount: Int?
    public var isActive: Bool

    public init(
        id: UUID,
        projectName: String,
        projectPath: String,
        conversationID: UUID?,
        conversationTitle: String,
        conversationState: ConversationRunState?,
        conversationSummaries: [WorkbenchConversationSummary],
        visibleConversationCount: Int,
        overflowCount: Int?,
        isActive: Bool
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.conversationState = conversationState
        self.conversationSummaries = conversationSummaries
        self.visibleConversationCount = visibleConversationCount
        self.overflowCount = overflowCount
        self.isActive = isActive
    }
}

public struct WorkbenchConversationSummary: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var state: ConversationRunState

    public init(id: UUID, title: String, state: ConversationRunState) {
        self.id = id
        self.title = title
        self.state = state
    }
}

public struct WorkbenchDraftWorkspaceSelection: Equatable, Sendable {
    public var projectName: String
    public var projectPath: String

    public init(projectName: String, projectPath: String) {
        self.projectName = projectName
        self.projectPath = projectPath
    }
}

public struct WorkbenchStatusBarState: Equatable, Sendable {
    public var codexCLIAvailable: Bool
    public var sqliteConnected: Bool
    public var archiveIndexState: String

    public init(codexCLIAvailable: Bool, sqliteConnected: Bool, archiveIndexState: String) {
        self.codexCLIAvailable = codexCLIAvailable
        self.sqliteConnected = sqliteConnected
        self.archiveIndexState = archiveIndexState
    }
}

public struct WorkbenchContextCompressionState: Equatable, Sendable {
    public var conversationID: UUID?
    public var rounds: [CompressionRound]
    public var activeVersions: [CompressionActiveVersion]
    public var timelinePresentation: ConversationTimelineCompressionPresentation
    public var budgetSnapshot: ContextBudgetSnapshot?
    public var sendBlockReason: String?
    public var assembledPreview: String
    public var modelInputPreview: String?
    public var activeOperationDescription: String?

    public init(
        conversationID: UUID? = nil,
        rounds: [CompressionRound] = [],
        activeVersions: [CompressionActiveVersion] = [],
        timelinePresentation: ConversationTimelineCompressionPresentation = ConversationTimelineCompressionPresentation(),
        budgetSnapshot: ContextBudgetSnapshot? = nil,
        sendBlockReason: String? = nil,
        assembledPreview: String = "",
        modelInputPreview: String? = nil,
        activeOperationDescription: String? = nil
    ) {
        self.conversationID = conversationID
        self.rounds = rounds
        self.activeVersions = activeVersions
        self.timelinePresentation = timelinePresentation
        self.budgetSnapshot = budgetSnapshot
        self.sendBlockReason = sendBlockReason
        self.assembledPreview = assembledPreview
        self.modelInputPreview = modelInputPreview
        self.activeOperationDescription = activeOperationDescription
    }
}

public struct WorkbenchSnapshot: Equatable, Sendable {
    public var projectCards: [WorkbenchProjectCard]
    public var selectedDraftWorkspace: WorkbenchDraftWorkspaceSelection?
    public var activeConversation: ConversationSession?
    public var composerAction: WorkbenchComposerAction
    public var statusBar: WorkbenchStatusBarState
    public var canSubmitPrompt: Bool
    public var canStartNewConversation: Bool
    public var archiveSearchResults: [ConversationArchiveRecord]
    public var isPinned: Bool
    public var pendingArchiveConfirmationConversationID: UUID?
    public var isShowingArchiveSearch: Bool
    public var openedArchiveConversation: ConversationSession?
    public var compression: WorkbenchContextCompressionState
    public var error: WorkbenchErrorState?

    public init(
        projectCards: [WorkbenchProjectCard] = [],
        selectedDraftWorkspace: WorkbenchDraftWorkspaceSelection? = nil,
        activeConversation: ConversationSession? = nil,
        composerAction: WorkbenchComposerAction = .send,
        statusBar: WorkbenchStatusBarState = WorkbenchStatusBarState(
            codexCLIAvailable: true,
            sqliteConnected: true,
            archiveIndexState: "ready"
        ),
        canSubmitPrompt: Bool = false,
        canStartNewConversation: Bool = false,
        archiveSearchResults: [ConversationArchiveRecord] = [],
        isPinned: Bool = false,
        pendingArchiveConfirmationConversationID: UUID? = nil,
        isShowingArchiveSearch: Bool = false,
        openedArchiveConversation: ConversationSession? = nil,
        compression: WorkbenchContextCompressionState = WorkbenchContextCompressionState(),
        error: WorkbenchErrorState? = nil
    ) {
        self.projectCards = projectCards
        self.selectedDraftWorkspace = selectedDraftWorkspace
        self.activeConversation = activeConversation
        self.composerAction = composerAction
        self.statusBar = statusBar
        self.canSubmitPrompt = canSubmitPrompt
        self.canStartNewConversation = canStartNewConversation
        self.archiveSearchResults = archiveSearchResults
        self.isPinned = isPinned
        self.pendingArchiveConfirmationConversationID = pendingArchiveConfirmationConversationID
        self.isShowingArchiveSearch = isShowingArchiveSearch
        self.openedArchiveConversation = openedArchiveConversation
        self.compression = compression
        self.error = error
    }
}

public enum ArchiveRequestResult: Equatable, Sendable {
    case archived
    case needsStopConfirmation(UUID)
    case notFound
}
