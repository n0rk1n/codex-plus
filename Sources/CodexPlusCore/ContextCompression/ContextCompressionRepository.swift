import Foundation

public protocol ContextCompressionRepository: Sendable {
    func loadCompressionState(conversationID: UUID) throws -> ConversationCompressionState
    func replaceCompressionRounds(
        _ rounds: [CompressionRound],
        events: [CompressionRoundEvent],
        conversationID: UUID
    ) throws

    func saveCompressionVersion(_ version: CompressionVersion) throws
    func saveCompressionVersionSources(_ sources: [CompressionVersionSource]) throws
    func saveCompressionLineageEdges(_ edges: [CompressionLineageEdge]) throws
    func saveCompressionInput(_ input: CompressionInputRecord) throws
    func saveCompressionTombstones(_ tombstones: [CompressionTombstone]) throws

    func setActiveCompressionVersion(_ active: CompressionActiveVersion) throws
    func clearActiveCompressionVersion(conversationID: UUID, roundID: UUID?, rangeID: UUID?) throws
}
