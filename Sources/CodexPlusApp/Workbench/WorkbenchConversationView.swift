import CodexPlusCore
import SwiftUI

struct WorkbenchConversationView: View {
    let snapshot: WorkbenchSnapshot
    let onArchiveConversation: (UUID) -> Void

    @State private var expandedTechnicalGroupIDs = Set<UUID>()

    var body: some View {
        LiquidGlassContainer(cornerRadius: 24) {
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
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)

                    Text(conversation.workspacePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                archiveButton(for: conversation.id)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .overlay(.white.opacity(0.08))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(ConversationTimelineBuilder.items(from: conversation.events)) { item in
                            timelineRow(for: item)
                                .id(item.id)
                        }
                    }
                    .padding(16)
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
        Button {
            onArchiveConversation(conversationID)
        } label: {
            Label("归档", systemImage: "archivebox.and.arrow.down")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .frame(height: 28)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Capsule(style: .continuous))
        .compositingGroup()
        .mask(Capsule(style: .continuous))
        .help("归档当前对话")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "text.bubble")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("暂无活动对话")
                .font(.system(size: 16, weight: .semibold))

            Text("新对话")
                .font(.caption)
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
