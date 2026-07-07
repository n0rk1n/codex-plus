import Foundation

func runPromptTemplateManagerAppSourceTests() {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
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
    let topProjectStripView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Workbench/TopProjectStripView.swift")
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
        managerView.contains("PromptTemplateMultilineEditor(") &&
            managerView.contains("textContainerInset") &&
            !managerView.contains("TextEditor(text:"),
        "prompt manager multiline prompt fields use an AppKit text view with explicit text container inset"
    )
    expect(
        managerView.contains("Picker(\"\", selection: sourceFilterBinding)") &&
            managerView.contains("Text(template.type.displayName)") &&
            !managerView.contains("Text(\"类型  \\(template.type.displayName)\")") &&
            managerView.contains("Text(template.source.displayName)") &&
            !managerView.contains("Text(\"来源  \\(template.source.displayName)\")"),
        "prompt manager sidebar removes redundant type and source labels while keeping values visible"
    )
    expect(
        managerView.contains("Picker(\"\", selection: draftTypeBinding)") &&
            !managerView.contains("Picker(\"类型\", selection: draftTypeBinding)"),
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
            managerView.contains("foregroundColor: .blue") &&
            managerView.contains("headerActionLabel(systemImage: \"trash\", title: \"删除\", foregroundColor: .red)"),
        "prompt manager header copy and delete actions are color-coded"
    )
    expect(
        managerView.contains(".codexCapsuleButtonHitArea()"),
        "prompt template manager action buttons use the shared capsule hit-area modifier"
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
            topProjectStripView.contains(".codexCircularButtonHitArea()"),
        "workbench circular icon buttons use the shared full-circle hit-area modifier"
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
