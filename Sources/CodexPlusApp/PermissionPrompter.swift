import AppKit

@MainActor
struct PermissionPrompter {
    static let fullAccessWarningText = "Full Access for this conversation. Codex can make broader local changes until this task ends or you stop it."

    func confirmEnableFullAccess() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Enable Full Access?"
        alert.informativeText = Self.fullAccessWarningText
        alert.addButton(withTitle: "Enable Full Access")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func showCannotChangeWhileRunning() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Full Access cannot change while Codex is running."
        alert.informativeText = Self.fullAccessWarningText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func confirmStopRunningTaskOnClose() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Stop the running Codex task?"
        alert.informativeText = "Closing the side panel will stop the active run."
        alert.addButton(withTitle: "Stop and Close")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func confirmStopRunningTaskOnArchive() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Archive running conversation?"
        alert.informativeText = "Archiving this conversation will stop its running Codex task."
        alert.addButton(withTitle: "Stop and Archive")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
