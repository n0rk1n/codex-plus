import AppKit
import CodexPlusCore

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let workbenchStore: WorkbenchStore
    private let promptTemplateRepository: any PromptTemplateRepository
    private let batteryMonitor: BatteryStatusMonitor
    private let codexUsageMonitor: CodexUsageMonitor
    private let dailyTokenUsageMonitor: DailyTokenUsageMonitor
    private let panelFactory = PanelFactory()
    private let screenProvider = ActiveScreenProvider()

    private lazy var workbenchPanelController = WorkbenchPanelController(
        panelFactory: panelFactory,
        screenProvider: screenProvider,
        store: workbenchStore,
        codexUsageMonitor: codexUsageMonitor,
        panelDelegate: self,
        onOpenSettings: { [weak self] in
            self?.showSettings()
        },
        onShow: { [weak self] in
            self?.workbenchLauncherPanelController.hide()
        },
        onHide: { [weak self] in
            self?.workbenchLauncherPanelController.show()
        }
    )

    private lazy var settingsPanelController = SettingsPanelController(
        panelFactory: panelFactory,
        panelDelegate: self,
        repository: promptTemplateRepository
    )

    private lazy var workbenchLauncherPanelController = WorkbenchLauncherPanelController(
        screenProvider: screenProvider,
        panelDelegate: self,
        onOpenWorkbench: { [weak self] in
            self?.showWorkbenchFromLauncher()
        }
    )

    init(
        batteryProvider: any BatteryStatusProviding,
        workbenchStore: WorkbenchStore,
        promptTemplateRepository: any PromptTemplateRepository
    ) {
        self.workbenchStore = workbenchStore
        self.promptTemplateRepository = promptTemplateRepository
        self.batteryMonitor = BatteryStatusMonitor(provider: batteryProvider)
        self.codexUsageMonitor = CodexUsageMonitor(provider: LocalCodexUsageProvider())
        self.dailyTokenUsageMonitor = DailyTokenUsageMonitor(provider: LocalDailyTokenUsageProvider())

        super.init()
        codexUsageMonitor.start()
        dailyTokenUsageMonitor.start()
        workbenchLauncherPanelController.show()
    }

    func handleGlobalShortcut() {
        workbenchPanelController.toggle()
    }

    private func showWorkbenchFromLauncher() {
        workbenchLauncherPanelController.hide()
        workbenchPanelController.show()
    }

    private func showSettings() {
        settingsPanelController.show()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? GlassPanel else {
            return
        }

        if settingsPanelController.recordMove(of: panel) {
            return
        }

        if workbenchPanelController.recordMove(of: panel) {
            return
        }

        if workbenchLauncherPanelController.recordMove(of: panel) {
            return
        }
    }
}
