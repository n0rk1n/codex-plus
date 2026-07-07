import Foundation
import CodexPlusCore
@testable import CodexPlusApp

@MainActor
func runPromptTemplateSettingsStoreLegacyTests() {
    let repository = RecordingPromptTemplateRepository()
    let builtIns = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100))
    let customTemplate = PromptTemplate(
        id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
        source: .userCustom,
        type: .archiveConversationSummary,
        name: "用户模板",
        systemPrompt: "整理归档对话",
        userPrompt: "",
        note: "",
        createdAt: Date(timeIntervalSince1970: 110),
        updatedAt: Date(timeIntervalSince1970: 120)
    )
    repository.templates = [customTemplate]

    let store = PromptTemplateSettingsStore(repository: repository)

    expect(
        store.visibleTemplates.map(\.id).contains(customTemplate.id),
        "prompt template settings store exposes custom templates"
    )

    if let builtInID = builtIns.first?.id {
        store.select(builtInID)
        store.save()

        expect(repository.savedTemplates.isEmpty, "system built-in template save does not hit repository")
        expect(store.selectedTemplate?.source == .systemBuiltIn, "system built-in template remains selected")
        expect(store.isEditable == false, "system built-in template stays read-only")
    } else {
        expect(false, "prompt template built-ins should exist")
    }

    store.sourceFilter = .source(.userCustom)
    if let builtInID = builtIns.first?.id {
        store.select(builtInID)
        store.createTemplate()
        store.discardChanges()

        expect(
            store.selectedTemplate?.id == customTemplate.id,
            "discard falls back to the visible custom template under filters"
        )
    }

    repository.templates = []
    store.sourceFilter = .source(.userCustom)
    store.select(customTemplate.id)
    store.deleteSelectedTemplate()

    expect(
        store.selectedTemplate == nil,
        "delete clears selection when no visible templates remain"
    )

    repository.templates = [customTemplate]
    store.sourceFilter = .source(.userCustom)
    if let builtInID = builtIns.first?.id {
        store.select(builtInID)
        store.reload()

        expect(
            store.selectedTemplate?.id == customTemplate.id,
            "reload falls back to the visible custom template under filters"
        )
    }
}

private final class RecordingPromptTemplateRepository: PromptTemplateRepository, @unchecked Sendable {
    var templates: [PromptTemplate] = []
    private(set) var savedTemplates: [PromptTemplate] = []
    private(set) var deletedTemplateIDs: [UUID] = []

    func savePromptTemplate(_ template: PromptTemplate) throws {
        savedTemplates.append(template)

        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
    }

    func loadPromptTemplates() throws -> [PromptTemplate] {
        templates
    }

    func deletePromptTemplate(_ id: UUID) throws {
        deletedTemplateIDs.append(id)
        templates.removeAll { $0.id == id }
    }
}
