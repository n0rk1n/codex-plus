import AppKit

@MainActor
struct CodexDesktopLauncher {
    static let bundleIdentifier = "com.openai.codex"

    private static let fallbackApplicationURL = URL(fileURLWithPath: "/Applications/Codex.app")
    private static let iconRelativePath = "Contents/Resources/icon.png"

    func open() {
        guard let applicationURL = Self.applicationURL else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    static var iconImage: NSImage? {
        guard let applicationURL else {
            return nil
        }

        return NSImage(contentsOf: applicationURL.appendingPathComponent(iconRelativePath))
    }

    private static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) ??
            fallbackURLIfInstalled
    }

    private static var fallbackURLIfInstalled: URL? {
        FileManager.default.fileExists(atPath: fallbackApplicationURL.path) ? fallbackApplicationURL : nil
    }
}
