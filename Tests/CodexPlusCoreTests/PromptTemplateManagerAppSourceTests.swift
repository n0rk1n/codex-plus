import Foundation

func runPromptTemplateManagerAppSourceTests() {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    assertControlRuleFilesExist(root: root)
    assertInitialRuleNamesExist(root: root)
    assertControlWrapperMetadataRules(root: root)
    assertAppControlsUseRules(root: root)
    let managerView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift")
    )
    let settingsPanelController = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Settings/SettingsPanelController.swift")
    )
    let settingsStore = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Settings/PromptTemplateSettingsStore.swift")
    )
    let windowCoordinator = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/WindowCoordinator.swift")
    )
    let workbenchLauncherView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/WorkbenchLauncherView.swift")
    )
    let workbenchLauncherPanelController = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/WorkbenchLauncherPanelController.swift")
    )
    let workbenchView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/WorkbenchView.swift")
    )
    let workbenchConversationListView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/WorkbenchConversationListView.swift")
    )
    let conversationEventRow = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Views/ConversationEventRow.swift")
    )
    let conversationDisplayPresentation = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Views/ConversationDisplayEvent+Presentation.swift")
    )
    let markdownMessageText = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Views/MarkdownMessageText.swift")
    )
    let topProjectStripView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/TopProjectStripView.swift")
    )
    let multilineTextEditor = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Views/AppMultilineTextEditor.swift")
    )

    expect(
        managerView.contains("performOrConfirm(.select"),
        "prompt manager row selection routes through dirty-change confirmation"
    )
    expect(
        managerView.contains("performOrConfirm(.create"),
        "prompt manager create routes through dirty-change confirmation"
    )
    expect(
        managerView.contains("performOrConfirm(.copy"),
        "prompt manager copy routes through dirty-change confirmation"
    )
    expect(
        managerView.contains("保存未完成的修改？"),
        "prompt manager presents save/discard/cancel copy before context switches"
    )
    expect(
        !managerView.contains("arrow.clockwise") &&
            !managerView.contains("performOrConfirm(.reload") &&
            !managerView.contains("case reload") &&
            !managerView.contains("重新加载提示词模板"),
        "prompt manager sidebar omits the redundant reload action"
    )
    expect(
        managerView.contains("AppMultilineTextEditor(text:") &&
            multilineTextEditor.contains("textContainerInset") &&
            !managerView.contains("\n        TextEditor(text:"),
        "prompt manager multiline prompt fields use the shared AppKit text view with explicit text container inset"
    )
    expect(
        managerView.contains("CodexPicker(rule: .segmentedFilter, title: \"\", selection: sourceFilterBinding)") &&
            managerView.contains("private func templateMetadataRow(_ template: PromptTemplate) -> some View") &&
            managerView.contains("HStack(alignment: .firstTextBaseline, spacing: 8)") &&
            managerView.contains("Spacer(minLength: 8)") &&
            managerView.contains("Text(template.type.displayName)") &&
            !managerView.contains("Text(\"类型  \\(template.type.displayName)\")") &&
            managerView.contains("Text(template.source.displayName)") &&
            !managerView.contains("Text(\"来源  \\(template.source.displayName)\")"),
        "prompt manager sidebar shows type left and source right on one metadata row"
    )
    expect(
        managerView.contains("title: \"\"") &&
            managerView.contains("selection: draftTypeBinding") &&
            !managerView.contains("title: \"类型\""),
        "prompt manager type menu hides the duplicate picker label"
    )
    expect(
        managerView.contains("swipeActions(edge: .trailing)") &&
            managerView.contains("Text(\"重命名\")") &&
            managerView.contains("Text(\"删除\")") &&
            settingsStore.contains("func renameTemplate(_ id: UUID, to name: String)") &&
            settingsStore.contains("func deleteTemplate(_ id: UUID)"),
        "prompt manager user template rows provide trailing rename and delete actions"
    )
    expect(
        managerView.contains("systemImage: \"doc.on.doc\"") &&
            managerView.contains("foregroundColor: CodexColors.stateRunning") &&
            managerView.contains("headerActionLabel(systemImage: \"trash\", title: \"删除\", foregroundColor: CodexColors.stateFailed)"),
        "prompt manager header copy and delete actions are color-coded"
    )
    expect(
        managerView.contains("rule: .formHeaderCapsule") &&
            managerView.contains("rule: .formFooterCapsule"),
        "prompt manager header/footer action buttons use shared form button rules"
    )
    expect(
        managerView.contains("readOnlyTemplateControl { handle in") &&
            managerView.contains("CodexReadOnlyNoticeHost(") &&
            managerView.contains("isReadOnly: !store.isEditable") &&
            managerView.contains("rule: .promptTemplateSystemTemplate") &&
            !managerView.contains("isShowingReadOnlyTemplateNotice") &&
            !managerView.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 3)") &&
            !managerView.contains(".contentShape(Rectangle())"),
        "prompt manager read-only detail controls use the shared read-only notice host"
    )
    expect(
        settingsPanelController.contains("PromptTemplateSettingsStore(repository: repository)") &&
            settingsPanelController.contains("PromptTemplateManagerView(store: store)"),
        "settings panel keeps one prompt template store instead of recreating it on every show"
    )
    expect(
        settingsPanelController.contains("shouldClose") &&
            windowCoordinator.contains("windowShouldClose") &&
            windowCoordinator.contains("settingsPanelController.shouldClose"),
        "settings panel close is guarded by dirty-change confirmation"
    )
    expect(
        settingsPanelController.contains("private let screenProvider: ActiveScreenProvider") &&
            settingsPanelController.contains("screenProvider.activeScreen()") &&
            windowCoordinator.contains("screenProvider: screenProvider"),
        "settings panel opens on the same active screen as the workbench entry point"
    )
    expect(
        settingsPanelController.contains("hasInstalledContent") &&
            !settingsPanelController.contains("contentView == nil"),
        "settings panel installs prompt manager content instead of relying on AppKit's default empty contentView"
    )
    expect(
        settingsPanelController.contains("private let onDismiss: () -> Void") &&
            settingsPanelController.contains("dismissMonitors = EventMonitorStore()") &&
            settingsPanelController.contains("func dismiss()") &&
            settingsPanelController.contains("installDismissMonitorsIfNeeded()"),
        "settings panel owns dismissal callbacks and event monitors"
    )
    expect(
        settingsPanelController.contains("CompactEntryDismissPolicy.shouldDismissForKeyDown") &&
            settingsPanelController.contains("CompactEntryDismissPolicy.shouldDismissForMouseDown") &&
            settingsPanelController.contains("hideIfNeededForOutsideClick"),
        "settings panel dismisses for Escape and outside clicks"
    )
    expect(
        windowCoordinator.contains("workbenchPanelController.hide(showLauncher: false)") &&
            windowCoordinator.contains("showWorkbenchAfterSettingsDismissal") &&
            windowCoordinator.contains("onDismiss: { [weak self]"),
        "opening settings hides the workbench, and dismissing settings restores it"
    )
    expect(
        topProjectStripView.contains("systemName: \"gearshape\"") &&
            topProjectStripView.contains("rule: .toolbarIconCircle"),
        "workbench circular icon buttons use the shared toolbar icon rule"
    )
    expect(
        workbenchView.contains("""
    private var conversationWorkspace: some View {
        VStack(spacing: WorkbenchMetrics.verticalSpacing) {
            HStack(spacing: WorkbenchMetrics.contentColumnSpacing) {
""") &&
            workbenchView.contains("HStack(spacing: WorkbenchMetrics.contentColumnSpacing)") &&
            workbenchView.contains("WorkbenchConversationListView(") &&
            workbenchView.contains("VStack(spacing: WorkbenchMetrics.verticalSpacing)") &&
            workbenchView.contains("WorkbenchConversationView(") &&
            workbenchView.contains("WorkbenchComposerView(") &&
            workbenchView.contains("""
            }

            WorkbenchStatusBarView(state: store.snapshot.statusBar, codexUsageStatus: codexUsageMonitor.status)
        }
""") &&
            workbenchConversationListView.contains("ForEach(card.conversationSummaries)") &&
            workbenchConversationListView.contains("maxHeight: .infinity") &&
            !topProjectStripView.contains("ScrollView(.horizontal"),
        "workbench conversation page keeps the left list through chat and composer, with status at the bottom"
    )
    expect(
        conversationEventRow.contains("MarkdownMessageText(markdown: message)") &&
            conversationDisplayPresentation.contains("case .userPrompt, .assistantMessage:") &&
            markdownMessageText.contains("AttributedString(markdown: markdown") &&
            markdownMessageText.contains("Text(attributedMarkdown)") &&
            markdownMessageText.contains("Text(markdown)"),
        "conversation event rows render user and assistant messages as markdown with plain-text fallback"
    )
    expect(
        conversationEventRow.contains(".font(CodexTypography.messageBody)") &&
            readSource(root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexDesignTokens.swift"))
            .contains("static let messageBody = Font.system(size: 15)"),
        "conversation event body text uses a larger 15 point font"
    )
    expect(
        workbenchLauncherView.contains("let onActivate: () -> Void") &&
            workbenchLauncherView.contains("action: onActivate") &&
            workbenchLauncherPanelController.contains("WorkbenchLauncherView(onActivate: onOpenWorkbench)") &&
            workbenchLauncherPanelController.contains("onClick: onOpenWorkbench"),
        "workbench launcher routes both the SwiftUI button and host click handling through the real activation closure"
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

private func assertAppControlsUseRules(root: URL) {
    let appRoot = root.appendingPathComponent("Sources/CodexPlusApp")
    let files = swiftSourceFiles(under: appRoot)
    let forbiddenTokens = [
        ".buttonStyle(.plain)": "plain button styling belongs in CodexButton",
        ".textFieldStyle(": "text field styling belongs in CodexTextField",
        ".pickerStyle(": "picker styling belongs in CodexPicker",
        ".toggleStyle(": "toggle styling belongs in CodexToggleSelector",
        ".contentShape(": "control hit areas belong in rule files",
        ".glassEffect(": "control glass styling belongs in rule files or named containers",
        ".codexRectangleButtonHitArea(": "page views must not call hit-area helpers",
        ".codexCapsuleButtonHitArea(": "page views must not call hit-area helpers",
        ".codexCircularButtonHitArea(": "page views must not call hit-area helpers",
        ".codexRoundedButtonHitArea(": "page views must not call hit-area helpers",
    ]

    for file in files
    where !isControlRuleImplementationFile(file) &&
            !isSystemControlExceptionFile(file) &&
            !isControlCompatibilityFile(file) {
        let source = readSource(file)
        for (token, message) in forbiddenTokens {
            expect(
                !source.contains(token),
                "\(file.path.replacingOccurrences(of: root.path + "/", with: "")): \(message)"
            )
        }
    }
}

private func assertControlRuleFilesExist(root: URL) {
    let viewsRoot = root.appendingPathComponent("Sources/CodexPlusApp/Views")
    let requiredFiles = [
        "CodexControlRules.swift",
        "CodexButton.swift",
        "CodexTextField.swift",
        "CodexMultilineTextField.swift",
        "CodexMultilineTextEditor.swift",
        "CodexPicker.swift",
        "CodexToggleSelector.swift",
        "CodexReadOnlyNotice.swift"
    ]

    for filename in requiredFiles {
        let path = viewsRoot.appendingPathComponent(filename).path
        expect(FileManager.default.fileExists(atPath: path), "\(filename) exists")
    }
}

private func assertInitialRuleNamesExist(root: URL) {
    let rules = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexControlRules.swift")
    )
    let requiredRuleNames = [
        "case toolbarCapsule",
        "case toolbarIconCircle",
        "case composerIconCircle",
        "case workspaceCapsule",
        "case workspaceClear",
        "case rowRectangle",
        "case rowRounded(cornerRadius: CGFloat)",
        "case cardRounded(cornerRadius: CGFloat)",
        "case formHeaderCapsule",
        "case formFooterCapsule",
        "case inlineTextLink",
        "case composerInline",
        "case searchField",
        "case formField",
        "case multilinePrompt",
        "case multilineNote",
        "case longPromptEditor",
        "case segmentedFilter",
        "case requiredMenu",
        "case filterToggle"
    ]

    for ruleName in requiredRuleNames {
        expect(rules.contains(ruleName), "control rules define \(ruleName)")
    }

    expect(
        rules.contains("系统内置提示词为只读内容。如需修改，请先创建用户自定义提示词。"),
        "control rules keep the exact read-only notice copy"
    )
}

private func assertControlWrapperMetadataRules(root: URL) {
    let button = readSource(root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexButton.swift"))
    let textField = readSource(root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexTextField.swift"))
    let multilineTextField = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexMultilineTextField.swift")
    )
    let multilineTextEditor = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexMultilineTextEditor.swift")
    )
    let picker = readSource(root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexPicker.swift"))
    let toggleSelector = readSource(root.appendingPathComponent("Sources/CodexPlusApp/Views/CodexToggleSelector.swift"))

    expect(
        button.contains("var isDisabled: Bool = false") &&
            button.contains(".disabled(isDisabled)"),
        "codex button owns disabled state"
    )
    expect(
        textField.contains("var isDisabled: Bool = false") &&
            textField.contains("var help: String?") &&
            textField.contains("var accessibilityLabel: String?") &&
            textField.contains(".disabled(isDisabled)") &&
            textField.contains(".codexOptionalHelp(help)") &&
            textField.contains(".codexOptionalAccessibilityLabel(accessibilityLabel)"),
        "codex text field owns disabled, help, and accessibility metadata"
    )
    expect(
        multilineTextField.contains("var isDisabled: Bool = false") &&
            multilineTextField.contains("var help: String?") &&
            multilineTextField.contains("var accessibilityLabel: String?") &&
            multilineTextField.contains(".disabled(isDisabled)") &&
            multilineTextField.contains(".codexOptionalHelp(help)") &&
            multilineTextField.contains(".codexOptionalAccessibilityLabel(accessibilityLabel)"),
        "codex multiline text field owns disabled, help, and accessibility metadata"
    )
    expect(
        multilineTextEditor.contains("struct CodexMultilineTextEditor: View") &&
            multilineTextEditor.contains("var isDisabled: Bool = false") &&
            multilineTextEditor.contains("var help: String?") &&
            multilineTextEditor.contains("var accessibilityLabel: String?") &&
            multilineTextEditor.contains(".disabled(isDisabled)") &&
            multilineTextEditor.contains(".codexOptionalHelp(help)") &&
            multilineTextEditor.contains(".codexOptionalAccessibilityLabel(accessibilityLabel)") &&
            multilineTextEditor.contains("private struct CodexMultilineTextEditorRepresentable: NSViewRepresentable"),
        "codex multiline text editor wraps the representable and owns metadata"
    )
    expect(
        picker.contains("var isDisabled: Bool = false") &&
            picker.contains("var help: String?") &&
            picker.contains("var accessibilityLabel: String?") &&
            picker.contains(".disabled(isDisabled)") &&
            picker.contains(".codexOptionalHelp(help)") &&
            picker.contains(".codexOptionalAccessibilityLabel(accessibilityLabel)"),
        "codex picker owns disabled, help, and accessibility metadata"
    )
    expect(
        toggleSelector.contains("var isDisabled: Bool = false") &&
            toggleSelector.contains("var accessibilityLabel: String?") &&
            toggleSelector.contains(".disabled(isDisabled)") &&
            toggleSelector.contains(".codexOptionalAccessibilityLabel(accessibilityLabel)") &&
            toggleSelector.contains(".codexOptionalHelp(help)"),
        "codex toggle selector owns disabled and accessibility metadata"
    )
}

private func swiftSourceFiles(under root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        expect(false, "can enumerate \(root.path)")
        return []
    }

    return enumerator.compactMap { item in
        guard let url = item as? URL, url.pathExtension == "swift" else {
            return nil
        }
        return url
    }
}

private func isControlRuleImplementationFile(_ url: URL) -> Bool {
    [
        "CodexControlRules.swift",
        "CodexButton.swift",
        "CodexTextField.swift",
        "CodexMultilineTextField.swift",
        "CodexMultilineTextEditor.swift",
        "CodexPicker.swift",
        "CodexToggleSelector.swift",
        "CodexReadOnlyNotice.swift"
    ].contains(url.lastPathComponent)
}

private func isSystemControlExceptionFile(_ url: URL) -> Bool {
    [
        "LiquidGlassContainer.swift",
        "PermissionPrompter.swift",
        "SettingsPanelController.swift"
    ].contains(url.lastPathComponent)
}

private func isControlCompatibilityFile(_ url: URL) -> Bool {
    [
        "ButtonHitAreaModifier.swift",
        "AppMultilineTextEditor.swift"
    ].contains(url.lastPathComponent)
}
