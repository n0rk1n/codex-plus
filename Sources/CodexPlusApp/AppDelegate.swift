import AppKit
import CodexPlusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let conversationCoordinator: ConversationCoordinator
    private let batteryProvider: IOKitBatteryStatusProvider
    private let codexRunner: ProcessCodexRunner
    private var windowCoordinator: WindowCoordinator?
    private var hotKeyController: HotKeyController?

    override init() {
        self.conversationCoordinator = ConversationCoordinator()
        self.batteryProvider = IOKitBatteryStatusProvider()
        self.codexRunner = ProcessCodexRunner()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = try makeWorkbenchStore()
            self.windowCoordinator = WindowCoordinator(
                conversationCoordinator: conversationCoordinator,
                batteryProvider: batteryProvider,
                codexRunner: codexRunner,
                workbenchStore: store
            )
        } catch {
            presentInitializationFailure(error)
            return
        }

        let hotKeyController = HotKeyController { [windowCoordinator] in
            Task { @MainActor in
                windowCoordinator?.handleGlobalShortcut()
            }
        }

        do {
            try hotKeyController.register()
            self.hotKeyController = hotKeyController
        } catch {
            NSLog("CodexPlus hotkey registration failed: \(error)")
            presentHotKeyRegistrationFailure(error)
        }
    }

    private func makeWorkbenchStore() throws -> WorkbenchStore {
        try ApplicationDataMigrator.migrateLegacyLocalDataIfNeeded()
        let databasePath = try makeDatabasePath()
        let database = try SQLiteDatabase(path: databasePath)
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let engine = CodexCLIEngine()
        return WorkbenchStore(repository: repository, engine: engine)
    }

    private func makeDatabasePath() throws -> String {
        let databasePath = ApplicationSupportPaths.databasePath()
        let databaseURL = URL(fileURLWithPath: databasePath)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return databasePath
    }

    private func presentInitializationFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Codex+ could not initialize the floating workbench."
        alert.informativeText = "Error: \(error)"
        alert.runModal()

        NSApp.terminate(nil)
    }

    private func presentHotKeyRegistrationFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Codex+ could not register Control-Option-Command-Space."
        alert.informativeText = "Error: \(error)"
        alert.runModal()

        NSApp.terminate(nil)
    }
}
