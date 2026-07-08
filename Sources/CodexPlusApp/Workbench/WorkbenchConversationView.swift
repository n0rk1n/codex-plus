import CodexPlusCore
import SwiftUI

struct WorkbenchConversationView: View {
    let snapshot: WorkbenchSnapshot
    let actions: ConversationActions

    @State private var expandedTechnicalGroupIDs = Set<UUID>()

    var body: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.conversationCornerRadius) {
            Group {
                if let conversation = snapshot.activeConversation {
                    activeConversationView(conversation)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func activeConversationView(_ conversation: ConversationSession) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(CodexTypography.contentTitle)
                        .lineLimit(1)

                    Text(conversation.workspacePath)
                        .font(CodexTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                archiveButton(for: conversation.id)
            }
            .padding(.horizontal, CodexSpacing.contentStack)
            .padding(.top, CodexSpacing.contentStack)
            .padding(.bottom, CodexSpacing.contentInline)

            Divider()
                .overlay(CodexColors.surfaceDivider)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(ConversationTimelineBuilder.items(from: conversation.events)) { item in
                            timelineRow(for: item)
                                .id(item.id)
                        }
                    }
                    .padding(CodexSpacing.contentStack)
                }
                .onAppear {
                    scrollToLatest(conversation: conversation, using: proxy)
                }
                .onChange(of: conversation.events.count) {
                    scrollToLatest(conversation: conversation, using: proxy)
                }
            }
        }
    }

    private func archiveButton(for conversationID: UUID) -> some View {
        CodexButton(rule: .toolbarCapsule, help: "归档当前对话", action: {
            actions.archiveConversation(conversationID)
        }) {
            Label("归档", systemImage: "archivebox.and.arrow.down")
                .font(CodexTypography.statusBar)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, CodexSpacing.tightInline)
                .frame(height: 28)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "text.bubble")
                .font(CodexTypography.panelHeader)
                .foregroundStyle(.secondary)

            Text(WorkbenchStrings.emptyConversationTitle)
                .font(CodexTypography.sectionTitle)

            Text(WorkbenchStrings.emptyConversationSubtitle)
                .font(CodexTypography.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
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

    private func scrollToLatest(conversation: ConversationSession, using proxy: ScrollViewProxy) {
        guard let latestID = ConversationTimelineBuilder.items(from: conversation.events).last?.id else {
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
