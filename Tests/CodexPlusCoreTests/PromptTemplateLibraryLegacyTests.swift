import Foundation
import CodexPlusCore

func runPromptTemplateLibraryTests() {
    let builtIns = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100))
    expect(
        builtIns.allSatisfy { $0.source == .systemBuiltIn },
        "prompt templates keep built-ins system sourced"
    )
    expect(
        Set(builtIns.map(\.type)) == Set(PromptTemplateType.allCases),
        "prompt templates provide built-ins for all supported types"
    )
    expect(
        builtIns.allSatisfy { !$0.systemPrompt.isEmpty },
        "prompt template built-ins always include a system prompt"
    )

    var draft = PromptTemplateDraft(
        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        type: .archiveConversationSummary,
        name: "摘要",
        systemPrompt: "整理归档对话",
        userPrompt: "",
        note: "",
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 100)
    )

    expect(
        PromptTemplateLibrary.validate(draft) == nil,
        "prompt template validation accepts an empty user prompt"
    )
    draft.name = "   "
    expect(
        PromptTemplateLibrary.validate(draft) == .emptyName,
        "prompt template validation requires a name"
    )
    draft.name = "摘要"
    draft.type = nil
    expect(
        PromptTemplateLibrary.validate(draft) == .missingType,
        "prompt template validation requires a type"
    )
    draft.type = .archiveConversationSummary
    draft.systemPrompt = "\n "
    expect(
        PromptTemplateLibrary.validate(draft) == .emptySystemPrompt,
        "prompt template validation requires a system prompt"
    )

    let now = Date(timeIntervalSince1970: 100)
    let archive = PromptTemplate(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        source: .userCustom,
        type: .archiveConversationSummary,
        name: "归档",
        systemPrompt: "归档",
        userPrompt: "",
        note: "",
        createdAt: now,
        updatedAt: now
    )
    let optimize = PromptTemplate(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        source: .userCustom,
        type: .optimizeUserInputPrompt,
        name: "优化",
        systemPrompt: "优化",
        userPrompt: "",
        note: "",
        createdAt: now,
        updatedAt: now
    )

    expect(
        PromptTemplateLibrary.filteredTemplates(
            [archive, optimize],
            sourceFilter: .all,
            selectedTypes: [],
            searchQuery: ""
        ).map(\.id) == [archive.id, optimize.id],
        "prompt template type filtering treats no selected type as all types"
    )
    expect(
        PromptTemplateLibrary.filteredTemplates(
            [archive, optimize],
            sourceFilter: .all,
            selectedTypes: [.archiveConversationSummary],
            searchQuery: ""
        ).map(\.id) == [archive.id],
        "prompt template type filtering supports one selected type"
    )
    expect(
        PromptTemplateLibrary.filteredTemplates(
            [archive, optimize],
            sourceFilter: .all,
            selectedTypes: Set(PromptTemplateType.allCases),
            searchQuery: ""
        ).map(\.id) == [archive.id, optimize.id],
        "prompt template type filtering supports multiple selected types"
    )

    let searchable = PromptTemplate(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        source: .userCustom,
        type: .archiveConversationSummary,
        name: "项目复盘摘要",
        systemPrompt: "保留验证结果",
        userPrompt: "输出中文摘要",
        note: "归档后检索",
        createdAt: now,
        updatedAt: now
    )
    for query in ["复盘", "验证", "中文", "检索"] {
        expect(
            PromptTemplateLibrary.filteredTemplates(
                [searchable],
                sourceFilter: .all,
                selectedTypes: [],
                searchQuery: query
            ) == [searchable],
            "prompt template search matches \(query)"
        )
    }

    let older = Date(timeIntervalSince1970: 10)
    let newer = Date(timeIntervalSince1970: 20)
    let customOld = PromptTemplate(
        id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
        source: .userCustom,
        type: .archiveConversationSummary,
        name: "旧",
        systemPrompt: "旧",
        userPrompt: "",
        note: "",
        createdAt: older,
        updatedAt: older
    )
    let customNew = PromptTemplate(
        id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
        source: .userCustom,
        type: .archiveConversationSummary,
        name: "新",
        systemPrompt: "新",
        userPrompt: "",
        note: "",
        createdAt: newer,
        updatedAt: newer
    )
    expect(
        PromptTemplateLibrary.sortedTemplates([customOld, builtIns[0], customNew]).map(\.id) ==
            [builtIns[0].id, customNew.id, customOld.id],
        "prompt template sorting puts built-ins first then custom templates by update time"
    )

    let copied = PromptTemplateLibrary.copyDraft(
        from: builtIns[0],
        now: Date(timeIntervalSince1970: 200)
    )
    expect(copied.id != builtIns[0].id, "prompt template copy creates a new draft id")
    expect(copied.type == builtIns[0].type, "prompt template copy keeps the selected type")
    expect(copied.systemPrompt == builtIns[0].systemPrompt, "prompt template copy keeps system prompt")
    expect(copied.userPrompt == builtIns[0].userPrompt, "prompt template copy keeps user prompt")
    expect(copied.note == builtIns[0].note, "prompt template copy keeps note")
    expect(copied.name.contains("副本"), "prompt template copy marks the draft name as a copy")
}
