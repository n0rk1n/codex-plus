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

public extension ConversationDisplayEvent {
    public var isTechnicalTimelineEvent: Bool {
        switch self {
        case .status, .command, .parseWarning:
            return true
        case .userPrompt, .assistantMessage, .error:
            return false
        }
    }

    public var isStatusTimelineEvent: Bool {
        if case .status = self {
            return true
        }

        return false
    }

    public var isCommandTimelineEvent: Bool {
        if case .command = self {
            return true
        }

        return false
    }

    public var isParseWarningTimelineEvent: Bool {
        if case .parseWarning = self {
            return true
        }

        return false
    }
}

public struct ConversationSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var prompt: String
    public var workspacePath: String
    public var state: ConversationRunState
    public var permissionMode: PermissionMode
    public var isPinned: Bool
    public var isExplicitlyKept: Bool
    public var isArchived: Bool
    public var createdAt: Date
    public var lastActivityAt: Date
    public var events: [ConversationDisplayEvent]

    public init(
        id: UUID = UUID(),
        title: String = ConversationTitleGenerator.title(randomSuffix: Int.random(in: 1000...9999)),
        prompt: String,
        workspacePath: String = ".",
        state: ConversationRunState = .idle,
        permissionMode: PermissionMode = .semiAutomatic,
        isPinned: Bool = false,
        isExplicitlyKept: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        events: [ConversationDisplayEvent] = []
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.workspacePath = workspacePath
        self.state = state
        self.permissionMode = permissionMode
        self.isPinned = isPinned
        self.isExplicitlyKept = isExplicitlyKept
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.events = events
    }
}

public struct WorkspaceSessionGroup: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var path: String
    public var displayName: String
    public var conversationIDs: [UUID]
    public var lastActivityAt: Date

    public init(
        id: UUID = UUID(),
        path: String,
        displayName: String,
        conversationIDs: [UUID] = [],
        lastActivityAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.conversationIDs = conversationIDs
        self.lastActivityAt = lastActivityAt
    }
}

public struct ConversationDraft: Equatable, Sendable {
    public var selectedWorkspacePath: String?
    public var prompt: String
    public var errorMessage: String?

    public init(
        selectedWorkspacePath: String? = nil,
        prompt: String = "",
        errorMessage: String? = nil
    ) {
        self.selectedWorkspacePath = selectedWorkspacePath
        self.prompt = prompt
        self.errorMessage = errorMessage
    }
}

public struct ConversationArchiveResult: Equatable, Sendable {
    public var archivedConversationID: UUID
    public var activeWorkspaceID: UUID?
    public var activeConversationID: UUID?

    public init(archivedConversationID: UUID, activeWorkspaceID: UUID?, activeConversationID: UUID?) {
        self.archivedConversationID = archivedConversationID
        self.activeWorkspaceID = activeWorkspaceID
        self.activeConversationID = activeConversationID
    }
}

public enum ConversationWorkspacePolicy {
    public static let defaultParentDirectoryName = ApplicationSupportPaths.workspacesDirectoryName

    public static func defaultParentPath(homeDirectoryPath: String) -> String {
        URL(fileURLWithPath: ApplicationSupportPaths.rootDirectoryPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true)
            .appendingPathComponent(defaultParentDirectoryName, isDirectory: true)
            .path
    }

    public static func defaultDateDirectoryName(
        date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let calendar = calendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func defaultRandomDirectoryName(randomSuffix: Int) -> String {
        String(format: "%04d", randomSuffix)
    }

    public static func defaultWorkspacePath(
        homeDirectoryPath: String,
        date: Date,
        randomSuffix: Int,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        URL(fileURLWithPath: defaultParentPath(homeDirectoryPath: homeDirectoryPath), isDirectory: true)
            .appendingPathComponent(defaultDateDirectoryName(date: date, calendar: calendar), isDirectory: true)
            .appendingPathComponent(defaultRandomDirectoryName(randomSuffix: randomSuffix), isDirectory: true)
            .path
    }

    public static func createDefaultWorkspaceDirectory(
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        date: Date = Date(),
        randomSuffixes: [Int]? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian),
        fileManager: FileManager = .default
    ) throws -> String {
        let suffixes = randomSuffixes ?? (0..<20).map { _ in Int.random(in: 1000...9999) }

        for suffix in suffixes {
            let path = defaultWorkspacePath(
                homeDirectoryPath: homeDirectoryPath,
                date: date,
                randomSuffix: suffix,
                calendar: calendar
            )
            let url = URL(fileURLWithPath: path, isDirectory: true)

            if !fileManager.fileExists(atPath: url.path) {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                return normalizedPath(url.path)
            }
        }

        throw CocoaError(.fileWriteFileExists)
    }

    public static func normalizedPath(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        return NSString(string: expanded).standardizingPath
    }

    public static func displayName(for path: String) -> String {
        let name = URL(fileURLWithPath: normalizedPath(path)).lastPathComponent
        return name.isEmpty ? normalizedPath(path) : name
    }
}

public struct ConversationTitleGenerator: Sendable {
    private var randomSuffixes: [Int]

    public init(randomSuffixes: [Int] = []) {
        self.randomSuffixes = randomSuffixes
    }

    public mutating func nextTitle(existingTitles: [String]) -> String {
        let existing = Set(existingTitles)

        while true {
            let suffix = nextSuffix()
            let title = Self.title(randomSuffix: suffix)
            if !existing.contains(title) {
                return title
            }
        }
    }

    public static func title(randomSuffix: Int) -> String {
        "对话_\(String(format: "%04d", randomSuffix))"
    }

    private mutating func nextSuffix() -> Int {
        if !randomSuffixes.isEmpty {
            return randomSuffixes.removeFirst()
        }

        return Int.random(in: 1000...9999)
    }
}
