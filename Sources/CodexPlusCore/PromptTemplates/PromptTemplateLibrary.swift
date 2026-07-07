import Foundation

public enum PromptTemplateLibrary {
    private static let archiveBuiltInID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let optimizeBuiltInID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    public static func builtInTemplates(now: Date = Date()) -> [PromptTemplate] {
        [
            PromptTemplate(
                id: archiveBuiltInID,
                source: .systemBuiltIn,
                type: .archiveConversationSummary,
                name: "归档对话总结",
                systemPrompt: "你是 Codex 对话归档助手。请把对话整理成可复用的归档摘要，保留目标、关键决策、完成内容、验证结果、遗留风险和后续动作。输出应简洁、结构清晰，并避免加入对话中没有出现的信息。",
                userPrompt: "请总结当前归档对话，输出适合保存和检索的摘要。",
                note: "用于将已归档 Codex 对话整理成摘要。",
                createdAt: now,
                updatedAt: now
            ),
            PromptTemplate(
                id: optimizeBuiltInID,
                source: .systemBuiltIn,
                type: .optimizeUserInputPrompt,
                name: "优化输入框提示词",
                systemPrompt: "你是 Codex 提示词优化助手。请把用户输入改写成更清晰、可执行、边界明确的 Codex 请求，保留用户原意，不添加用户没有要求的范围。",
                userPrompt: "请优化这段用户输入，使它更适合发送给 Codex。",
                note: "用于优化用户对话输入框中的提示词。",
                createdAt: now,
                updatedAt: now
            )
        ]
    }

    public static func validate(_ draft: PromptTemplateDraft) -> PromptTemplateValidationError? {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptyName
        }
        guard draft.type != nil else {
            return .missingType
        }
        if draft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptySystemPrompt
        }
        return nil
    }

    public static func userTemplate(from draft: PromptTemplateDraft, now: Date = Date()) throws -> PromptTemplate {
        if let validationError = validate(draft) {
            throw validationError
        }

        return PromptTemplate(
            id: draft.id,
            source: .userCustom,
            type: draft.type!,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: draft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            userPrompt: draft.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: draft.createdAt,
            updatedAt: now
        )
    }

    public static func copyDraft(from template: PromptTemplate, now: Date = Date()) -> PromptTemplateDraft {
        PromptTemplateDraft(
            id: UUID(),
            type: template.type,
            name: "\(template.name) 副本",
            systemPrompt: template.systemPrompt,
            userPrompt: template.userPrompt,
            note: template.note,
            createdAt: now,
            updatedAt: now
        )
    }

    public static func sortedTemplates(_ templates: [PromptTemplate]) -> [PromptTemplate] {
        templates.sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source == .systemBuiltIn
            }

            if lhs.source == .userCustom, lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func filteredTemplates(
        _ templates: [PromptTemplate],
        sourceFilter: PromptTemplateSourceFilter,
        selectedTypes: Set<PromptTemplateType>,
        searchQuery: String
    ) -> [PromptTemplate] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return sortedTemplates(templates).filter { template in
            switch sourceFilter {
            case .all:
                break
            case let .source(source):
                guard template.source == source else {
                    return false
                }
            }

            if !selectedTypes.isEmpty, !selectedTypes.contains(template.type) {
                return false
            }

            guard !trimmedQuery.isEmpty else {
                return true
            }

            return [
                template.name,
                template.note,
                template.systemPrompt,
                template.userPrompt
            ].contains { text in
                text.lowercased().contains(trimmedQuery)
            }
        }
    }
}
