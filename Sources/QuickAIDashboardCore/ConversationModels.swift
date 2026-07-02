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
}

public struct ConversationSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var prompt: String
    public var state: ConversationRunState
    public var permissionMode: PermissionMode
    public var isPinned: Bool
    public var isExplicitlyKept: Bool

    public init(
        id: UUID = UUID(),
        prompt: String,
        state: ConversationRunState = .idle,
        permissionMode: PermissionMode = .semiAutomatic,
        isPinned: Bool = false,
        isExplicitlyKept: Bool = false
    ) {
        self.id = id
        self.prompt = prompt
        self.state = state
        self.permissionMode = permissionMode
        self.isPinned = isPinned
        self.isExplicitlyKept = isExplicitlyKept
    }
}
