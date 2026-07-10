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
    @State private var customCompressionDraft: CompressionCustomDraft?

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
        ZStack {
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
                        onCustomCompress: openCustomCompressionDialog,
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
                            onRestoreOriginal: restoreSelectedCompressionOriginal,
                            onRollback: rollbackCompressionVersion,
                            onContinueCompression: continueCompression,
                            onClose: { selectedCompressionRoundID = nil }
                        )
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }

            compressionEditOverlay
        }
        .sheet(item: $customCompressionDraft) { draft in
            CompressionCustomDialog(
                roundCount: draft.roundIDs.count,
                templates: draft.templates,
                onCancel: {
                    customCompressionDraft = nil
                },
                onStart: { template, userInstruction in
                    let roundIDs = draft.roundIDs
                    _ = actions.compressSelectedRounds(roundIDs, template, userInstruction)
                    customCompressionDraft = nil
                    clearCompressionSelection()
                }
            )
        }
    }

    @ViewBuilder
    private var compressionEditOverlay: some View {
        if let draft = editingCompressionDraft {
            CompressionEditDialog(
                roundID: draft.roundID,
                initialUserText: draft.initialUserText,
                initialAIBlocks: draft.initialAIBlocks,
                onCancel: {
                    editingCompressionDraft = nil
                },
                onSave: { content in
                    actions.editCompressionRoundContent(draft.roundID, content)
                    editingCompressionDraft = nil
                    selectedCompressionRoundID = draft.roundID
                }
            )
            .transition(.opacity)
            .zIndex(10)
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
                    compressionPresentation: snapshot.compression.timelinePresentation.rowsByEventID[event.id],
                    isCompressionHighlighted: isCompressionEventHighlighted(event.id)
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

    private func isCompressionEventHighlighted(_ eventID: UUID) -> Bool {
        guard let selectedCompressionRoundID,
              let row = snapshot.compression.timelinePresentation.rowsByEventID[eventID] else {
            return false
        }
        return row.roundID == selectedCompressionRoundID
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
        _ = actions.compressSelectedRounds(roundIDs, nil, "")
        clearCompressionSelection()
    }

    private func openCustomCompressionDialog() {
        let roundIDs = selectedOrderedRoundIDs
        guard !roundIDs.isEmpty else {
            return
        }
        customCompressionDraft = CompressionCustomDraft(
            roundIDs: roundIDs,
            templates: actions.loadCompressionTemplates()
        )
    }

    private func excludeSelectedRounds() {
        for roundID in selectedOrderedRoundIDs {
            actions.excludeCompressionRound(roundID)
        }
        clearCompressionSelection()
    }

    private func restoreSelectedCompressionOriginal(_ roundID: UUID) {
        actions.restoreCompressionOriginal(roundID)
        selectedCompressionRoundID = roundID
        selectedCompressionRoundIDs = [roundID]
        compressionSelectionAnchorRoundID = roundID
    }

    private func rollbackCompressionVersion(_ versionID: UUID) {
        actions.rollbackCompressionVersion(versionID)
    }

    private func continueCompression(_ roundIDs: [UUID]) {
        guard !roundIDs.isEmpty else {
            return
        }
        _ = actions.compressSelectedRounds(roundIDs, nil, "")
        selectedCompressionRoundIDs = Set(roundIDs)
        compressionSelectionAnchorRoundID = roundIDs.first
    }

    private func openCompressionEditDialog() {
        guard let roundID = selectedOrderedRoundIDs.first,
              selectedOrderedRoundIDs.count == 1,
              let conversation = snapshot.activeConversation else {
            return
        }
        let editParts = compressionEditParts(roundID: roundID, conversation: conversation)
        editingCompressionDraft = CompressionEditDraft(
            roundID: roundID,
            initialUserText: editParts.user,
            initialAIBlocks: editParts.aiBlocks
        )
    }

    private func compressionEditParts(
        roundID: UUID,
        conversation: ConversationSession
    ) -> (user: String, aiBlocks: [CompressionEditBlock]) {
        let eventIDs = snapshot.compression.timelinePresentation.rounds
            .first { $0.roundID == roundID }?
            .eventIDs ?? []
        var userTexts: [String] = []
        var aiBlocks: [CompressionEditBlock] = []
        var technicalEvents: [ConversationDisplayEvent] = []

        func flushTechnicalEvents() {
            guard let firstEvent = technicalEvents.first else {
                return
            }
            aiBlocks.append(.details(
                id: firstEvent.id,
                title: "Details · \(countLabel(technicalEvents.count, singular: "event", plural: "events"))",
                subtitle: detailSummaryText(for: technicalEvents),
                modelInputText: technicalEvents
                    .map(modelInputText)
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            ))
            technicalEvents.removeAll(keepingCapacity: true)
        }

        for eventID in eventIDs {
            guard let event = conversation.events.first(where: { $0.id == eventID }) else {
                continue
            }
            switch event {
            case let .userPrompt(_, text):
                userTexts.append(text)
            case let .assistantMessage(_, text):
                flushTechnicalEvents()
                aiBlocks.append(.assistant(id: event.id, text: text))
            case .status, .command, .parseWarning:
                technicalEvents.append(event)
            case let .error(id, text):
                flushTechnicalEvents()
                aiBlocks.append(.details(id: id, title: "Error", subtitle: text, modelInputText: text))
            }
        }
        flushTechnicalEvents()
        return (
            user: userTexts.joined(separator: "\n\n"),
            aiBlocks: aiBlocks
        )
    }

    private func detailSummaryText(for events: [ConversationDisplayEvent]) -> String {
        var parts: [String] = []
        let statusCount = events.filter(\.isStatusTimelineEvent).count
        let commandCount = events.filter(\.isCommandTimelineEvent).count
        let warningCount = events.filter(\.isParseWarningTimelineEvent).count

        if statusCount > 0 {
            parts.append(countLabel(statusCount, singular: "status", plural: "statuses"))
        }
        if commandCount > 0 {
            parts.append(countLabel(commandCount, singular: "command", plural: "commands"))
        }
        if warningCount > 0 {
            parts.append(countLabel(warningCount, singular: "warning", plural: "warnings"))
        }

        return parts.joined(separator: ", ")
    }

    private func modelInputText(for event: ConversationDisplayEvent) -> String {
        switch event {
        case let .userPrompt(_, text),
             let .status(_, text),
             let .assistantMessage(_, text),
             let .error(_, text),
             let .parseWarning(_, text):
            return text
        case let .command(_, _, command, _):
            return command
        }
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
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
    var initialUserText: String
    var initialAIBlocks: [CompressionEditBlock]
}

private struct CompressionCustomDraft: Identifiable {
    let id = UUID()
    var roundIDs: [UUID]
    var templates: [PromptTemplate]
}
