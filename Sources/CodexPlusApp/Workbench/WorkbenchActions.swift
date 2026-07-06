import Foundation

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
    let togglePin: () -> Void
    let selectProject: (UUID) -> Void
    let selectConversation: (UUID) -> Void
}

struct ConversationActions {
    let archiveConversation: (UUID) -> Void
}

struct ComposerActions {
    let send: (String) -> Void
    let pickWorkspace: () -> Void
    let clearWorkspace: () -> Void
    let stop: () -> Void
}

struct ArchiveActions {
    let search: (String) -> Void
    let open: (UUID) -> Void
}
