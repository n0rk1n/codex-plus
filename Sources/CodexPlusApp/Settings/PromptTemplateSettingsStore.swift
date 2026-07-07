import Combine
import Foundation

import CodexPlusCore

@MainActor
final class PromptTemplateSettingsStore: ObservableObject {
    @Published private(set) var templates: [PromptTemplate] = []
    @Published var searchQuery = ""
    @Published var sourceFilter: PromptTemplateSourceFilter = .all
    @Published var selectedTypes = Set(PromptTemplateType.allCases)
    @Published private(set) var selectedTemplateID: UUID?
    @Published private(set) var draft: PromptTemplateDraft?
    @Published private(set) var isEditable = false
    @Published private(set) var isDirty = false
    @Published private(set) var validationError: PromptTemplateValidationError?
    @Published private(set) var errorMessage: String?

    private let repository: any PromptTemplateRepository
    private var savedDraft: PromptTemplateDraft?
    private var fallbackSelectionID: UUID?

    init(repository: any PromptTemplateRepository) {
        self.repository = repository
        reload()
    }

    var visibleTemplates: [PromptTemplate] {
        PromptTemplateLibrary.filteredTemplates(
            templates,
            sourceFilter: sourceFilter,
            selectedTypes: selectedTypes,
            searchQuery: searchQuery
        )
    }

    var selectedTemplate: PromptTemplate? {
        guard let selectedTemplateID else {
            return nil
        }

        return templates.first { $0.id == selectedTemplateID }
    }

    func reload() {
        loadTemplates(preferredSelectionID: selectedTemplateID)
    }

    func select(_ id: UUID?) {
        guard let id, let template = templates.first(where: { $0.id == id }) else {
            clearSelection()
            return
        }

        selectedTemplateID = id
        draft = PromptTemplateDraft(template: template)
        savedDraft = draft
        isEditable = template.source == .userCustom
        isDirty = false
        validationError = nil
        errorMessage = nil
        fallbackSelectionID = nil
    }

    func createTemplate() {
        let now = Date()
        let nextType = selectedTypes.count == 1 ? selectedTypes.first : .archiveConversationSummary
        let nextDraft = PromptTemplateDraft(
            type: nextType,
            name: "",
            systemPrompt: "",
            userPrompt: "",
            note: "",
            createdAt: now,
            updatedAt: now
        )

        fallbackSelectionID = selectedTemplateID
        selectedTemplateID = nextDraft.id
        draft = nextDraft
        savedDraft = nil
        isEditable = true
        isDirty = true
        validationError = nil
        errorMessage = nil
    }

    func copySelectedTemplate() {
        guard let selectedTemplate else {
            return
        }

        let nextDraft = PromptTemplateLibrary.copyDraft(from: selectedTemplate)
        fallbackSelectionID = selectedTemplateID
        selectedTemplateID = nextDraft.id
        draft = nextDraft
        savedDraft = nil
        isEditable = true
        isDirty = true
        validationError = nil
        errorMessage = nil
    }

    func updateDraft(_ mutation: (inout PromptTemplateDraft) -> Void) {
        guard isEditable, var nextDraft = draft else {
            return
        }

        mutation(&nextDraft)
        draft = nextDraft
        isDirty = savedDraft != nextDraft
        validationError = PromptTemplateLibrary.validate(nextDraft)
        errorMessage = nil
    }

    func discardChanges() {
        guard isEditable else {
            return
        }

        if let savedDraft {
            draft = savedDraft
            isDirty = false
            validationError = nil
            errorMessage = nil
            return
        }

        if let fallbackSelectionID,
           templates.contains(where: { $0.id == fallbackSelectionID }) {
            select(fallbackSelectionID)
            return
        }

        if let firstTemplateID = templates.first?.id {
            select(firstTemplateID)
        } else {
            clearSelection()
        }
    }

    func save() {
        guard let draft else {
            return
        }

        do {
            let template = try PromptTemplateLibrary.userTemplate(from: draft)
            try repository.savePromptTemplate(template)
            loadTemplates(preferredSelectionID: template.id)
        } catch let validation as PromptTemplateValidationError {
            validationError = validation
        } catch {
            errorMessage = "无法保存提示词模板：\(error)"
        }
    }

    func deleteSelectedTemplate() {
        guard let template = selectedTemplate, template.source == .userCustom else {
            return
        }

        do {
            try repository.deletePromptTemplate(template.id)
            loadTemplates(preferredSelectionID: nil)
        } catch {
            errorMessage = "无法删除提示词模板：\(error)"
        }
    }

    func toggleTypeFilter(_ type: PromptTemplateType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
    }

    private func loadTemplates(preferredSelectionID: UUID?) {
        let nextTemplates: [PromptTemplate]
        let loadErrorMessage: String?
        do {
            nextTemplates = PromptTemplateLibrary.sortedTemplates(
                PromptTemplateLibrary.builtInTemplates() + (try repository.loadPromptTemplates())
            )
            loadErrorMessage = nil
        } catch {
            nextTemplates = PromptTemplateLibrary.sortedTemplates(PromptTemplateLibrary.builtInTemplates())
            loadErrorMessage = "无法加载提示词模板：\(error)"
        }

        templates = nextTemplates
        reconcileSelection(preferredSelectionID: preferredSelectionID)
        errorMessage = loadErrorMessage
    }

    private func reconcileSelection(preferredSelectionID: UUID?) {
        if let preferredSelectionID,
           templates.contains(where: { $0.id == preferredSelectionID }) {
            select(preferredSelectionID)
            return
        }

        if let firstTemplateID = templates.first?.id {
            select(firstTemplateID)
            return
        }

        clearSelection()
    }

    private func clearSelection() {
        selectedTemplateID = nil
        draft = nil
        savedDraft = nil
        isEditable = false
        isDirty = false
        validationError = nil
        fallbackSelectionID = nil
    }
}
