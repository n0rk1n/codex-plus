import SwiftUI

struct SideEdgeAffordanceView: View {
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            Capsule(style: .continuous)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                .padding(2)
        }
        .buttonStyle(.plain)
        .help("Show Conversation")
        .accessibilityLabel("Show Conversation")
    }
}
