import SwiftUI

struct SideEdgeAffordanceView: View {
    let onActivate: () -> Void

    var body: some View {
        CodexButton(
            rule: .toolbarCapsule,
            help: "Show Conversation",
            accessibilityLabel: "Show Conversation",
            action: onActivate
        ) {
            Capsule(style: .continuous)
                .padding(2)
        }
    }
}
