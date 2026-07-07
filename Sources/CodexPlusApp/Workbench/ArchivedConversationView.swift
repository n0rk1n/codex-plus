import CodexPlusCore
import SwiftUI

struct ArchivedConversationView: View {
    let results: [ConversationArchiveRecord]
    let openedConversation: ConversationSession?
    let actions: ArchiveActions

    private let archiveSwipeActionSpacingAdjustment: CGFloat = -8

    @State private var query = ""
    @State private var expandedTechnicalGroupIDs = Set<UUID>()
    @State private var pendingDeleteRecord: ConversationArchiveRecord?
    @State private var restoreNotice: RestoreNotice?

    var body: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.conversationCornerRadius) {
            HStack(spacing: 0) {
                searchPane

                Divider()
                    .overlay(.white.opacity(0.08))

                detailPane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if let restoreNotice {
                restoreNoticeView(restoreNotice)
            }
        }
        .alert("删除归档对话？", isPresented: deleteConfirmationBinding, presenting: pendingDeleteRecord) { record in
            Button("取消", role: .cancel) {
                pendingDeleteRecord = nil
            }
            Button("删除", role: .destructive) {
                actions.delete(record.id)
                pendingDeleteRecord = nil
            }
        } message: { record in
            Text("删除后将从归档列表移除“\(record.title)”。此操作无法撤销。")
        }
    }

    private var searchPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索已归档对话", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    actions.search(query)
                }
                .onChange(of: query) {
                    actions.search(query)
                }

            List {
                ForEach(results) { record in
                    Button {
                        actions.open(record.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)

                            Text(record.projectPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeleteRecord = record
                        } label: {
                            Text("删除")
                        }
                        .padding(.leading, archiveSwipeActionSpacingAdjustment)

                        Button {
                            if actions.restore(record.id) {
                                showRestoreNotice(for: record)
                            }
                        } label: {
                            Text("恢复")
                        }
                        .tint(.blue)
                        .padding(.trailing, archiveSwipeActionSpacingAdjustment)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .padding(16)
        .frame(width: 300)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let openedConversation {
            archivedConversationView(openedConversation)
        } else {
            emptyState
        }
    }

    private func archivedConversationView(_ conversation: ConversationSession) -> some View {
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

                Text("已归档")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "archivebox")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("选择已归档对话")
                .font(.system(size: 16, weight: .semibold))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func restoreNoticeView(_ notice: RestoreNotice) -> some View {
        HStack(spacing: 4) {
            Text("已经恢复，是否")
                .foregroundStyle(.primary)

            Button {
                actions.jumpToRestored(notice.conversationID)
                restoreNotice = nil
            } label: {
                Text("跳转对话")
                    .foregroundStyle(Color.blue.opacity(0.72))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteRecord != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteRecord = nil
                }
            }
        )
    }

    private func showRestoreNotice(for record: ConversationArchiveRecord) {
        let notice = RestoreNotice(conversationID: record.id)
        restoreNotice = notice
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if restoreNotice?.id == notice.id {
                restoreNotice = nil
            }
        }
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

    private struct RestoreNotice: Equatable, Identifiable {
        let id = UUID()
        let conversationID: UUID
    }
}
