import CodexPlusCore
import SwiftUI

struct ConversationView: View {
    let snapshot: ConversationCoordinatorSnapshot
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

    @FocusState private var isFollowUpFocused: Bool
    @State private var followUp = ""
    @State private var expandedTechnicalGroupIDs = Set<UUID>()

    private var session: ConversationSession? {
        snapshot.activeConversation
    }

    var body: some View {
        LiquidGlassScene(padding: 14, minWidth: 360, minHeight: 420) {
            panelContent
        }
        .onAppear {
            if session != nil {
                isFollowUpFocused = true
            }
        }
    }

    private var panelContent: some View {
        VStack(spacing: CodexSpacing.contentInline) {
            header

            if let session {
                conversationBody(for: session)
                footer(for: session)
            } else {
                Spacer(minLength: 0)
                ConversationDraftView(
                    draft: snapshot.draft,
                    onPickWorkspace: onPickWorkspace,
                    onSubmit: onSubmitDraft
                )
            }
        }
    }

    private var header: some View {
        LiquidGlassContainer(cornerRadius: 20) {
            VStack(spacing: 8) {
                ConversationTabHeaderView(
                    snapshot: snapshot,
                    onSelectWorkspace: onSelectWorkspace,
                    onSelectConversation: onSelectConversation,
                    onNewDraft: onNewDraft,
                    onArchiveConversation: onArchiveConversation,
                    onReorderWorkspace: onReorderWorkspace,
                    onReorderConversation: onReorderConversation
                )

                if let session {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.state.labelText)
                                .font(CodexTypography.statusBar)
                                .foregroundStyle(session.state.tint)
                                .lineLimit(1)

                            Text(session.permissionMode.displayName)
                                .font(CodexTypography.caption2)
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
                    }
                }
            }
            .padding(.horizontal, CodexSpacing.contentInline)
            .padding(.vertical, CodexSpacing.tightInline)
        }
    }

    private func conversationBody(for session: ConversationSession) -> some View {
        LiquidGlassContainer(cornerRadius: CodexRadius.panel) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(timelineItems(for: session)) { item in
                            timelineRow(for: item)
                                .id(item.id)
                        }
                    }
                    .padding(CodexSpacing.compactInline)
                }
                .onChange(of: session.events.count) {
                    scrollToLatest(session: session, using: proxy)
                }
                .onAppear {
                    scrollToLatest(session: session, using: proxy)
                }
            }
        }
    }

    private func footer(for _: ConversationSession) -> some View {
        LiquidGlassContainer(cornerRadius: CodexRadius.card) {
            HStack(alignment: .bottom, spacing: 10) {
                CodexMultilineTextField(
                    rule: .conversationFollowUpPrompt,
                    placeholder: "Follow up...",
                    text: $followUp,
                    onSubmit: submitFollowUp
                )
                .focused($isFollowUpFocused)

                CodexButton(
                    rule: .composerIconCircle,
                    action: submitFollowUp
                ) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(CodexTypography.sectionHeader)
                }
                .help("Send")
                .accessibilityLabel("Send Follow-Up")
                .disabled(followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, CodexSpacing.compactInline)
            .padding(.vertical, CodexSpacing.contentInline)
        }
    }

    private var fullAccessWarningText: String {
        PermissionPrompter.fullAccessWarningText
    }

    private func timelineItems(for session: ConversationSession) -> [ConversationTimelineItem] {
        ConversationTimelineBuilder.items(from: session.events)
    }

    @ViewBuilder
    private func timelineRow(for item: ConversationTimelineItem) -> some View {
        switch item {
        case let .event(event):
            ConversationEventRow(event: event)
        case let .technicalGroup(id, events):
            ConversationTechnicalEventGroupRow(
                events: events,
                isExpanded: expandedTechnicalGroupIDs.contains(id),
                onToggle: {
                    toggleTechnicalGroup(id)
                }
            )
        case let .compressionSnapshot(snapshot, sourceEvents):
            ConversationCompressionSnapshotRow(snapshot: snapshot, sourceEvents: sourceEvents)
        }
    }

    private func iconButton(
        systemName: String,
        help: String,
        accessibilityLabel: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        CodexButton(
            rule: .rowRectangle,
            isDisabled: isDisabled,
            help: help,
            accessibilityLabel: accessibilityLabel,
            action: action
        ) {
            Image(systemName: systemName)
                .font(CodexTypography.menuPrimary)
                .frame(width: 28, height: 28)
        }
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

    private func scrollToLatest(session: ConversationSession, using proxy: ScrollViewProxy) {
        guard let latestID = timelineItems(for: session).last?.id else {
            return
        }

        proxy.scrollTo(latestID, anchor: .bottom)
    }

    private func toggleTechnicalGroup(_ id: UUID) {
        if expandedTechnicalGroupIDs.contains(id) {
            expandedTechnicalGroupIDs.remove(id)
        } else {
            expandedTechnicalGroupIDs.insert(id)
        }
    }
}
