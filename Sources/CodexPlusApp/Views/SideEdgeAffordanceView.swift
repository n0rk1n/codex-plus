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
                .fill(Color.white.opacity(0.08))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(2)
        }
    }
}
