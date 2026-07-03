import CodexPlusCore
import SwiftUI

@MainActor
final class ConversationPanelModel: ObservableObject {
    @Published var session: ConversationSession

    init(session: ConversationSession) {
        self.session = session
    }
}

struct ConversationPanelHostView: View {
    @ObservedObject var model: ConversationPanelModel

    let onFollowUp: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onToggleSide: () -> Void
    let onToggleFullAccess: () -> Void

    var body: some View {
        ConversationView(
            session: model.session,
            onFollowUp: onFollowUp,
            onStop: onStop,
            onClose: onClose,
            onTogglePin: onTogglePin,
            onToggleSide: onToggleSide,
            onToggleFullAccess: onToggleFullAccess
        )
        .id(model.session.id)
    }
}
