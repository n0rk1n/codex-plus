import Foundation

public enum PromptTemplateSource: String, CaseIterable, Sendable {
    case systemBuiltIn
    case userCustom

    public var displayName: String {
        switch self {
        case .systemBuiltIn:
            return "系统内置提示词"
        case .userCustom:
            return "用户自定义提示词"
        }
    }
}

public enum PromptTemplateType: String, CaseIterable, Sendable {
    case archiveConversationSummary
    case optimizeUserInputPrompt

    public var displayName: String {
        switch self {
        case .archiveConversationSummary:
            return "对归档对话进行总结"
        case .optimizeUserInputPrompt:
            return "优化用户对话输入框提示词"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .archiveConversationSummary:
            return "归档总结"
        case .optimizeUserInputPrompt:
            return "优化输入"
        }
    }
}

public enum PromptTemplateSourceFilter: Equatable, Hashable, Sendable {
    case all
    case source(PromptTemplateSource)
}

public struct PromptTemplate: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var source: PromptTemplateSource
    public var type: PromptTemplateType
    public var name: String
    public var systemPrompt: String
    public var userPrompt: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        source: PromptTemplateSource,
        type: PromptTemplateType,
        name: String,
        systemPrompt: String,
        userPrompt: String,
        note: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.type = type
        self.name = name
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PromptTemplateDraft: Equatable, Sendable {
    public var id: UUID
    public var type: PromptTemplateType?
    public var name: String
    public var systemPrompt: String
    public var userPrompt: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        type: PromptTemplateType?,
        name: String,
        systemPrompt: String,
        userPrompt: String,
        note: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(template: PromptTemplate) {
        self.init(
            id: template.id,
            type: template.type,
            name: template.name,
            systemPrompt: template.systemPrompt,
            userPrompt: template.userPrompt,
            note: template.note,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
    }
}

public enum PromptTemplateValidationError: Error, Equatable, Sendable {
    case emptyName
    case missingType
    case emptySystemPrompt
}
