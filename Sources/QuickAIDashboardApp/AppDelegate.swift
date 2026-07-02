import AppKit
import QuickAIDashboardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let conversationCoordinator: ConversationCoordinator
    private let batteryProvider: IOKitBatteryStatusProvider
    private let codexRunner: ProcessCodexRunner
    private let windowCoordinator: WindowCoordinator
    private var hotKeyController: HotKeyController?

    override init() {
        let conversationCoordinator = ConversationCoordinator()
        let batteryProvider = IOKitBatteryStatusProvider()
        let codexRunner = ProcessCodexRunner()

        self.conversationCoordinator = conversationCoordinator
        self.batteryProvider = batteryProvider
        self.codexRunner = codexRunner
        self.windowCoordinator = WindowCoordinator(
            conversationCoordinator: conversationCoordinator,
            batteryProvider: batteryProvider,
            codexRunner: codexRunner
        )

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hotKeyController = HotKeyController { [windowCoordinator] in
            Task { @MainActor in
                windowCoordinator.handleGlobalShortcut()
            }
        }

        do {
            try hotKeyController.register()
            self.hotKeyController = hotKeyController
        } catch {
            NSLog("QuickAIDashboard hotkey registration failed: \(error)")
            presentHotKeyRegistrationFailure(error)
        }
    }

    private func presentHotKeyRegistrationFailure(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Quick AI Dashboard could not register Control-Option-Space."
        alert.informativeText = "Error: \(error)"
        alert.runModal()

        NSApp.terminate(nil)
    }
}
