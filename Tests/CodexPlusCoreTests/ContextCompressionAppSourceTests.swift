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
            workbenchView.contains("restoreCompressionOriginal: { store.restoreCompressionOriginal(roundID: $0) }") &&
            workbenchView.contains("rollbackCompressionVersion: { store.rollbackCompressionVersion(versionID: $0) }") &&
            store.contains("public func restoreCompressionOriginal(roundID: UUID)") &&
            store.contains("public func rollbackCompressionVersion(versionID: UUID)"),
        "workbench actions expose restore original and rollback version store operations"
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
