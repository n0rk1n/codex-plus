import Foundation

public protocol AttachmentRepository: Sendable {
    func saveAttachment(_ attachment: CodexPlusAttachment) throws
    func loadAttachments(ownerKind: String, ownerID: UUID?) throws -> [CodexPlusAttachment]
    func deleteAttachment(_ id: UUID) throws
}
