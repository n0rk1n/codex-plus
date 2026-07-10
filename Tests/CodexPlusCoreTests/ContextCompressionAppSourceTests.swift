import Foundation

func runContextCompressionAppSourceTests() {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let actionBar = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/ContextCompression/CompressionRangeActionBar.swift")
    )
    let customDialog = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/ContextCompression/CompressionCustomDialog.swift")
    )
    let conversationView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift")
    )
    let actions = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/WorkbenchActions.swift")
    )
    let workbenchView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/WorkbenchView.swift")
    )
    let store = readSource(
        root.appendingPathComponent("Sources/CodexPlusCore/WorkbenchStore.swift")
    )
    let inspector = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/ContextCompression/CompressionHistoryInspectorView.swift")
    )
    let editDialog = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/ContextCompression/CompressionEditDialog.swift")
    )

    expect(
        actionBar.contains("Label(\"不压缩\", systemImage: \"xmark.circle\")") &&
            actionBar.contains("Label(\"默认压缩\", systemImage: \"arrow.down.right.and.arrow.up.left\")") &&
            actionBar.contains("Label(\"自定义压缩\", systemImage: \"slider.horizontal.3\")") &&
            actionBar.contains("连续 \\(selectedCount) 轮") &&
            actionBar.contains("let onCustomCompress: () -> Void"),
        "compression range action bar exposes explicit no/default/custom compression controls and continuous round count"
    )
    expect(
        customDialog.contains("struct CompressionCustomDialog: View") &&
            customDialog.contains("let templates: [PromptTemplate]") &&
            customDialog.contains("CodexPicker(") &&
            customDialog.contains("AppMultilineTextEditor(") &&
            customDialog.contains("onStart(selectedTemplate, userInstruction"),
        "custom compression dialog lets users choose a prompt template and add one-time instructions"
    )
    expect(
        conversationView.contains("@State private var customCompressionDraft: CompressionCustomDraft?") &&
            conversationView.contains("CompressionCustomDialog(") &&
            conversationView.contains("onCustomCompress: openCustomCompressionDialog") &&
            conversationView.contains("actions.loadCompressionTemplates()") &&
            conversationView.contains("actions.compressSelectedRounds(roundIDs, template, userInstruction)"),
        "conversation view wires custom compression sheet through prompt templates and custom action"
    )
    expect(
        actions.contains("let loadCompressionTemplates: () -> [PromptTemplate]") &&
            actions.contains("let compressSelectedRounds: ([UUID], PromptTemplate?, String) -> (any ExecutionHandle)?"),
        "conversation actions expose template loading and custom compression parameters"
    )
    expect(
        workbenchView.contains("loadCompressionTemplates: { store.loadCompressionTemplates() }") &&
            workbenchView.contains("compressSelectedRounds: { store.compressSelectedRounds(roundIDs: $0, template: $1, userInstruction: $2) }"),
        "workbench view maps custom compression action parameters to the store"
    )
    expect(
        store.contains("public func loadCompressionTemplates() -> [PromptTemplate]") &&
            store.contains("mode: template == nil ? .defaultTemplate : .customTemplate") &&
            store.contains("template: template ?? defaultTemplate"),
        "store action bridge keeps default compression low-friction and marks custom compression as customTemplate"
    )
    expect(
        inspector.contains("let onRestoreOriginal: (UUID) -> Void") &&
            inspector.contains("let onRollback: (UUID) -> Void") &&
            inspector.contains("let onContinueCompression: ([UUID]) -> Void") &&
            inspector.contains("Label(\"恢复原文\", systemImage: \"arrow.uturn.backward\")") &&
            inspector.contains("Label(\"回滚到此版本\", systemImage: \"clock.arrow.circlepath\")") &&
            inspector.contains("Label(\"继续压缩\", systemImage: \"arrow.down.right.and.arrow.up.left.circle\")"),
        "compression inspector exposes restore original, rollback, and continue compression actions"
    )
    expect(
        inspector.contains("private func selectedActionGroup(for round: ConversationRoundPresentation) -> some View") &&
            inspector.contains("ViewThatFits(in: .horizontal)") &&
            inspector.contains("private func selectedActionButtons(for round: ConversationRoundPresentation) -> some View") &&
            inspector.contains("selectedActionButtons(for: round)") &&
            inspector.contains("private func rollbackAction(for item: CompressionVersionHistoryPresentation) -> some View") &&
            inspector.contains(".frame(maxWidth: .infinity, alignment: .leading)"),
        "compression inspector action controls adapt to narrow widths instead of forcing fixed horizontal button rows"
    )
    expect(
        inspector.contains("Text(\"发送时使用\")") &&
            !inspector.contains("Text(\"当前活动标记\")") &&
            !inspector.contains("ForEach(markedRounds)"),
        "compression inspector summarizes only the selected round's active send version instead of listing every marked round"
    )
    expect(
        inspector.contains("Text(item.versionOrderLabel)") &&
            inspector.contains("private func versionOrderBadge") &&
            inspector.contains("historyOrderBackground(for: item)") &&
            inspector.contains("historyOrderForeground(for: item)"),
        "compression inspector displays each history row's chronological version order label"
    )
    expect(
        editDialog.contains(".preferredColorScheme(.dark)") &&
            editDialog.contains(".fill(CodexColors.surfaceSubtle)") &&
            editDialog.contains(".background(.regularMaterial"),
        "compression edit dialog keeps text readable by using a dark sheet surface and visible editor background"
    )
    expect(
        editDialog.contains("@State private var userText: String") &&
            editDialog.contains("@State private var aiBlocks: [CompressionEditBlock]") &&
            editDialog.contains("editor(title: \"用户\"") &&
            editDialog.contains("ForEach(aiBlocks.indices") &&
            editDialog.contains("detailsTextBlock(") &&
            editDialog.contains("case .assistant") &&
            editDialog.contains("case .details") &&
            !editDialog.contains("CodexPicker("),
        "compression edit dialog shows user editing plus ordered plain Details text and editable AI blocks"
    )
    expect(
        editDialog.contains("private func detailsTextBlock") &&
            !editDialog.contains("readOnlyDetailsBlock") &&
            !editDialog.contains("Image(systemName: \"chevron.right\")"),
        "compression edit dialog renders Details as plain timeline text instead of a read-only control block"
    )
    expect(
        editDialog.contains(".frame(minWidth: 880") &&
            editDialog.contains("minHeight: 640") &&
            editDialog.contains("ScrollView") &&
            editDialog.contains("onSave(modelInputText)"),
        "compression edit dialog opens as a large editing surface and saves the assembled model input"
    )
    expect(
        editDialog.contains("private var hasUnsavedChanges: Bool") &&
            editDialog.contains("private func requestClose()") &&
            editDialog.contains("isShowingUnsavedConfirmation = true") &&
            editDialog.contains(".alert(\"尚未保存\"") &&
            editDialog.contains("Button(\"保存\")") &&
            editDialog.contains("Button(\"不保存\", role: .destructive)") &&
            editDialog.contains("Button(\"继续编辑\", role: .cancel)") &&
            editDialog.contains(".onTapGesture(perform: requestClose)"),
        "compression edit dialog prompts before closing when edited content has not been saved"
    )
    expect(
        conversationView.contains("compressionEditOverlay") &&
            conversationView.contains("if let draft = editingCompressionDraft") &&
            !conversationView.contains(".sheet(item: $editingCompressionDraft)"),
        "compression edit dialog is presented in a controlled overlay so outside clicks cannot dismiss it implicitly"
    )
    expect(
        conversationView.contains("onRestoreOriginal: restoreSelectedCompressionOriginal") &&
            conversationView.contains("onRollback: rollbackCompressionVersion") &&
            conversationView.contains("onContinueCompression: continueCompression") &&
            conversationView.contains("actions.restoreCompressionOriginal(roundID)") &&
            conversationView.contains("actions.rollbackCompressionVersion(versionID)") &&
            conversationView.contains("actions.compressSelectedRounds(roundIDs, nil, \"\")"),
        "conversation view wires inspector recovery actions to store-backed compression actions"
    )
    expect(
            actions.contains("let restoreCompressionOriginal: (UUID) -> Void") &&
            actions.contains("let rollbackCompressionVersion: (UUID) -> Void") &&
            actions.contains("let editCompressionRound: (UUID, String, String) -> Void") &&
            actions.contains("let editCompressionRoundContent: (UUID, String) -> Void") &&
            conversationView.contains("actions.editCompressionRoundContent(draft.roundID, content)") &&
            conversationView.contains("let editParts = compressionEditParts(roundID: roundID, conversation: conversation)") &&
            conversationView.contains("initialUserText: editParts.user") &&
            conversationView.contains("initialAIBlocks: editParts.aiBlocks") &&
            conversationView.contains("aiBlocks.append(.details(") &&
            conversationView.contains("aiBlocks.append(.assistant(") &&
            workbenchView.contains("editCompressionRound: { store.editCompressionRound(roundID: $0, userContent: $1, assistantContent: $2) }") &&
            workbenchView.contains("editCompressionRoundContent: { store.editCompressionRoundContent(roundID: $0, content: $1) }") &&
            workbenchView.contains("restoreCompressionOriginal: { store.restoreCompressionOriginal(roundID: $0) }") &&
            workbenchView.contains("rollbackCompressionVersion: { store.rollbackCompressionVersion(versionID: $0) }") &&
            store.contains("public func editCompressionRound(") &&
            store.contains("try contextCompressionService.editRoundSegments(") &&
            store.contains("public func editCompressionRoundContent(") &&
            store.contains("try contextCompressionService.editRound(") &&
            store.contains("public func restoreCompressionOriginal(roundID: UUID)") &&
            store.contains("public func rollbackCompressionVersion(versionID: UUID)"),
        "workbench actions expose ordered full-content editing, restore original, and rollback version store operations"
    )
}

private func readSource(_ url: URL) -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        expect(false, "source file is readable: \(url.path)")
        return ""
    }
}
