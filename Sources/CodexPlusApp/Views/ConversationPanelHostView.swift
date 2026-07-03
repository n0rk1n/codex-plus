import CodexPlusCore
import SwiftUI

@MainActor
final class ConversationPanelModel: ObservableObject {
    @Published var snapshot: ConversationCoordinatorSnapshot

    init(snapshot: ConversationCoordinatorSnapshot) {
        self.snapshot = snapshot
    }
}

struct ConversationPanelHostView: View {
    @ObservedObject var model: ConversationPanelModel

    let onSubmitDraft: (String) -> Void
    let onFollowUp: (String) -> Void
    let onStop: () -> Void
    let onTogglePin: () -> Void
    let onToggleSide: () -> Void
    let onToggleFullAccess: () -> Void
    let onSelectWorkspace: (UUID) -> Void
    let onSelectConversation: (UUID) -> Void
    let onNewDraft: () -> Void
    let onArchiveConversation: (UUID) -> Void
    let onPickWorkspace: () -> Void
    let onReorderWorkspace: (UUID, Int) -> Void
    let onReorderConversation: (UUID, Int) -> Void

    var body: some View {
        ConversationView(
            snapshot: model.snapshot,
            onSubmitDraft: onSubmitDraft,
            onFollowUp: onFollowUp,
            onStop: onStop,
            onTogglePin: onTogglePin,
            onToggleSide: onToggleSide,
            onToggleFullAccess: onToggleFullAccess,
            onSelectWorkspace: onSelectWorkspace,
            onSelectConversation: onSelectConversation,
            onNewDraft: onNewDraft,
            onArchiveConversation: onArchiveConversation,
            onPickWorkspace: onPickWorkspace,
            onReorderWorkspace: onReorderWorkspace,
            onReorderConversation: onReorderConversation
        )
        .id(panelIdentity)
    }

    private var panelIdentity: String {
        if let activeConversationID = model.snapshot.activeConversationID {
            return "conversation-\(activeConversationID.uuidString)"
        }

        return "conversation-draft"
    }
}
