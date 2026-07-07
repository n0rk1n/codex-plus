import Foundation

func runPromptTemplateManagerAppSourceTests() {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let managerView = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift")
    )
    let settingsPanelController = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/Settings/SettingsPanelController.swift")
    )
    let windowCoordinator = readSource(
        root.appendingPathComponent("Sources/CodexPlusApp/WindowCoordinator.swift")
    )

    expect(
        managerView.contains("performOrConfirm(.select"),
        "prompt manager row selection routes through dirty-change confirmation"
    )
    expect(
        managerView.contains("performOrConfirm(.reload"),
        "prompt manager reload routes through dirty-change confirmation"
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
}

private func readSource(_ url: URL) -> String {
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        expect(false, "source file is readable: \(url.path)")
        return ""
    }
}
