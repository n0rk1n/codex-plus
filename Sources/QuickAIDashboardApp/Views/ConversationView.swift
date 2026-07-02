import QuickAIDashboardCore
import SwiftUI

struct ConversationView: View {
    let session: ConversationSession
    let onFollowUp: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onToggleSide: () -> Void
    let onToggleFullAccess: () -> Void

    @FocusState private var isFollowUpFocused: Bool
    @State private var followUp = ""

    var body: some View {
        VStack(spacing: 12) {
            header

            LiquidGlassContainer(cornerRadius: 24) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(session.events) { event in
                                ConversationEventRow(event: event)
                                    .id(event.id)
                            }
                        }
                        .padding(14)
                    }
                    .onChange(of: session.events.count) {
                        scrollToLatest(using: proxy)
                    }
                    .onAppear {
                        scrollToLatest(using: proxy)
                    }
                }
            }

            footer
        }
        .padding(14)
        .frame(minWidth: 360, minHeight: 420)
        .onAppear {
            isFollowUpFocused = true
        }
    }

    private var header: some View {
        LiquidGlassContainer(cornerRadius: 20) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.state.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(session.state.tint)
                        .lineLimit(1)

                    Text(session.permissionMode.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                iconButton(
                    systemName: session.permissionMode == .fullAccess ? "lock.open.fill" : "lock.fill",
                    help: fullAccessWarningText,
                    accessibilityLabel: session.permissionMode == .fullAccess ? "Disable Full Access" : "Enable Full Access",
                    action: onToggleFullAccess
                )

                iconButton(
                    systemName: "sidebar.trailing",
                    help: "Switch Side",
                    accessibilityLabel: "Switch Side",
                    action: onToggleSide
                )

                iconButton(
                    systemName: session.isPinned ? "pin.fill" : "pin",
                    help: "Pin",
                    accessibilityLabel: session.isPinned ? "Unpin Window" : "Pin Window",
                    action: onTogglePin
                )

                iconButton(
                    systemName: "stop.fill",
                    help: "Stop",
                    accessibilityLabel: "Stop Codex Task",
                    isDisabled: session.state != .running,
                    action: onStop
                )

                iconButton(
                    systemName: "xmark",
                    help: "Close",
                    accessibilityLabel: "Close Conversation",
                    action: onClose
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var footer: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Follow up...", text: $followUp, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...4)
                    .focused($isFollowUpFocused)
                    .onSubmit(submitFollowUp)

                Button(action: submitFollowUp) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Send")
                .accessibilityLabel("Send Follow-Up")
                .disabled(followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var fullAccessWarningText: String {
        PermissionPrompter.fullAccessWarningText
    }

    private func iconButton(
        systemName: String,
        help: String,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.38 : 1)
    }

    private func submitFollowUp() {
        let trimmedFollowUp = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFollowUp.isEmpty else {
            return
        }

        onFollowUp(trimmedFollowUp)
        followUp = ""
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let latestID = session.events.last?.id else {
            return
        }

        proxy.scrollTo(latestID, anchor: .bottom)
    }
}

private extension ConversationRunState {
    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .stopped:
            return "Stopped"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .stopped:
            return .orange
        }
    }
}
