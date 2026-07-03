import Foundation

public enum PermissionMode: String, Equatable, Sendable {
    case semiAutomatic
    case fullAccess

    public var displayName: String {
        switch self {
        case .semiAutomatic:
            return "Semi-Automatic"
        case .fullAccess:
            return "Full Access"
        }
    }
}

public enum ConversationRunState: String, Equatable, Sendable {
    case idle
    case running
    case completed
    case failed
    case stopped

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .stopped:
            return true
        case .idle, .running:
            return false
        }
    }
}

public enum SideAttachment: String, Equatable, Sendable {
    case left
    case right

    public mutating func toggle() {
        switch self {
        case .left:
            self = .right
        case .right:
            self = .left
        }
    }
}

public enum ConversationDisplayEvent: Equatable, Identifiable, Sendable {
    case userPrompt(id: UUID, text: String)
    case status(id: UUID, text: String)
    case assistantMessage(id: UUID, text: String)
    case command(id: UUID, executionID: String?, command: String, status: CodexCommandStatus)
    case error(id: UUID, text: String)
    case parseWarning(id: UUID, text: String)

    public var id: UUID {
        switch self {
        case let .userPrompt(id, _),
             let .status(id, _),
             let .assistantMessage(id, _),
             let .error(id, _),
             let .parseWarning(id, _):
            return id
        case let .command(id, _, _, _):
            return id
        }
    }
}

public struct ConversationSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var prompt: String
    public var state: ConversationRunState
    public var permissionMode: PermissionMode
    public var isPinned: Bool
    public var isExplicitlyKept: Bool
    public var events: [ConversationDisplayEvent]

    public init(
        id: UUID = UUID(),
        prompt: String,
        state: ConversationRunState = .idle,
        permissionMode: PermissionMode = .semiAutomatic,
        isPinned: Bool = false,
        isExplicitlyKept: Bool = false,
        events: [ConversationDisplayEvent] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.state = state
        self.permissionMode = permissionMode
        self.isPinned = isPinned
        self.isExplicitlyKept = isExplicitlyKept
        self.events = events
    }
}

public enum ShortcutDecision: Equatable, Sendable {
    case recallExisting(UUID)
    case openFreshEntry
}
