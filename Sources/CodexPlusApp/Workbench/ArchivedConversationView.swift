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
                    .overlay(CodexColors.surfaceDivider)

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
            CodexTextField(
                rule: .searchField,
                placeholder: "搜索已归档对话",
                text: $query,
                onChange: { newQuery in
                    actions.search(newQuery)
                },
                onSubmit: { actions.search(query) }
            )

            List {
                    ForEach(results) { record in
                        CodexButton(rule: .rowRectangle, action: {
                            actions.open(record.id)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.title)
                                    .font(CodexTypography.menuPrimary)
                                    .lineLimit(1)

                                Text(record.projectPath)
                                .font(CodexTypography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
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
                        .tint(CodexColors.stateRunning)
                        .padding(.trailing, archiveSwipeActionSpacingAdjustment)
                    }
                }
            }
            .listStyle(.sidebar)
        }
            .padding(CodexSpacing.contentStack)
            .frame(width: WorkbenchMetrics.conversationListWidth)
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
                        .font(CodexTypography.contentTitle)
                        .lineLimit(1)

                    Text(conversation.workspacePath)
                        .font(CodexTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Text("已归档")
                    .font(CodexTypography.statusBar)
                    .foregroundStyle(.secondary)
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
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: "archivebox")
                .font(CodexTypography.panelHeader)
                .foregroundStyle(.secondary)

            Text("选择已归档对话")
                .font(CodexTypography.sectionTitle)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func restoreNoticeView(_ notice: RestoreNotice) -> some View {
        HStack(spacing: 4) {
            Text("已经恢复，是否")
                .foregroundStyle(.primary)

            CodexButton(rule: .inlineTextLink, action: {
                actions.jumpToRestored(notice.conversationID)
                restoreNotice = nil
            }) {
                Text("跳转对话")
                    .foregroundStyle(CodexColors.stateRunning.opacity(0.72))
            }
        }
        .font(CodexTypography.restoreNoticeAction)
        .padding(.horizontal, CodexSpacing.compactInline)
        .padding(.vertical, CodexSpacing.tightInline)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CodexRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CodexRadius.badge, style: .continuous)
                    .stroke(CodexColors.surfaceStroke, lineWidth: 1)
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

    private struct RestoreNotice: Equatable, Identifiable {
        let id = UUID()
        let conversationID: UUID
    }
}
