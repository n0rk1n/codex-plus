import Foundation
import XCTest
@testable import CodexPlusCore

final class PromptTemplateLibraryTests: XCTestCase {
    func testBuiltInTemplatesAreReadOnlyAndCoverBothTypes() {
        let templates = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100))

        XCTAssertTrue(templates.allSatisfy { $0.source == .systemBuiltIn })
        XCTAssertEqual(Set(templates.map(\.type)), Set(PromptTemplateType.allCases))
        XCTAssertTrue(templates.allSatisfy { !$0.name.isEmpty })
        XCTAssertTrue(templates.allSatisfy { !$0.systemPrompt.isEmpty })
    }

    func testValidationRequiresNameTypeAndSystemPromptOnly() {
        let now = Date(timeIntervalSince1970: 100)
        var draft = PromptTemplateDraft(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            type: .archiveConversationSummary,
            name: "摘要",
            systemPrompt: "整理归档对话",
            userPrompt: "",
            note: "",
            createdAt: now,
            updatedAt: now
        )

        XCTAssertNil(PromptTemplateLibrary.validate(draft))

        draft.name = "   "
        XCTAssertEqual(PromptTemplateLibrary.validate(draft), .emptyName)

        draft.name = "摘要"
        draft.type = nil
        XCTAssertEqual(PromptTemplateLibrary.validate(draft), .missingType)

        draft.type = .archiveConversationSummary
        draft.systemPrompt = "\n "
        XCTAssertEqual(PromptTemplateLibrary.validate(draft), .emptySystemPrompt)
    }

    func testTypeFilteringSupportsNoneOneAndBothSelectedTypes() {
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
        let templates = [archive, optimize]

        XCTAssertEqual(
            PromptTemplateLibrary.filteredTemplates(
                templates,
                sourceFilter: .all,
                selectedTypes: [],
                searchQuery: ""
            ).map(\.id),
            [archive.id, optimize.id]
        )
        XCTAssertEqual(
            PromptTemplateLibrary.filteredTemplates(
                templates,
                sourceFilter: .all,
                selectedTypes: [.archiveConversationSummary],
                searchQuery: ""
            ).map(\.id),
            [archive.id]
        )
        XCTAssertEqual(
            PromptTemplateLibrary.filteredTemplates(
                templates,
                sourceFilter: .all,
                selectedTypes: Set(PromptTemplateType.allCases),
                searchQuery: ""
            ).map(\.id),
            [archive.id, optimize.id]
        )
    }

    func testSearchMatchesNameNoteSystemPromptAndUserPrompt() {
        let now = Date(timeIntervalSince1970: 100)
        let template = PromptTemplate(
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
            XCTAssertEqual(
                PromptTemplateLibrary.filteredTemplates(
                    [template],
                    sourceFilter: .all,
                    selectedTypes: [],
                    searchQuery: query
                ),
                [template]
            )
        }
    }

    func testSortingPlacesBuiltInsBeforeCustomTemplates() {
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
        let builtIn = PromptTemplateLibrary.builtInTemplates(now: older)[0]

        XCTAssertEqual(
            PromptTemplateLibrary.sortedTemplates([customOld, builtIn, customNew]).map(\.id),
            [builtIn.id, customNew.id, customOld.id]
        )
    }

    func testCopyingTemplateCreatesUserCustomDraft() {
        let source = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100))[0]
        let draft = PromptTemplateLibrary.copyDraft(from: source, now: Date(timeIntervalSince1970: 200))

        XCTAssertNotEqual(draft.id, source.id)
        XCTAssertEqual(draft.type, source.type)
        XCTAssertEqual(draft.systemPrompt, source.systemPrompt)
        XCTAssertEqual(draft.userPrompt, source.userPrompt)
        XCTAssertEqual(draft.note, source.note)
        XCTAssertTrue(draft.name.contains("副本"))
    }

    func testDefaultTemplateIDsUseFirstBuiltInPerTypeWhenNoSelectionExists() {
        let builtIns = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100))
        let defaults = PromptTemplateLibrary.resolvedDefaultTemplateIDs(
            templates: builtIns,
            savedDefaultTemplateIDs: [:]
        )

        for type in PromptTemplateType.allCases {
            XCTAssertEqual(
                defaults[type],
                builtIns.first { $0.source == .systemBuiltIn && $0.type == type }?.id
            )
        }
    }

    func testDefaultTemplateIDsKeepSavedSelectionWhenItMatchesTheType() {
        let now = Date(timeIntervalSince1970: 100)
        let builtIns = PromptTemplateLibrary.builtInTemplates(now: now)
        let custom = PromptTemplate(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            source: .userCustom,
            type: .archiveConversationSummary,
            name: "自定义归档默认",
            systemPrompt: "自定义归档",
            userPrompt: "",
            note: "",
            createdAt: now,
            updatedAt: now
        )

        let defaults = PromptTemplateLibrary.resolvedDefaultTemplateIDs(
            templates: builtIns + [custom],
            savedDefaultTemplateIDs: [.archiveConversationSummary: custom.id]
        )

        XCTAssertEqual(defaults[.archiveConversationSummary], custom.id)
        XCTAssertEqual(
            defaults[.optimizeUserInputPrompt],
            builtIns.first { $0.type == .optimizeUserInputPrompt }?.id
        )
    }

    func testDefaultTemplateIDsIgnoreSavedSelectionWhenTemplateIsMissingOrWrongType() {
        let now = Date(timeIntervalSince1970: 100)
        let builtIns = PromptTemplateLibrary.builtInTemplates(now: now)
        let optimizeCustom = PromptTemplate(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            source: .userCustom,
            type: .optimizeUserInputPrompt,
            name: "自定义优化",
            systemPrompt: "自定义优化",
            userPrompt: "",
            note: "",
            createdAt: now,
            updatedAt: now
        )

        let defaults = PromptTemplateLibrary.resolvedDefaultTemplateIDs(
            templates: builtIns + [optimizeCustom],
            savedDefaultTemplateIDs: [
                .archiveConversationSummary: optimizeCustom.id,
                .optimizeUserInputPrompt: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
            ]
        )

        XCTAssertEqual(
            defaults[.archiveConversationSummary],
            builtIns.first { $0.type == .archiveConversationSummary }?.id
        )
        XCTAssertEqual(
            defaults[.optimizeUserInputPrompt],
            builtIns.first { $0.type == .optimizeUserInputPrompt }?.id
        )
    }
}
