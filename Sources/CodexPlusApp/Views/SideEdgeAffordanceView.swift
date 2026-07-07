import SwiftUI

struct SideEdgeAffordanceView: View {
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            Capsule(style: .continuous)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .compositingGroup()
                .mask(Capsule(style: .continuous))
                .padding(2)
        }
        .buttonStyle(.plain)
        .codexCapsuleButtonHitArea()
        .help("Show Conversation")
        .accessibilityLabel("Show Conversation")
    }
}
