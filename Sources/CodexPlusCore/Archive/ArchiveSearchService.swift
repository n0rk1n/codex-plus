import Foundation

public struct ConversationArchiveRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: UUID
    public var projectID: UUID
    public var title: String
    public var searchableText: String
    public var commandText: String
    public var errorText: String
    public var projectPath: String
    public var archivedAt: Date

    public init(
        id: UUID,
        conversationID: UUID,
        projectID: UUID,
        title: String,
        searchableText: String,
        commandText: String,
        errorText: String,
        projectPath: String,
        archivedAt: Date
    ) {
        self.id = id
        self.conversationID = conversationID
        self.projectID = projectID
        self.title = title
        self.searchableText = searchableText
        self.commandText = commandText
        self.errorText = errorText
        self.projectPath = projectPath
        self.archivedAt = archivedAt
    }
}

public struct ArchiveSearchService: Sendable {
    private let repository: CodexPlusRepository
    private let archiveRootPath: String
    private let now: @Sendable () -> Date

    public init(
        repository: CodexPlusRepository,
        archiveRootPath: String = ArchiveSearchService.defaultArchiveRootPath(homeDirectoryPath: NSHomeDirectory()),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.repository = repository
        self.archiveRootPath = archiveRootPath
        self.now = now
    }

    public func archive(
        conversation: ConversationSession,
        project: WorkspaceSessionGroup
    ) throws -> ConversationArchiveRecord {
        let markdown = MarkdownArchiveRenderer.render(conversation: conversation, projectName: project.displayName)

        let archivedAt = now()
        let record = Self.indexRecord(
            conversation: conversation,
            projectID: project.id,
            projectName: project.displayName,
            archivedAt: archivedAt
        )
        let archiveMarkdownPath = Self.defaultArchiveMarkdownPath(
            conversation: conversation,
            archiveRootPath: archiveRootPath
        )

        try writeArchiveMarkdown(markdown, to: archiveMarkdownPath)

        do {
            try repository.archiveConversation(
                record: record,
                archiveMarkdownPath: archiveMarkdownPath,
                archivedAt: archivedAt
            )
        } catch {
            try? FileManager.default.removeItem(atPath: archiveMarkdownPath)
            throw error
        }

        return record
    }

    public func search(_ query: String) throws -> [ConversationArchiveRecord] {
        try repository.searchArchiveRecords(query: query)
    }

    public static func indexRecord(
        conversation: ConversationSession,
        projectID: UUID,
        projectName: String,
        archivedAt: Date
    ) -> ConversationArchiveRecord {
        var searchableParts = [conversation.title, projectName, conversation.workspacePath]
        var commandParts: [String] = []
        var errorParts: [String] = []

        for event in conversation.events {
            switch event {
            case let .userPrompt(_, text),
                 let .status(_, text),
                 let .assistantMessage(_, text),
                 let .parseWarning(_, text):
                searchableParts.append(text)
            case let .command(_, executionID, command, status):
                commandParts.append(command)
                commandParts.append(status.rawValue)
                if let executionID {
                    commandParts.append(executionID)
                }
            case let .error(_, text):
                searchableParts.append(text)
                errorParts.append(text)
            }
        }

        return ConversationArchiveRecord(
            id: conversation.id,
            conversationID: conversation.id,
            projectID: projectID,
            title: conversation.title,
            searchableText: joinedText(searchableParts),
            commandText: joinedText(commandParts),
            errorText: joinedText(errorParts),
            projectPath: conversation.workspacePath,
            archivedAt: archivedAt
        )
    }

    public static func defaultArchiveRootPath(homeDirectoryPath: String) -> String {
        let libraryPath = NSString(string: homeDirectoryPath).appendingPathComponent("Library")
        let applicationSupportPath = NSString(string: libraryPath).appendingPathComponent("Application Support")
        let codexPlusPath = NSString(string: applicationSupportPath).appendingPathComponent("CodexPlus")
        return NSString(string: codexPlusPath).appendingPathComponent("Archives")
    }

    public static func defaultArchiveMarkdownPath(
        conversation: ConversationSession,
        archiveRootPath: String
    ) -> String {
        NSString(string: archiveRootPath)
            .appendingPathComponent("\(conversation.id.uuidString.lowercased()).md")
    }

    private static func joinedText(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func writeArchiveMarkdown(_ markdown: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
}
