import CodexPlusCore
import SwiftUI

struct WorkbenchConversationView: View {
    let snapshot: WorkbenchSnapshot
    let actions: ConversationActions

    @State private var expandedTechnicalGroupIDs = Set<UUID>()
    @State private var selectedCompressionRoundID: UUID?
    @State private var selectedCompressionRoundIDs = Set<UUID>()
    @State private var compressionSelectionAnchorRoundID: UUID?
    @State private var editingCompressionDraft: CompressionEditDraft?

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

            if !selectedCompressionRoundIDs.isEmpty {
                CompressionRangeActionBar(
                    selectedCount: selectedOrderedRoundIDs.count,
                    canEditSegment: selectedOrderedRoundIDs.count == 1,
                    onEdit: openCompressionEditDialog,
                    onDefaultCompress: compressSelectedRounds,
                    onExclude: excludeSelectedRounds,
                    onClear: clearCompressionSelection
                )

                Divider()
                    .overlay(CodexColors.surfaceDivider)
            }

            HStack(spacing: 0) {
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

                if selectedCompressionRoundID != nil {
                    Divider()
                        .overlay(CodexColors.surfaceDivider)

                    CompressionHistoryInspectorView(
                        presentation: snapshot.compression.timelinePresentation,
                        selectedRoundID: selectedCompressionRoundID,
                        onClose: { selectedCompressionRoundID = nil }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $editingCompressionDraft) { draft in
            CompressionEditDialog(
                roundID: draft.roundID,
                initialText: draft.initialText,
                onCancel: {
                    editingCompressionDraft = nil
                },
                onSave: { segmentKind, content in
                    actions.editCompressionSegment(draft.roundID, segmentKind, content)
                    editingCompressionDraft = nil
                    selectedCompressionRoundID = draft.roundID
                }
            )
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
            VStack(alignment: .leading, spacing: 0) {
                if let round = roundPresentation(for: event.id),
                   let boundary = round.boundary,
                   round.eventIDs.first == event.id {
                    CompressionRangeMarkerView(
                        boundary: boundary,
                        status: round.status,
                        joinedRelationship: round.joinedRelationship,
                        isSelected: selectedCompressionRoundID == round.roundID,
                        onSelect: { selectedCompressionRoundID = round.roundID }
                    )
                }

                ConversationEventRow(
                    event: event,
                    compressionPresentation: snapshot.compression.timelinePresentation.rowsByEventID[event.id]
                )
                .onTapGesture {
                    selectCompressionRound(containing: event.id)
                }
            }
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

    private func roundPresentation(for eventID: UUID) -> ConversationRoundPresentation? {
        guard let row = snapshot.compression.timelinePresentation.rowsByEventID[eventID] else {
            return nil
        }
        return snapshot.compression.timelinePresentation.rounds.first { $0.roundID == row.roundID }
    }

    private var selectedOrderedRoundIDs: [UUID] {
        snapshot.compression.timelinePresentation.rounds
            .map(\.roundID)
            .filter { selectedCompressionRoundIDs.contains($0) }
    }

    private func selectCompressionRound(containing eventID: UUID) {
        guard let round = roundPresentation(for: eventID) else {
            return
        }

        selectedCompressionRoundID = round.roundID
        if let anchor = compressionSelectionAnchorRoundID,
           anchor != round.roundID,
           let range = contiguousRoundIDs(from: anchor, to: round.roundID) {
            selectedCompressionRoundIDs = Set(range)
        } else {
            compressionSelectionAnchorRoundID = round.roundID
            selectedCompressionRoundIDs = [round.roundID]
        }
    }

    private func contiguousRoundIDs(from first: UUID, to second: UUID) -> [UUID]? {
        let roundIDs = snapshot.compression.timelinePresentation.rounds.map(\.roundID)
        guard let firstIndex = roundIDs.firstIndex(of: first),
              let secondIndex = roundIDs.firstIndex(of: second) else {
            return nil
        }
        let lower = min(firstIndex, secondIndex)
        let upper = max(firstIndex, secondIndex)
        return Array(roundIDs[lower...upper])
    }

    private func clearCompressionSelection() {
        selectedCompressionRoundIDs.removeAll()
        compressionSelectionAnchorRoundID = nil
    }

    private func compressSelectedRounds() {
        let roundIDs = selectedOrderedRoundIDs
        guard !roundIDs.isEmpty else {
            return
        }
        _ = actions.compressSelectedRounds(roundIDs)
        clearCompressionSelection()
    }

    private func excludeSelectedRounds() {
        for roundID in selectedOrderedRoundIDs {
            actions.excludeCompressionRound(roundID)
        }
        clearCompressionSelection()
    }

    private func openCompressionEditDialog() {
        guard let roundID = selectedOrderedRoundIDs.first,
              selectedOrderedRoundIDs.count == 1,
              let conversation = snapshot.activeConversation else {
            return
        }
        editingCompressionDraft = CompressionEditDraft(
            roundID: roundID,
            initialText: segmentText(roundID: roundID, segmentKind: .assistant, conversation: conversation)
        )
    }

    private func segmentText(
        roundID: UUID,
        segmentKind: CompressionSegmentKind,
        conversation: ConversationSession
    ) -> String {
        let eventIDs = snapshot.compression.timelinePresentation.rounds
            .first { $0.roundID == roundID }?
            .eventIDs ?? []
        for eventID in eventIDs {
            guard let event = conversation.events.first(where: { $0.id == eventID }) else {
                continue
            }
            switch (segmentKind, event) {
            case let (.user, .userPrompt(_, text)),
                 let (.assistant, .assistantMessage(_, text)):
                return text
            default:
                continue
            }
        }
        return ""
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

private struct CompressionEditDraft: Identifiable {
    var id: UUID { roundID }
    var roundID: UUID
    var initialText: String
}
