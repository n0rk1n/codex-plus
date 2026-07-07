import Foundation

public protocol PromptTemplateRepository: Sendable {
    func savePromptTemplate(_ template: PromptTemplate) throws
    func loadPromptTemplates() throws -> [PromptTemplate]
    func deletePromptTemplate(_ id: UUID) throws
}
