import Foundation
import CodexPlusCore

struct WorkbenchActions {
    var projectStrip: ProjectStripActions
    var conversation: ConversationActions
    var composer: ComposerActions
    var archive: ArchiveActions
}

struct ProjectStripActions {
    let newConversation: () -> Void
    let returnToConversation: () -> Void
    let openArchive: () -> Void
    let openSettings: () -> Void
    let togglePin: () -> Void
    let selectProject: (UUID) -> Void
    let selectConversation: (UUID) -> Void
}

struct ConversationActions {
    let archiveConversation: (UUID) -> Void
    let editCompressionSegment: (UUID, CompressionSegmentKind, String) -> Void
    let excludeCompressionRound: (UUID) -> Void
    let compressSelectedRounds: ([UUID]) -> (any ExecutionHandle)?
}

struct ComposerActions {
    let send: (String) -> Void
    let systemCompress: (String) -> (any ExecutionHandle)?
    let optimizePrompt: (String, @escaping @Sendable (PromptOptimizationResult) -> Void) -> (any ExecutionHandle)?
    let pickWorkspace: () -> Void
    let clearWorkspace: () -> Void
    let stop: () -> Void
}

struct ArchiveActions {
    let search: (String) -> Void
    let open: (UUID) -> Void
    let delete: (UUID) -> Void
    let restore: (UUID) -> Bool
    let jumpToRestored: (UUID) -> Void
}
