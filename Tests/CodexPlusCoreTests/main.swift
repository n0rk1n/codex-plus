import Foundation
import CoreGraphics
import CodexPlusCore

var failures: [String] = []
var assertionCount = 0

@MainActor
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertionCount += 1

    if !condition() {
        failures.append(message)
    }
}

final class LockedRunCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedEvents: [CodexEvent] = []
    private var capturedResults: [CodexRunResult] = []

    func appendEvent(_ event: CodexEvent) {
        lock.lock()
        defer {
            lock.unlock()
        }

        capturedEvents.append(event)
    }

    func appendResult(_ result: CodexRunResult) {
        lock.lock()
        defer {
            lock.unlock()
        }

        capturedResults.append(result)
    }

    func events() -> [CodexEvent] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedEvents
    }

    func results() -> [CodexRunResult] {
        lock.lock()
        defer {
            lock.unlock()
        }

        return capturedResults
    }
}

final class SequenceBatteryProvider: BatteryStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [BatteryStatus]

    init(_ statuses: [BatteryStatus]) {
        self.statuses = statuses
    }

    func currentStatus() -> BatteryStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !statuses.isEmpty else {
            return .unknown
        }

        return statuses.removeFirst()
    }
}

final class SequenceCodexUsageProvider: CodexUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [CodexUsageStatus]

    init(_ statuses: [CodexUsageStatus]) {
        self.statuses = statuses
    }

    func currentStatus() -> CodexUsageStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !statuses.isEmpty else {
            return .unknown
        }

        return statuses.removeFirst()
    }
}

final class SequenceDailyTokenProvider: DailyTokenUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [DailyTokenStatus]

    init(_ statuses: [DailyTokenStatus]) {
        self.statuses = statuses
    }

    func currentStatus() -> DailyTokenStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !statuses.isEmpty else {
            return .unknown
        }

        return statuses.removeFirst()
    }
}

final class MemoryCodexUsageStatusCache: CodexUsageStatusCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: CodexUsageStatus?
    private var savedStatusValue: CodexUsageStatus?

    init(_ storedStatus: CodexUsageStatus? = nil) {
        self.storedStatus = storedStatus
    }

    func loadStatus() -> CodexUsageStatus? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return storedStatus
    }

    func saveStatus(_ status: CodexUsageStatus) {
        lock.lock()
        defer {
            lock.unlock()
        }

        savedStatusValue = status
        storedStatus = status
    }

    var savedStatus: CodexUsageStatus? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return savedStatusValue
    }
}

final class MemoryDailyTokenStatusCache: DailyTokenStatusCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: DailyTokenStatus?
    private var savedStatusValue: DailyTokenStatus?

    init(_ storedStatus: DailyTokenStatus? = nil) {
        self.storedStatus = storedStatus
    }

    func loadStatus() -> DailyTokenStatus? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return storedStatus
    }

    func saveStatus(_ status: DailyTokenStatus) {
        lock.lock()
        defer {
            lock.unlock()
        }

        savedStatusValue = status
        storedStatus = status
    }

    var savedStatus: DailyTokenStatus? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return savedStatusValue
    }
}

final class BlockingCodexUsageProvider: CodexUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let status: CodexUsageStatus
    private var callWasOnMainThreadValue: Bool?

    init(status: CodexUsageStatus) {
        self.status = status
    }

    func currentStatus() -> CodexUsageStatus {
        lock.lock()
        callWasOnMainThreadValue = Thread.isMainThread
        lock.unlock()

        started.signal()
        _ = releaseSemaphore.wait(timeout: .now() + .seconds(2))
        finished.signal()

        return status
    }

    func release() {
        releaseSemaphore.signal()
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + .seconds(2)) == .success
    }

    func waitUntilFinished() -> Bool {
        finished.wait(timeout: .now() + .seconds(2)) == .success
    }

    var callWasOnMainThread: Bool? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return callWasOnMainThreadValue
    }
}

final class BlockingDailyTokenProvider: DailyTokenUsageProviding, @unchecked Sendable {
    private let started = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let status: DailyTokenStatus

    init(status: DailyTokenStatus) {
        self.status = status
    }

    func currentStatus() -> DailyTokenStatus {
        started.signal()
        _ = releaseSemaphore.wait(timeout: .now() + .seconds(2))
        finished.signal()

        return status
    }

    func release() {
        releaseSemaphore.signal()
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + .seconds(2)) == .success
    }

    func waitUntilFinished() -> Bool {
        finished.wait(timeout: .now() + .seconds(2)) == .success
    }
}

@MainActor
func makeTemporaryScript(named name: String, contents: String) -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "codex-plus-\(UUID().uuidString)-\(name).sh"
    )

    do {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        expect(false, "temporary script \(name) can be written")
    }

    return url.path
}

@MainActor
func makeTemporaryDirectory(named name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "codex-plus-\(UUID().uuidString)-\(name)",
        isDirectory: true
    )

    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        expect(false, "temporary directory \(name) can be created")
    }

    return url
}

@MainActor
func writeText(_ text: String, to url: URL) {
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        expect(false, "temporary text file \(url.lastPathComponent) can be written")
    }
}

@MainActor
func setModificationDate(_ date: Date, for url: URL) {
    do {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    } catch {
        expect(false, "temporary file \(url.lastPathComponent) modification date can be set")
    }
}

@MainActor
func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if condition() {
            return true
        }

        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }

    return condition()
}

func agentMessageTexts(from events: [CodexEvent]) -> [String] {
    events.compactMap { event in
        if case let .agentMessage(text) = event {
            return text
        }

        return nil
    }
}

func jsonObject(from line: String) -> [String: Any] {
    guard
        let data = line.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return [:]
    }

    return object
}

func jsonValue(_ object: [String: Any], _ path: String...) -> Any? {
    var current: Any? = object

    for key in path {
        current = (current as? [String: Any])?[key]
    }

    return current
}

@MainActor
func explicitPackageProductNames(packageRoot: URL) -> [String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "package", "dump-package"]
    process.currentDirectoryURL = packageRoot

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        expect(false, "swift package dump-package can run")
        return []
    }

    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        expect(false, "swift package dump-package exits successfully")
        return []
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let products = object["products"] as? [[String: Any]]
    else {
        expect(false, "swift package dump-package output contains products JSON")
        return []
    }

    return products.compactMap { product in
        product["name"] as? String
    }
}

@MainActor
func expectCodexPlusNaming() {
    let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let expectedPaths = [
        "Sources/CodexPlusCore",
        "Sources/CodexPlusApp",
        "Tests/CodexPlusCoreTests"
    ]

    for expectedPath in expectedPaths {
        let exists = FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent(expectedPath).path
        )
        expect(exists, "Codex+ project path exists: \(expectedPath)")
    }

    let packageText = (try? String(contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)) ?? ""
    let coreBatteryText = (try? String(
        contentsOf: packageRoot.appendingPathComponent("Sources/CodexPlusCore/BatteryStatus.swift"),
        encoding: .utf8
    )) ?? ""
    let appBatteryProviderPath = packageRoot.appendingPathComponent(
        "Sources/CodexPlusApp/IOKitBatteryStatusProvider.swift"
    )

    expect(packageText.contains(#"name: "codex-plus""#), "Swift package uses codex-plus slug name")
    expect(
        explicitPackageProductNames(packageRoot: packageRoot) == ["CodexPlusApp"],
        "Swift package explicitly exposes only CodexPlusApp"
    )
    expect(!coreBatteryText.contains("IOKit"), "CodexPlusCore BatteryStatus does not import or reference IOKit")
    expect(
        FileManager.default.fileExists(atPath: appBatteryProviderPath.path),
        "CodexPlusApp owns IOKitBatteryStatusProvider"
    )

    let legacyFragments = [
        "Quick" + "AIDashboard",
        "Quick" + " AI " + "Dashboard",
        "quick" + "-ai-" + "dashboard"
    ]
    let filesToScan = [
        packageRoot.appendingPathComponent("Package.swift"),
        packageRoot.appendingPathComponent("Sources/CodexPlusCore/CodexUsageMonitor.swift"),
        packageRoot.appendingPathComponent("Sources/CodexPlusApp/AppDelegate.swift")
    ]

    for fileURL in filesToScan {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        for fragment in legacyFragments {
            expect(!text.contains(fragment), "legacy project name '\(fragment)' is removed from \(fileURL.lastPathComponent)")
        }
    }
}

@MainActor
func expectNoCodexDesktopHandoffIntegration() {
    let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let removedSourceFiles = [
        "Sources/CodexPlusCore/CodexAppServerProtocol.swift",
        "Sources/CodexPlusCore/ProcessCodexAppServerHandoffRunner.swift"
    ]

    for sourceFile in removedSourceFiles {
        let exists = FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent(sourceFile).path
        )
        expect(!exists, "Codex Desktop app-server handoff source file is removed: \(sourceFile)")
    }

    let appSources = [
        "Sources/CodexPlusApp/AppDelegate.swift",
        "Sources/CodexPlusApp/WindowCoordinator.swift"
    ]
    let forbiddenFragments = [
        "CodexAppServer",
        "startCodexAppHandoff",
        "codex://threads",
        "codex app-server",
        "com.openai.codex"
    ]

    for sourceFile in appSources {
        let url = packageRoot.appendingPathComponent(sourceFile)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        for fragment in forbiddenFragments {
            expect(!text.contains(fragment), "Codex Desktop handoff fragment '\(fragment)' is removed from \(sourceFile)")
        }
    }
}

@MainActor
func expectCodexDesktopLauncherIntegration() {
    let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let launcherPath = "Sources/CodexPlusApp/CodexDesktopLauncher.swift"
    let tilePath = "Sources/CodexPlusApp/Views/CodexDesktopTileView.swift"
    let batteryTilePath = "Sources/CodexPlusApp/Views/BatteryTileView.swift"
    let codexUsageTilePath = "Sources/CodexPlusApp/Views/CodexUsageRingTileView.swift"
    let dailyTokenTilePath = "Sources/CodexPlusApp/Views/DailyTokenTileView.swift"
    let metricTileLayoutPath = "Sources/CodexPlusApp/Views/CompactDashboardMetricTileLayout.swift"
    let compactEntryPath = "Sources/CodexPlusApp/Views/CompactEntryView.swift"
    let compactEntryHostPath = "Sources/CodexPlusApp/Views/CompactEntryHostView.swift"
    let conversationViewPath = "Sources/CodexPlusApp/Views/ConversationView.swift"
    let compactControllerPath = "Sources/CodexPlusApp/CompactPanelController.swift"
    let sidePanelControllerPath = "Sources/CodexPlusApp/SidePanelController.swift"
    let windowCoordinatorPath = "Sources/CodexPlusApp/WindowCoordinator.swift"
    let liquidGlassPath = "Sources/CodexPlusApp/Views/LiquidGlassContainer.swift"
    let glassPanelPath = "Sources/CodexPlusApp/GlassPanel.swift"

    for sourceFile in [launcherPath, tilePath, batteryTilePath, codexUsageTilePath, dailyTokenTilePath] {
        let exists = FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent(sourceFile).path
        )
        expect(exists, "Codex Desktop launcher source exists: \(sourceFile)")
    }

    let launcherText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(launcherPath),
        encoding: .utf8
    )) ?? ""
    expect(launcherText.contains("NSWorkspace"), "Codex Desktop launcher uses NSWorkspace")
    expect(
        launcherText.contains(#""com.openai.codex""#),
        "Codex Desktop launcher targets the Codex bundle identifier"
    )
    expect(launcherText.contains("icon.png"), "Codex Desktop launcher loads a PNG app icon")
    expect(!launcherText.contains("codex app-server"), "Codex Desktop launcher does not restore app-server handoff")
    expect(!launcherText.contains("codex://threads"), "Codex Desktop launcher does not restore thread deep-link handoff")

    let tileText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(tilePath),
        encoding: .utf8
    )) ?? ""
    expect(tileText.contains("CodexDesktopTileView"), "compact entry has a Codex Desktop tile view")
    expect(tileText.contains("Image(nsImage:"), "Codex Desktop tile renders the PNG image")

    let compactEntryText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(compactEntryPath),
        encoding: .utf8
    )) ?? ""
    let compactEntryHostText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(compactEntryHostPath),
        encoding: .utf8
    )) ?? ""
    let conversationViewText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(conversationViewPath),
        encoding: .utf8
    )) ?? ""
    expect(compactEntryText.contains("CodexDesktopTileView"), "compact entry renders Codex Desktop tile above prompt")
    expect(compactEntryText.contains("case .codexDesktop"), "Codex Desktop tile is part of dashboard tile row")
    expect(
        compactEntryText.contains("CompactDashboardTileDragPolicy.tileStripWidth"),
        "compact entry dashboard row uses the shared full tile strip width"
    )
    expect(
        compactEntryText.contains("LiquidGlassScene(padding: 18)")
            && !compactEntryText.contains("GlassEffectContainer"),
        "compact entry uses the shared liquid glass scene component"
    )
    expect(
        compactEntryText.contains("promptPlaceholderColor")
            && compactEntryText.contains("TextField(text: $prompt, axis: .vertical)")
            && compactEntryText.contains(#"Text("Ask Codex...")"#),
        "compact entry prompt uses an explicit placeholder color so Ask Codex does not drift with the sampled background"
    )
    expect(
        compactEntryText.contains("promptForegroundColor")
            && compactEntryText.contains("promptIconColor"),
        "compact entry prompt text and icon use stable foreground colors"
    )
    expect(
        compactEntryHostText.contains("codexUsageIsRefreshing: codexUsageMonitor.isRefreshing")
            && compactEntryHostText.contains("dailyTokenIsRefreshing: dailyTokenUsageMonitor.isRefreshing"),
        "compact entry host passes monitor refresh state into the compact entry view"
    )
    expect(
        compactEntryText.contains("let codexUsageIsRefreshing: Bool")
            && compactEntryText.contains("let dailyTokenIsRefreshing: Bool")
            && compactEntryText.contains("CodexUsageRingTileView(status: codexUsageStatus, isRefreshing: codexUsageIsRefreshing)")
            && compactEntryText.contains("DailyTokenTileView(status: dailyTokenStatus, isRefreshing: dailyTokenIsRefreshing)"),
        "compact entry forwards refresh state to the usage and token tiles"
    )
    expect(
        compactEntryText.contains("LiquidGlassContainer(cornerRadius: 24)")
            && !compactEntryText.contains("surface: .compactPrompt"),
        "compact entry prompt uses the plain system glass container"
    )
    expect(
        !compactEntryText.contains(#".environment(\.colorScheme, .dark)"#),
        "compact entry does not own a page-specific color scheme override"
    )
    expect(
        conversationViewText.contains("LiquidGlassScene(padding: 14, minWidth: 360, minHeight: 420)")
            && conversationViewText.contains("private var panelContent: some View")
            && !conversationViewText.contains("GlassEffectContainer")
            && !conversationViewText.contains("LiquidGlassContainer(cornerRadius: 28)"),
        "conversation panel uses the same shared liquid glass scene component without drawing a large blurred outer shell"
    )
    expect(
        [tilePath, batteryTilePath, codexUsageTilePath, dailyTokenTilePath].allSatisfy { sourceFile in
            let text = (try? String(
                contentsOf: packageRoot.appendingPathComponent(sourceFile),
                encoding: .utf8
            )) ?? ""

            return text.contains("LiquidGlassContainer(cornerRadius: 22)")
                && !text.contains("surface: .compactPrompt")
        },
        "compact dashboard tiles use the plain system glass container"
    )
    let codexUsageTileText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(codexUsageTilePath),
        encoding: .utf8
    )) ?? ""
    let dailyTokenTileText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(dailyTokenTilePath),
        encoding: .utf8
    )) ?? ""
    let metricTileLayoutText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(metricTileLayoutPath),
        encoding: .utf8
    )) ?? ""
    expect(
        metricTileLayoutText.contains("metricRowHeight")
            && metricTileLayoutText.contains("labelRowHeight")
            && metricTileLayoutText.contains("valueRowHeight")
            && metricTileLayoutText.contains("footerRowHeight"),
        "compact dashboard metric tiles define shared row heights"
    )
    expect(
        [codexUsageTileText, dailyTokenTileText].allSatisfy { text in
            text.contains("CompactDashboardMetricTileLayout.metricRowHeight")
                && text.contains("CompactDashboardMetricTileLayout.labelRowHeight")
                && text.contains("CompactDashboardMetricTileLayout.valueRowHeight")
                && text.contains("CompactDashboardMetricTileLayout.footerRowHeight")
        },
        "Codex usage and daily token tiles share fixed label, value, and footer rows"
    )
    expect(
        dailyTokenTileText.contains(".font(.system(size: 11")
            && dailyTokenTileText.contains(".font(.system(size: 22"),
        "daily token metrics use the same label and value font sizes as usage metrics"
    )
    expect(
        dailyTokenTileText.contains("Text(label)")
            && dailyTokenTileText.contains(".font(.system(size: 11, weight: .semibold, design: .rounded))")
            && dailyTokenTileText.contains(".foregroundStyle(.primary)")
            && dailyTokenTileText.contains(".frame(height: CompactDashboardMetricTileLayout.labelRowHeight)"),
        "daily token metric labels use the same primary foreground as usage metric labels"
    )
    expect(
        codexUsageTileText.contains("status.percent(for: window) != nil")
            && codexUsageTileText.contains("return .secondary"),
        "Codex usage unknown values use the shared placeholder foreground"
    )
    expect(
        [codexUsageTileText, dailyTokenTileText].allSatisfy { text in
            text.contains("let isRefreshing: Bool")
                && text.contains("ProgressView()")
                && text.contains("if isRefreshing")
                && text.contains("Spacer()")
        },
        "usage and token tiles show a small bottom-right progress spinner while refreshing"
    )
    expect(
        dailyTokenTileText.contains("private var placeholderValueColor: Color")
            && dailyTokenTileText.contains("status.observedAt == nil ? placeholderValueColor : .primary")
            && dailyTokenTileText.contains("status.hitRatePercent == nil ? placeholderValueColor : successValueColor")
            && dailyTokenTileText.contains("CodexUsageRingColor.lowUsageGreen"),
        "daily token unknown values use the shared placeholder foreground"
    )

    let liquidGlassText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(liquidGlassPath),
        encoding: .utf8
    )) ?? ""
    expect(
        liquidGlassText.contains(".glassEffect(")
            && liquidGlassText.contains(".regular,")
            && liquidGlassText.contains("in: glassShape"),
        "liquid glass container uses the system regular glass effect"
    )
    expect(
        liquidGlassText.contains("struct LiquidGlassScene")
            && liquidGlassText.contains("GlassEffectContainer")
            && liquidGlassText.contains(#".environment(\.colorScheme, .dark)"#),
        "shared liquid glass scene owns the system glass grouping and color scheme for both pages"
    )
    expect(
        liquidGlassText.contains("content\n            .glassEffect(")
            && liquidGlassText.contains(".compositingGroup()")
            && liquidGlassText.contains(".mask(glassShape)")
            && !liquidGlassText.contains(".background {"),
        "liquid glass container masks the rendered system glass to its shape so the halo does not bleed outside"
    )
    expect(
        !liquidGlassText.contains("LiquidGlassSurface")
            && !liquidGlassText.contains("surface:")
            && !liquidGlassText.contains(".regular.tint(")
            && !liquidGlassText.contains("compactPrompt")
            && !liquidGlassText.contains("strokeBorder("),
        "liquid glass container has no custom surface, tint, or stroke"
    )
    expect(
        !liquidGlassText.contains("baseOpacity")
            && !liquidGlassText.contains("compactPromptFill")
            && !liquidGlassText.contains("compactPromptTint")
            && !liquidGlassText.contains("compactPromptStroke"),
        "liquid glass container does not carry old custom glass tuning"
    )

    let glassPanelText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(glassPanelPath),
        encoding: .utf8
    )) ?? ""
    expect(
        glassPanelText.contains("hasShadow = false")
            && !glassPanelText.contains("hasShadow = true"),
        "transparent glass panels disable AppKit system shadow so active windows do not draw a dark outer outline"
    )
    expect(
        glassPanelText.contains("override var canBecomeKey: Bool")
            && glassPanelText.contains("override var canBecomeMain: Bool")
            && glassPanelText.contains("canBecomeMain: Bool {\n        false")
            && glassPanelText.contains("styleMask: [.borderless, .nonactivatingPanel]"),
        "floating glass panels can accept keyboard focus without becoming a main activating window"
    )

    let compactControllerText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(compactControllerPath),
        encoding: .utf8
    )) ?? ""
    expect(
        compactControllerText.contains("openCodexDesktopAndDismiss"),
        "Codex Desktop tile click dismisses compact panel after opening Codex"
    )

    let sidePanelControllerText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(sidePanelControllerPath),
        encoding: .utf8
    )) ?? ""
    expect(
        sidePanelControllerText.contains("private let dismissMonitors = EventMonitorStore()")
            && sidePanelControllerText.contains("installDismissMonitorsIfNeeded()")
            && sidePanelControllerText.contains("CompactEntryDismissPolicy.shouldDismissForKeyDown")
            && sidePanelControllerText.contains("CompactEntryDismissPolicy.shouldDismissForMouseDown"),
        "side panel can be dismissed by escape or clicking outside"
    )
    expect(
        sidePanelControllerText.contains("guard !isPinned() else")
            && sidePanelControllerText.contains("private func dismissIfNeededForMouseDown"),
        "side panel ignores outside mouse dismiss while pinned"
    )

    let windowCoordinatorText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(windowCoordinatorPath),
        encoding: .utf8
    )) ?? ""
    expect(
        windowCoordinatorText.contains("case let .recallConversation(conversationID):")
            && windowCoordinatorText.contains("conversationCoordinator.selectConversation(conversationID)")
            && windowCoordinatorText.contains("case .openFreshEntry:"),
        "global shortcut selects an existing conversation before opening the side panel"
    )
}

@MainActor
func expectWorkbenchInterfaceIntegration() {
    let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let workbenchViewPath = "Sources/CodexPlusApp/Workbench/WorkbenchView.swift"
    let topProjectStripPath = "Sources/CodexPlusApp/Workbench/TopProjectStripView.swift"
    let workbenchConversationPath = "Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift"
    let workbenchComposerPath = "Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift"
    let workbenchStatusBarPath = "Sources/CodexPlusApp/Workbench/WorkbenchStatusBarView.swift"
    let workbenchPanelControllerPath = "Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift"
    let workbenchLauncherViewPath = "Sources/CodexPlusApp/Workbench/WorkbenchLauncherView.swift"
    let workbenchLauncherPanelControllerPath = "Sources/CodexPlusApp/Workbench/WorkbenchLauncherPanelController.swift"
    let sideEdgeAffordancePath = "Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift"
    let windowCoordinatorPath = "Sources/CodexPlusApp/WindowCoordinator.swift"
    let glassPanelPath = "Sources/CodexPlusApp/GlassPanel.swift"
    let draggableHostingViewPath = "Sources/CodexPlusApp/DraggableHostingView.swift"

    for sourceFile in [
        workbenchViewPath,
        topProjectStripPath,
        workbenchConversationPath,
        workbenchComposerPath,
        workbenchStatusBarPath,
        workbenchPanelControllerPath,
        workbenchLauncherViewPath,
        workbenchLauncherPanelControllerPath,
        sideEdgeAffordancePath,
        glassPanelPath,
        draggableHostingViewPath
    ] {
        let exists = FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent(sourceFile).path
        )
        expect(exists, "workbench source exists: \(sourceFile)")
    }

    let workbenchViewText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(workbenchViewPath),
        encoding: .utf8
    )) ?? ""
    let topProjectStripText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(topProjectStripPath),
        encoding: .utf8
    )) ?? ""
    let workbenchConversationText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(workbenchConversationPath),
        encoding: .utf8
    )) ?? ""
    let workbenchComposerText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(workbenchComposerPath),
        encoding: .utf8
    )) ?? ""
    let workbenchStatusBarText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(workbenchStatusBarPath),
        encoding: .utf8
    )) ?? ""
    let workbenchPanelControllerText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(workbenchPanelControllerPath),
        encoding: .utf8
    )) ?? ""
    let workbenchLauncherViewText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(workbenchLauncherViewPath),
        encoding: .utf8
    )) ?? ""
    let workbenchLauncherPanelControllerText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(workbenchLauncherPanelControllerPath),
        encoding: .utf8
    )) ?? ""
    let sideEdgeAffordanceText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(sideEdgeAffordancePath),
        encoding: .utf8
    )) ?? ""
    let windowCoordinatorText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(windowCoordinatorPath),
        encoding: .utf8
    )) ?? ""
    let glassPanelText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(glassPanelPath),
        encoding: .utf8
    )) ?? ""
    let draggableHostingViewText = (try? String(
        contentsOf: packageRoot.appendingPathComponent(draggableHostingViewPath),
        encoding: .utf8
    )) ?? ""

    expect(
        workbenchViewText.contains("TopProjectStripView")
            && workbenchViewText.contains("WorkbenchConversationView")
            && workbenchViewText.contains("WorkbenchComposerView")
            && workbenchViewText.contains("WorkbenchStatusBarView"),
        "workbench root view composes the strip, conversation, composer, and status bar"
    )
    expect(
        workbenchViewText.contains("onSend: { store.submitPrompt($0) }")
            && workbenchViewText.contains("onPickWorkspace: pickWorkspace")
            && workbenchViewText.contains("onClearWorkspace: { store.clearDraftWorkspaceSelection() }")
            && workbenchViewText.contains("onTogglePin: { store.togglePin() }"),
        "workbench root routes composer submit, workspace picking, workspace clearing, and pin toggle through the store"
    )
    expect(
        workbenchViewText.contains("import AppKit")
            && workbenchViewText.contains("let panel = NSOpenPanel()")
            && workbenchViewText.contains("panel.canChooseDirectories = true")
            && workbenchViewText.contains("panel.canChooseFiles = false")
            && workbenchViewText.contains("store.createProject(")
            && workbenchViewText.contains("ConversationWorkspacePolicy.displayName(for: url.path)"),
        "workbench root opens a directory picker and selects the chosen workspace as the active project"
    )
    expect(
        topProjectStripText.contains(#"Text("项目：")"#)
            && topProjectStripText.contains(#"Text("对话：")"#)
            && topProjectStripText.contains(#"Image(systemName: "folder")"#)
            && topProjectStripText.contains(#"Image(systemName: "text.bubble")"#)
            && topProjectStripText.contains("card.overflowCount != nil"),
        "top project strip distinguishes project and conversation labels and only shows overflow when available"
    )
    expect(
        topProjectStripText.contains(#"title: "新对话""#)
            && topProjectStripText.contains(#"title: "已归档""#)
            && !topProjectStripText.contains("归档当前")
            && !topProjectStripText.contains("archivebox.and.arrow.down"),
        "top project strip only shows the new-conversation and archived entry actions"
    )
    expect(
        topProjectStripText.contains(".mask(Circle())")
            && topProjectStripText.contains(".mask(Capsule(style: .continuous))"),
        "top project strip masks rendered direct glass buttons to avoid exterior halo on light backgrounds"
    )
    expect(
        topProjectStripText.contains(#"Image(systemName: isPinned ? "pin.fill" : "pin")"#)
            && topProjectStripText.contains("Button(action: onTogglePin)")
            && topProjectStripText.contains("conversationSummaries"),
        "top project strip exposes pin and overflow conversation selection"
    )
    expect(
        !topProjectStripText.contains("workbenchLabel")
            && !topProjectStripText.contains("workbenchTint")
            && !topProjectStripText.contains(#""运行中""#)
            && !topProjectStripText.contains(#""已完成""#),
        "top project strip does not render conversation run-state labels"
    )
    expect(
        workbenchConversationText.contains("snapshot.activeConversation")
            && workbenchConversationText.contains("ConversationTimelineBuilder.items")
            && workbenchConversationText.contains("ConversationEventRow")
            && workbenchConversationText.contains("ConversationTechnicalEventGroupRow")
            && workbenchConversationText.contains(#"Label("归档", systemImage: "archivebox.and.arrow.down")"#)
            && workbenchConversationText.contains("archiveButton(for: conversation.id)")
            && workbenchConversationText.contains("onArchiveConversation(conversationID)"),
        "workbench conversation view renders the active timeline and a visible per-conversation archive action"
    )
    expect(
        !workbenchConversationText.contains("workbenchLabel")
            && !workbenchConversationText.contains("workbenchTint")
            && !workbenchConversationText.contains("conversation.state")
            && !workbenchConversationText.contains(#""运行中""#)
            && !workbenchConversationText.contains(#""已完成""#),
        "workbench conversation header does not render conversation run-state labels"
    )
    expect(
        workbenchConversationText.contains(".glassEffect(.regular, in: Capsule(style: .continuous))")
            && workbenchConversationText.contains(".compositingGroup()")
            && workbenchConversationText.contains(".mask(Capsule(style: .continuous))"),
        "workbench conversation archive button masks rendered glass to avoid exterior halo"
    )
    expect(
        workbenchComposerText.contains("switch snapshot.composerAction")
            && workbenchComposerText.contains("HStack(alignment: .center, spacing: 12)")
            && workbenchComposerText.contains("TextField(activePlaceholder, text: $prompt)")
            && !workbenchComposerText.contains("axis: .vertical")
            && workbenchComposerText.contains(#"Image(systemName: "stop.fill")"#)
            && workbenchComposerText.contains(#"Image(systemName: "arrow.up")"#)
            && workbenchComposerText.contains(#"Image(systemName: "folder")"#)
            && workbenchComposerText.contains("workspacePickerButton")
            && workbenchComposerText.contains("snapshot.activeConversation == nil")
            && workbenchComposerText.contains("onPickWorkspace")
            && workbenchComposerText.contains("onClearWorkspace")
            && workbenchComposerText.contains("workspaceClearButton")
            && workbenchComposerText.contains(#"Image(systemName: "xmark.circle.fill")"#)
            && workbenchComposerText.contains(".symbolRenderingMode(.hierarchical)")
            && workbenchComposerText.contains(".frame(width: 24, height: 30)")
            && workbenchComposerText.contains(".padding(.trailing, 6)")
            && workbenchComposerText.contains(".submitLabel(.send)")
            && workbenchComposerText.contains(".disabled(snapshot.composerAction == .stop)")
            && workbenchComposerText.contains("snapshot.canSubmitPrompt"),
        "workbench composer sends on return and respects submit availability"
    )
    expect(
        workbenchStatusBarText.contains("Codex CLI 可用")
            && workbenchStatusBarText.contains("SQLite 已连接")
            && workbenchStatusBarText.contains("归档索引 待更新"),
        "workbench status bar shows the three required technical items"
    )
    expect(
        !workbenchStatusBarText.contains("pin")
            && !workbenchStatusBarText.contains("background"),
        "workbench status bar does not show pin or background-task state"
    )
    expect(
        workbenchPanelControllerText.contains("WorkbenchPanelHostingView(rootView: WorkbenchView(store: store))")
            && !workbenchPanelControllerText.contains("WorkbenchPanelPlaceholderView"),
        "workbench panel controller hosts the real workbench view instead of a placeholder root"
    )
    expect(
        !windowCoordinatorText.contains("NSApp.activate(ignoringOtherApps: true)")
            && windowCoordinatorText.contains("workbenchPanelController.toggle()")
            && windowCoordinatorText.contains("workbenchPanelController.show()"),
        "workbench opens as a non-activating floating panel instead of switching the app into active glass appearance"
    )
    expect(
        workbenchPanelControllerText.contains("configureTransparentBacking()")
            && workbenchPanelControllerText.contains("wantsLayer = true")
            && workbenchPanelControllerText.contains("NSColor.clear.cgColor")
            && workbenchPanelControllerText.contains("layer?.shadowOpacity = 0")
            && workbenchPanelControllerText.contains("panel.hasShadow = false"),
        "workbench panel keeps the active key window backing and shadow transparent"
    )
    expect(
        !glassPanelText.contains("snapsToScreenMidline")
            && !glassPanelText.contains("constrainFrameRect")
            && workbenchPanelControllerText.contains("func recordMove(of movedPanel: GlassPanel) -> Bool")
            && !workbenchPanelControllerText.contains("midlineSnapDistance")
            && !workbenchPanelControllerText.contains("CompactPanelSnapPolicy")
            && !workbenchPanelControllerText.contains("NSHapticFeedbackManager")
            && !workbenchPanelControllerText.contains("wasNearMidline")
            && !workbenchPanelControllerText.contains("windowDragMode = .workbenchPanel")
            && !draggableHostingViewText.contains("case workbenchPanel")
            && !draggableHostingViewText.contains("workbenchSnap")
            && !draggableHostingViewText.contains("workbenchPanelDragResult")
            && !draggableHostingViewText.contains("WorkbenchPanelDragGestureHandler"),
        "workbench panel uses native dragging without midline snap behavior"
    )
    expect(
        !workbenchPanelControllerText.contains("NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]")
            && !workbenchPanelControllerText.contains("snapWorkbenchPanelToMidlineIfNeeded()"),
        "workbench panel relies on native drag constraints instead of mouse-up snap correction"
    )
    expect(
        workbenchPanelControllerText.contains("NSEvent.addLocalMonitorForEvents(matching: [.keyDown]")
            && workbenchPanelControllerText.contains("CompactEntryDismissPolicy.shouldDismissForKeyDown")
            && workbenchPanelControllerText.contains("panel.isKeyWindow || panel.isMainWindow")
            && workbenchPanelControllerText.contains("hide()"),
        "workbench panel hides on escape only when it is the current key or main window"
    )
    expect(
        windowCoordinatorText.contains("workbenchPanelController.recordMove(of: panel)"),
        "window coordinator routes workbench panel move events into move ownership handling"
    )
    expect(
        workbenchLauncherViewText.contains("struct WorkbenchLauncherView")
            && workbenchLauncherViewText.contains(".glassEffect(")
            && workbenchLauncherViewText.contains(".compositingGroup()")
            && workbenchLauncherViewText.contains(".mask(Circle())")
            && workbenchLauncherViewText.contains("WorkbenchLauncherMetrics.sphereSize")
            && workbenchLauncherViewText.contains(".accessibilityAddTraits(.isButton)"),
        "workbench launcher renders a smaller masked liquid glass clickable sphere"
    )
    expect(
        workbenchLauncherViewText.contains("symbolColor")
            && workbenchLauncherViewText.contains("Color.white")
            && workbenchLauncherViewText.contains(".blendMode(.difference)")
            && !workbenchLauncherViewText.contains(#"@Environment(\.colorScheme)"#),
        "workbench launcher symbol inverts against light and dark glass backgrounds"
    )
    expect(
        workbenchLauncherPanelControllerText.contains("final class WorkbenchLauncherPanelController")
            && workbenchLauncherPanelControllerText.contains("WorkbenchLauncherHostingView")
            && workbenchLauncherPanelControllerText.contains("WorkbenchLauncherView()")
            && workbenchLauncherPanelControllerText.contains("static func defaultFrame"),
        "workbench launcher panel owns the draggable small floating entry window"
    )
    expect(
        workbenchLauncherPanelControllerText.contains("final class WorkbenchLauncherPanel")
            && workbenchLauncherPanelControllerText.contains("override var canBecomeKey: Bool")
            && workbenchLauncherPanelControllerText.contains("override var canBecomeMain: Bool")
            && workbenchLauncherPanelControllerText.contains("false"),
        "workbench launcher uses a non-key panel to avoid active square focus shadow"
    )
    expect(
        sideEdgeAffordanceText.contains(".glassEffect(.regular, in: Capsule(style: .continuous))")
            && sideEdgeAffordanceText.contains(".compositingGroup()")
            && sideEdgeAffordanceText.contains(".mask(Capsule(style: .continuous))")
            && !sideEdgeAffordanceText.contains(".shadow("),
        "side edge affordance uses masked glass without an exterior shadow haze"
    )
    expect(
        workbenchLauncherPanelControllerText.contains("static let panelSize = CGFloat(48)")
            && workbenchLauncherPanelControllerText.contains("static let sphereSize = CGFloat(38)")
            && workbenchLauncherPanelControllerText.contains("performWindowDrag")
            && workbenchLauncherPanelControllerText.contains("onClick()"),
        "workbench launcher is 40 percent smaller and distinguishes click from drag"
    )
    expect(
        workbenchLauncherPanelControllerText.contains("configureTransparentBacking()")
            && workbenchLauncherPanelControllerText.contains("wantsLayer = true")
            && workbenchLauncherPanelControllerText.contains("NSColor.clear.cgColor")
            && workbenchLauncherPanelControllerText.contains("layer?.isOpaque = false"),
        "workbench launcher hosting view keeps the square panel backing transparent"
    )
    expect(
        workbenchPanelControllerText.contains("let onHide: () -> Void")
            && workbenchPanelControllerText.contains("let onShow: () -> Void")
            && workbenchPanelControllerText.contains("onHide()")
            && workbenchPanelControllerText.contains("onShow()"),
        "workbench panel controller announces show and hide transitions"
    )
    expect(
        windowCoordinatorText.contains("workbenchLauncherPanelController.show()")
            && windowCoordinatorText.contains("workbenchLauncherPanelController.hide()")
            && windowCoordinatorText.contains("private func showWorkbenchFromLauncher()")
            && windowCoordinatorText.contains("workbenchPanelController.show()"),
        "window coordinator hides the launcher while the main workbench is visible"
    )
}

expect(PermissionMode.semiAutomatic.displayName == "Semi-Automatic", "semiAutomatic display name")
expect(PermissionMode.fullAccess.displayName == "Full Access", "fullAccess display name")

expect(
    CodexEventParser.parseLine(#"{"type":"thread.started","thread_id":"abc"}"#) == .threadStarted("abc"),
    "thread.started parses thread id"
)
expect(
    CodexEventParser.parseLine(#"{"type":"item.completed","item":{"type":"agent_message","text":"Hello"}}"#) == .agentMessage("Hello"),
    "item.completed parses agent message text"
)
expect(
    CodexEventParser.parseLine(#"{"type":"item.started","item":{"id":"cmd1","type":"command_execution","command":"pwd"}}"#) == .command(id: "cmd1", command: "pwd", status: .inProgress),
    "item.started parses command execution id and in-progress status"
)
expect(
    CodexEventParser.parseLine(#"{"type":"item.completed","item":{"id":"cmd2","type":"command_execution","command":"pwd","status":"completed"}}"#) == .command(id: "cmd2", command: "pwd", status: .completed),
    "item.completed preserves command id and completed status"
)
expect(
    CodexEventParser.parseLine(#"{"type":"item.completed","item":{"id":"cmd3","type":"command_execution","command":"false","status":"failed"}}"#) == .command(id: "cmd3", command: "false", status: .failed),
    "item.completed preserves command id and failed status"
)
expect(
    CodexEventParser.parseLine("{broken") == .parseWarning("{broken"),
    "malformed JSON returns parse warning"
)
let agentMessageWithoutText = #"{"type":"item.started","item":{"id":"m1","type":"agent_message"}}"#
expect(
    CodexEventParser.parseLine(agentMessageWithoutText) == .raw(agentMessageWithoutText),
    "item.started agent message without text returns raw"
)
expect(
    CodexCommandBuilder.arguments(prompt: "List files", permissionMode: .semiAutomatic) == ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", "--", "List files"],
    "semi-automatic command arguments"
)
expect(
    CodexCommandBuilder.arguments(prompt: "List files", permissionMode: .fullAccess) == ["exec", "--json", "--skip-git-repo-check", "--sandbox", "danger-full-access", "--", "List files"],
    "full access command arguments"
)
expect(
    CodexCommandBuilder.arguments(prompt: "--help", permissionMode: .semiAutomatic) == ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", "--", "--help"],
    "prompt beginning with dash remains after delimiter"
)
expectNoCodexDesktopHandoffIntegration()
expectCodexDesktopLauncherIntegration()
expectWorkbenchInterfaceIntegration()
expectCodexPlusNaming()

expect(CodexRunResult(exitCode: 0, stderr: "").succeeded, "codex run result succeeds on exit zero")
expect(!CodexRunResult(exitCode: 1, stderr: "boom").succeeded, "codex run result fails on nonzero exit")
let parserInjectedRunner = ProcessCodexRunner(parser: { line in .agentMessage(line) })
expect(String(describing: type(of: parserInjectedRunner)) == "ProcessCodexRunner", "process codex runner accepts parser injection")

let normalScriptPath = makeTemporaryScript(
    named: "normal",
    contents: """
    printf 'first\\r\\ncaf'
    printf '\\303'
    printf 'err caf' >&2
    printf '\\303' >&2
    sleep 1
    printf '\\251\\nfinal'
    printf '\\251' >&2
    exit 0
    """
)
defer {
    try? FileManager.default.removeItem(atPath: normalScriptPath)
}

let normalCapture = LockedRunCapture()
let normalFinish = DispatchSemaphore(value: 0)
let normalRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [normalScriptPath],
    parser: { line in .agentMessage("parsed:\(line)") }
)
let normalHandle = normalRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    onEvent: { event in
        normalCapture.appendEvent(event)
    },
    onFinish: { result in
        normalCapture.appendResult(result)
        normalFinish.signal()
    }
)
let normalRunFinished = normalFinish.wait(timeout: .now() + .seconds(5)) == .success
expect(normalRunFinished, "process codex runner normal script finishes")
let normalDidNotFinishTwice = normalFinish.wait(timeout: .now() + .milliseconds(200)) == .timedOut
expect(normalDidNotFinishTwice, "process codex runner normal finish is called once")
expect(
    agentMessageTexts(from: normalCapture.events()) == ["parsed:first", "parsed:café", "parsed:final"],
    "process codex runner parses stdout lines through injected parser and flushes final line"
)
expect(normalCapture.results().count == 1, "process codex runner records one normal finish result")
expect(normalCapture.results().first?.exitCode == 0, "process codex runner normal script exits zero")
expect(normalCapture.results().first?.stderr == "err café", "process codex runner accumulates stderr as UTF-8")
_ = normalHandle

let noStdoutScriptPath = makeTemporaryScript(
    named: "no-stdout",
    contents: """
    exit 0
    """
)
defer {
    try? FileManager.default.removeItem(atPath: noStdoutScriptPath)
}

let noStdoutCapture = LockedRunCapture()
let noStdoutFinish = DispatchSemaphore(value: 0)
let noStdoutRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [noStdoutScriptPath],
    parser: { line in .agentMessage(line) }
)
let noStdoutHandle = noStdoutRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    onEvent: { event in
        noStdoutCapture.appendEvent(event)
    },
    onFinish: { result in
        noStdoutCapture.appendResult(result)
        noStdoutFinish.signal()
    }
)
let noStdoutRunFinished = noStdoutFinish.wait(timeout: .now() + .seconds(5)) == .success
expect(noStdoutRunFinished, "process codex runner no-stdout script finishes")
let noStdoutDidNotFinishTwice = noStdoutFinish.wait(timeout: .now() + .milliseconds(200)) == .timedOut
expect(noStdoutDidNotFinishTwice, "process codex runner no-stdout finish is called once")
expect(noStdoutCapture.events().isEmpty, "process codex runner no-stdout script emits no events")
expect(noStdoutCapture.results().count == 1, "process codex runner records one no-stdout result")
expect(noStdoutCapture.results().first?.succeeded == true, "process codex runner no-stdout script succeeds")
_ = noStdoutHandle

let longStdoutScriptPath = makeTemporaryScript(
    named: "long-stdout",
    contents: """
    printf 'abcdefghijklmnopqrstuvwxyz'
    exit 0
    """
)
defer {
    try? FileManager.default.removeItem(atPath: longStdoutScriptPath)
}

let longStdoutCapture = LockedRunCapture()
let longStdoutFinish = DispatchSemaphore(value: 0)
let longStdoutRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [longStdoutScriptPath],
    parser: { line in .agentMessage(line) },
    maxBufferedOutputBytes: 8
)
let longStdoutHandle = longStdoutRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    onEvent: { event in
        longStdoutCapture.appendEvent(event)
    },
    onFinish: { result in
        longStdoutCapture.appendResult(result)
        longStdoutFinish.signal()
    }
)
let longStdoutRunFinished = longStdoutFinish.wait(timeout: .now() + .seconds(5)) == .success
expect(longStdoutRunFinished, "process codex runner long stdout script finishes")
expect(
    agentMessageTexts(from: longStdoutCapture.events()).contains("stdout truncated after 8 bytes"),
    "process codex runner truncates unterminated stdout lines"
)
_ = longStdoutHandle

let longStderrScriptPath = makeTemporaryScript(
    named: "long-stderr",
    contents: """
    printf 'abcdefghijklmnopqrstuvwxyz' >&2
    exit 1
    """
)
defer {
    try? FileManager.default.removeItem(atPath: longStderrScriptPath)
}

let longStderrCapture = LockedRunCapture()
let longStderrFinish = DispatchSemaphore(value: 0)
let longStderrRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [longStderrScriptPath],
    parser: { line in .agentMessage(line) },
    maxBufferedOutputBytes: 8
)
let longStderrHandle = longStderrRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    onEvent: { event in
        longStderrCapture.appendEvent(event)
    },
    onFinish: { result in
        longStderrCapture.appendResult(result)
        longStderrFinish.signal()
    }
)
let longStderrRunFinished = longStderrFinish.wait(timeout: .now() + .seconds(5)) == .success
expect(longStderrRunFinished, "process codex runner long stderr script finishes")
expect(
    longStderrCapture.results().first?.stderr.contains("stderr truncated after 8 bytes") == true,
    "process codex runner truncates long stderr"
)
_ = longStderrHandle

let missingExecutableURL = FileManager.default.temporaryDirectory.appendingPathComponent(
    "codex-plus-missing-\(UUID().uuidString)"
)
let startFailureCapture = LockedRunCapture()
let startFailureFinish = DispatchSemaphore(value: 0)
let startFailureRunner = ProcessCodexRunner(
    executableURL: missingExecutableURL,
    executableArgumentsPrefix: [],
    parser: { line in .agentMessage(line) }
)
let startFailureHandle: ProcessCodexRunHandle = startFailureRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    onEvent: { event in
        startFailureCapture.appendEvent(event)
    },
    onFinish: { result in
        startFailureCapture.appendResult(result)
        startFailureFinish.signal()
    }
)
let startFailureFinished = startFailureFinish.wait(timeout: .now() + .seconds(2)) == .success
expect(startFailureFinished, "process codex runner start failure finishes")
let startFailureDidNotFinishTwice = startFailureFinish.wait(timeout: .now() + .milliseconds(200)) == .timedOut
expect(startFailureDidNotFinishTwice, "process codex runner start failure finish is called once")
expect(startFailureCapture.results().count == 1, "process codex runner records one start failure result")
expect(startFailureCapture.results().first?.exitCode == 127, "process codex runner start failure exits 127")
if case let .error(message)? = startFailureCapture.events().first {
    expect(message.hasPrefix("Unable to start codex:"), "process codex runner start failure emits error")
} else {
    expect(false, "process codex runner start failure emits error")
}
_ = startFailureHandle

let controllerSuccessScriptPath = makeTemporaryScript(
    named: "controller-success",
    contents: """
    printf '{"type":"item.completed","item":{"type":"agent_message","text":"done"}}\\n'
    """
)
defer {
    try? FileManager.default.removeItem(atPath: controllerSuccessScriptPath)
}

let controllerSuccessRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [controllerSuccessScriptPath],
    parser: CodexEventParser.parseLine
)
let codexRunController = CodexRunController(runner: controllerSuccessRunner)
let codexRunControllerSessionID = UUID()
var codexRunControllerEvents: [CodexEvent] = []
var codexRunControllerFinishResult: CodexRunResult?

let codexRunControllerDidStart = codexRunController.start(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    sessionID: codexRunControllerSessionID,
    workingDirectoryURL: nil,
    onEvent: { event, sessionID in
        if sessionID == codexRunControllerSessionID {
            codexRunControllerEvents.append(event)
        }
    },
    onFinish: { result, sessionID in
        if sessionID == codexRunControllerSessionID {
            codexRunControllerFinishResult = result
        }
    }
)
expect(codexRunControllerDidStart, "codex run controller starts process")
let codexRunControllerFinished = waitUntil(timeout: 5) {
    codexRunControllerFinishResult != nil
}
expect(codexRunControllerFinished, "codex run controller forwards finish")
expect(codexRunControllerFinishResult?.succeeded == true, "codex run controller forwards success result")
expect(codexRunController.isRunning == false, "codex run controller clears active run after finish")
expect(
    agentMessageTexts(from: codexRunControllerEvents) == ["done"],
    "codex run controller forwards events"
)

let workingDirectory = makeTemporaryDirectory(named: "runner-working-directory")
defer {
    try? FileManager.default.removeItem(at: workingDirectory)
}
let workingDirectoryScriptPath = makeTemporaryScript(
    named: "working-directory",
    contents: """
    pwd
    """
)
defer {
    try? FileManager.default.removeItem(atPath: workingDirectoryScriptPath)
}
let workingDirectoryCapture = LockedRunCapture()
let workingDirectoryFinish = DispatchSemaphore(value: 0)
let workingDirectoryRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [workingDirectoryScriptPath],
    parser: { line in .agentMessage(line) }
)
_ = workingDirectoryRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    workingDirectoryURL: workingDirectory,
    onEvent: { event in
        workingDirectoryCapture.appendEvent(event)
    },
    onFinish: { result in
        workingDirectoryCapture.appendResult(result)
        workingDirectoryFinish.signal()
    }
)
expect(
    workingDirectoryFinish.wait(timeout: .now() + .seconds(5)) == .success,
    "working-directory process finishes"
)
expect(
    URL(fileURLWithPath: agentMessageTexts(from: workingDirectoryCapture.events()).first ?? "", isDirectory: true).resolvingSymlinksInPath().path ==
        URL(fileURLWithPath: workingDirectory.path, isDirectory: true).resolvingSymlinksInPath().path,
    "process runner starts in supplied working directory"
)

let parallelScriptPath = makeTemporaryScript(
    named: "parallel-controller",
    contents: """
    printf 'started\\n'
    sleep 1
    printf 'done\\n'
    """
)
defer {
    try? FileManager.default.removeItem(atPath: parallelScriptPath)
}
let parallelRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [parallelScriptPath],
    parser: { line in .agentMessage(line) }
)
let parallelController = CodexRunController(runner: parallelRunner)
let parallelFirstSessionID = UUID()
let parallelSecondSessionID = UUID()
var parallelFinishedSessionIDs: [UUID] = []
let firstParallelStarted = parallelController.start(
    prompt: "first",
    permissionMode: .semiAutomatic,
    sessionID: parallelFirstSessionID,
    workingDirectoryURL: nil,
    onEvent: { _, _ in },
    onFinish: { _, sessionID in
        parallelFinishedSessionIDs.append(sessionID)
    }
)
let secondParallelStarted = parallelController.start(
    prompt: "second",
    permissionMode: .semiAutomatic,
    sessionID: parallelSecondSessionID,
    workingDirectoryURL: nil,
    onEvent: { _, _ in },
    onFinish: { _, sessionID in
        parallelFinishedSessionIDs.append(sessionID)
    }
)
let duplicateParallelStarted = parallelController.start(
    prompt: "duplicate",
    permissionMode: .semiAutomatic,
    sessionID: parallelFirstSessionID,
    workingDirectoryURL: nil,
    onEvent: { _, _ in },
    onFinish: { _, _ in }
)
expect(firstParallelStarted, "parallel controller starts first session")
expect(secondParallelStarted, "parallel controller starts second session")
expect(!duplicateParallelStarted, "parallel controller rejects duplicate session run")
expect(parallelController.isRunning(sessionID: parallelFirstSessionID), "first session is running")
expect(parallelController.isRunning(sessionID: parallelSecondSessionID), "second session is running")
expect(
    waitUntil(timeout: 5) { parallelFinishedSessionIDs.count == 2 },
    "parallel controller forwards both finishes"
)
expect(!parallelController.isRunning, "parallel controller clears aggregate running state")

let parallelStopIsolationScriptPath = makeTemporaryScript(
    named: "parallel-controller-stop-isolation",
    contents: """
    last_arg=""
    for arg in "$@"; do
      last_arg="$arg"
    done

    case "$last_arg" in
      stop)
        printf 'started-stop\\n'
        while :; do
          :
        done
        ;;
      finish)
        printf 'started-finish\\n'
        sleep 2
        printf 'done-finish\\n'
        ;;
      *)
        printf 'unexpected-%s\\n' "$last_arg"
        ;;
    esac
    """
)
defer {
    try? FileManager.default.removeItem(atPath: parallelStopIsolationScriptPath)
}
let parallelStopIsolationStopCapture = LockedRunCapture()
let parallelStopIsolationFinishCapture = LockedRunCapture()
let parallelStopIsolationStopSessionID = UUID()
let parallelStopIsolationFinishSessionID = UUID()
let parallelStopIsolationController = CodexRunController(
    runner: ProcessCodexRunner(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        executableArgumentsPrefix: [parallelStopIsolationScriptPath],
        parser: { line in .agentMessage(line) }
    )
)
let parallelStopIsolationStopStartedRun = parallelStopIsolationController.start(
    prompt: "stop",
    permissionMode: .semiAutomatic,
    sessionID: parallelStopIsolationStopSessionID,
    workingDirectoryURL: nil,
    onEvent: { event, _ in
        parallelStopIsolationStopCapture.appendEvent(event)
    },
    onFinish: { result, _ in
        parallelStopIsolationStopCapture.appendResult(result)
    }
)
let parallelStopIsolationFinishStartedRun = parallelStopIsolationController.start(
    prompt: "finish",
    permissionMode: .semiAutomatic,
    sessionID: parallelStopIsolationFinishSessionID,
    workingDirectoryURL: nil,
    onEvent: { event, _ in
        parallelStopIsolationFinishCapture.appendEvent(event)
    },
    onFinish: { result, _ in
        parallelStopIsolationFinishCapture.appendResult(result)
    }
)
expect(parallelStopIsolationStopStartedRun, "stop session starts")
expect(parallelStopIsolationFinishStartedRun, "finish session starts")
expect(
    waitUntil(timeout: 2) {
        parallelStopIsolationStopCapture.events().contains {
            if case .agentMessage("started-stop") = $0 {
                return true
            }

            return false
        }
    },
    "stop session emits start signal"
)
expect(
    waitUntil(timeout: 2) {
        parallelStopIsolationFinishCapture.events().contains {
            if case .agentMessage("started-finish") = $0 {
                return true
            }

            return false
        }
    },
    "finish session emits start signal"
)
expect(
    parallelStopIsolationController.stop(sessionID: parallelStopIsolationStopSessionID),
    "stopping one session succeeds"
)
expect(
    parallelStopIsolationController.isRunning(sessionID: parallelStopIsolationFinishSessionID),
    "parallel session keeps running after sibling stop"
)
expect(
    waitUntil(timeout: 2) {
        !parallelStopIsolationController.isRunning(sessionID: parallelStopIsolationStopSessionID)
    },
    "stopped session clears its own running state"
)
expect(
    parallelStopIsolationStopCapture.results().isEmpty,
    "stopped session does not call finish handler"
)
expect(
    waitUntil(timeout: 5) { parallelStopIsolationFinishCapture.results().count == 1 },
    "parallel session still finishes normally"
)
expect(
    parallelStopIsolationFinishCapture.results().first?.succeeded == true,
    "parallel session finish result succeeds"
)
expect(
    parallelStopIsolationStopCapture.results().isEmpty,
    "stopped session never reports finish"
)
expect(
    !parallelStopIsolationController.isRunning(sessionID: parallelStopIsolationFinishSessionID),
    "parallel session clears after finishing"
)
expect(!parallelStopIsolationController.isRunning, "stop isolation controller clears aggregate state")

let stopScriptPath = makeTemporaryScript(
    named: "stop",
    contents: """
    printf 'started\\n'
    while :; do
      :
    done
    """
)
defer {
    try? FileManager.default.removeItem(atPath: stopScriptPath)
}

let stopCapture = LockedRunCapture()
let stopStarted = DispatchSemaphore(value: 0)
let stopFinish = DispatchSemaphore(value: 0)
let stopRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [stopScriptPath],
    parser: { line in .agentMessage(line) }
)
let stopHandle = stopRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    onEvent: { event in
        stopCapture.appendEvent(event)
        if case .agentMessage("started") = event {
            stopStarted.signal()
        }
    },
    onFinish: { result in
        stopCapture.appendResult(result)
        stopFinish.signal()
    }
)
let stopRunStarted = stopStarted.wait(timeout: .now() + .seconds(5)) == .success
expect(stopRunStarted, "process codex runner stop script starts")
stopHandle.stop()
let stopRunFinished = stopFinish.wait(timeout: .now() + .seconds(5)) == .success
expect(stopRunFinished, "process codex runner stop finishes")
let stopDidNotFinishTwice = stopFinish.wait(timeout: .now() + .milliseconds(200)) == .timedOut
expect(stopDidNotFinishTwice, "process codex runner stop finish is called once")
expect(stopCapture.results().count == 1, "process codex runner records one stop result")
if let stoppedExitCode = stopCapture.results().first?.exitCode {
    expect(stoppedExitCode != 0, "process codex runner stop returns nonzero exit")
} else {
    expect(false, "process codex runner stop returns nonzero exit")
}

expect(!ConversationRunState.idle.isTerminal, "idle should not be terminal")
expect(!ConversationRunState.running.isTerminal, "running should not be terminal")
expect(ConversationRunState.completed.isTerminal, "completed should be terminal")
expect(ConversationRunState.failed.isTerminal, "failed should be terminal")
expect(ConversationRunState.stopped.isTerminal, "stopped should be terminal")

let fixedDateComponents = DateComponents(
    calendar: Calendar(identifier: .gregorian),
    timeZone: TimeZone(secondsFromGMT: 0),
    year: 2026,
    month: 7,
    day: 3
)
let fixedDate = fixedDateComponents.date!
expect(
    ConversationWorkspacePolicy.defaultParentPath(homeDirectoryPath: "/Users/oriki") ==
        "/Users/oriki/Documents/Codex-plus",
    "default workspace parent uses Codex-plus documents path"
)
expect(
    ConversationWorkspacePolicy.defaultDateDirectoryName(
        date: fixedDate,
        calendar: Calendar(identifier: .gregorian)
    ) == "2026-07-03",
    "default workspace date directory uses yyyy-MM-dd"
)
expect(
    ConversationWorkspacePolicy.defaultRandomDirectoryName(randomSuffix: 4821) == "4821",
    "default workspace random directory uses four digits"
)
expect(
    ConversationWorkspacePolicy.defaultWorkspacePath(
        homeDirectoryPath: "/Users/oriki",
        date: fixedDate,
        randomSuffix: 4821,
        calendar: Calendar(identifier: .gregorian)
    ) == "/Users/oriki/Documents/Codex-plus/2026-07-03/4821",
    "default workspace path joins parent, date, and random directories"
)
expect(
    ConversationWorkspacePolicy.displayName(for: "/Users/oriki/Documents/codex-plus") == "codex-plus",
    "workspace display name uses last path component"
)
expect(
    ConversationWorkspacePolicy.normalizedPath("/Users/oriki/Documents/codex-plus/") ==
        "/Users/oriki/Documents/codex-plus",
    "workspace path normalization removes trailing slash"
)

var titleGenerator = ConversationTitleGenerator(randomSuffixes: [4821, 4821, 9130])
let firstTitle = titleGenerator.nextTitle(existingTitles: [])
let secondTitle = titleGenerator.nextTitle(existingTitles: [firstTitle])
expect(firstTitle == "对话_4821", "conversation title uses random suffix")
expect(secondTitle == "对话_9130", "conversation title retries on collision")
expect(
    ConversationTitleGenerator.title(randomSuffix: 7) == "对话_0007",
    "conversation title uses shared padding format"
)

let defaultSession = ConversationSession(prompt: "default title")
let defaultSessionTitleSuffix = String(defaultSession.title.dropFirst("对话_".count))
expect(
    defaultSession.title.hasPrefix("对话_"),
    "conversation session default title has 对话_ prefix"
)
expect(
    defaultSessionTitleSuffix.count == 4 && defaultSessionTitleSuffix.allSatisfy(\.isNumber),
    "conversation session default title has 4-digit suffix"
)
expect(
    defaultSession.title != "对话_0000",
    "conversation session default title is not fixed 0000 placeholder"
)

let emptyConversationCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [1111]))
expect(
    emptyConversationCoordinator.shortcutDecision() == .openFreshEntry,
    "shortcut opens fresh when no active conversation"
)
expect(emptyConversationCoordinator.snapshot.workspaces.isEmpty, "empty coordinator has no workspaces")

let draftShortcutCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [1112]))
draftShortcutCoordinator.beginDraft(selectedWorkspacePath: "/tmp/draft")
expect(
    draftShortcutCoordinator.shortcutDecision() == .openFreshEntry,
    "shortcut opens compact entry when only a draft exists"
)

let draftPromptCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [1113]))
draftPromptCoordinator.beginDraft(selectedWorkspacePath: "/tmp/draft")
draftPromptCoordinator.setDraftPrompt("Retry this prompt")
draftPromptCoordinator.setDraftError("Unable to prepare workspace")
expect(
    draftPromptCoordinator.snapshot.draft?.prompt == "Retry this prompt",
    "draft error preserves the entered prompt"
)
draftPromptCoordinator.setDraftWorkspacePath("/tmp/other-draft")
expect(
    draftPromptCoordinator.snapshot.draft?.prompt == "Retry this prompt",
    "changing draft workspace preserves the entered prompt"
)

let archivedShortcutCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [6101]))
let archivedShortcutConversation = archivedShortcutCoordinator.startConversation(prompt: "archive", workspacePath: "/tmp/archive-shortcut")
archivedShortcutCoordinator.archiveConversation(archivedShortcutConversation.id)
expect(
    archivedShortcutCoordinator.shortcutDecision() == .openFreshEntry,
    "shortcut opens fresh entry when every conversation is archived"
)

let archivedDraftShortcutCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [6102]))
let archivedDraftShortcutConversation = archivedDraftShortcutCoordinator.startConversation(prompt: "archive draft", workspacePath: "/tmp/archive-draft-shortcut")
archivedDraftShortcutCoordinator.archiveConversation(archivedDraftShortcutConversation.id)
archivedDraftShortcutCoordinator.beginDraft(selectedWorkspacePath: "/tmp/archive-draft-shortcut", prompt: "resume draft prompt")
expect(
    archivedDraftShortcutCoordinator.shortcutDecision() == .openFreshEntry,
    "shortcut opens the compact entry when no visible conversation remains"
)

let visibleCompletedShortcutCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [6201]))
let visibleCompletedConversation = visibleCompletedShortcutCoordinator.startConversation(prompt: "done", workspacePath: "/tmp/done")
visibleCompletedShortcutCoordinator.markCompleted(visibleCompletedConversation.id)
expect(
    visibleCompletedShortcutCoordinator.shortcutDecision() == .recallConversation(visibleCompletedConversation.id),
    "completed visible conversation recalls workbench while it remains unarchived"
)

let visibleConversationWithDraftShortcutCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [6202, 6203]))
let visibleConversationWithDraft = visibleConversationWithDraftShortcutCoordinator.startConversation(
    prompt: "visible",
    workspacePath: "/tmp/visible-with-draft"
)
visibleConversationWithDraftShortcutCoordinator.beginDraft(selectedWorkspacePath: "/tmp/visible-with-draft", prompt: "draft should not win shortcut")
expect(
    visibleConversationWithDraftShortcutCoordinator.shortcutDecision() == .recallConversation(visibleConversationWithDraft.id),
    "shortcut recalls a visible conversation before opening any draft surface"
)

let workspaceMergeCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [1111, 2222]))
let mergeDate = Date(timeIntervalSince1970: 100)
let firstMergedConversation = workspaceMergeCoordinator.startConversation(
    prompt: "first",
    workspacePath: "/Users/oriki/project/",
    now: mergeDate
)
let secondMergedConversation = workspaceMergeCoordinator.startConversation(
    prompt: "second",
    workspacePath: "/Users/oriki/project",
    now: mergeDate.addingTimeInterval(10)
)
expect(workspaceMergeCoordinator.snapshot.workspaces.count == 1, "same normalized path merges into one workspace")
expect(
    workspaceMergeCoordinator.snapshot.workspaces.first?.conversationIDs ==
        [firstMergedConversation.id, secondMergedConversation.id],
    "merged workspace preserves conversation order"
)
expect(firstMergedConversation.title == "对话_1111", "first generated conversation title")
expect(secondMergedConversation.title == "对话_2222", "second generated conversation title")

let separateWorkspaceCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [3333, 4444]))
let leftWorkspaceConversation = separateWorkspaceCoordinator.startConversation(
    prompt: "left",
    workspacePath: "/tmp/left",
    now: Date(timeIntervalSince1970: 100)
)
let rightWorkspaceConversation = separateWorkspaceCoordinator.startConversation(
    prompt: "right",
    workspacePath: "/tmp/right",
    now: Date(timeIntervalSince1970: 200)
)
expect(separateWorkspaceCoordinator.snapshot.workspaces.count == 2, "different paths create different workspaces")
separateWorkspaceCoordinator.selectWorkspace(separateWorkspaceCoordinator.snapshot.workspaces.first!.id)
expect(
    separateWorkspaceCoordinator.activeConversation?.id == leftWorkspaceConversation.id,
    "selecting workspace selects its first visible conversation"
)
separateWorkspaceCoordinator.selectConversation(rightWorkspaceConversation.id)
expect(
    separateWorkspaceCoordinator.activeConversation?.id == rightWorkspaceConversation.id,
    "selecting conversation switches active conversation"
)

let reorderCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [1001, 1002, 1003]))
let reorderFirst = reorderCoordinator.startConversation(prompt: "one", workspacePath: "/tmp/reorder", now: Date(timeIntervalSince1970: 1))
let reorderSecond = reorderCoordinator.startConversation(prompt: "two", workspacePath: "/tmp/reorder", now: Date(timeIntervalSince1970: 2))
let reorderThird = reorderCoordinator.startConversation(prompt: "three", workspacePath: "/tmp/reorder", now: Date(timeIntervalSince1970: 3))
reorderCoordinator.reorderConversation(reorderThird.id, to: 0)
expect(
    reorderCoordinator.snapshot.workspaces.first?.conversationIDs ==
        [reorderThird.id, reorderFirst.id, reorderSecond.id],
    "conversation reorder moves within workspace"
)

let archiveCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [9001, 9002, 9003]))
let archiveLeft = archiveCoordinator.startConversation(prompt: "left", workspacePath: "/tmp/archive", now: Date(timeIntervalSince1970: 10))
let archiveMiddle = archiveCoordinator.startConversation(prompt: "middle", workspacePath: "/tmp/archive", now: Date(timeIntervalSince1970: 20))
let archiveRight = archiveCoordinator.startConversation(prompt: "right", workspacePath: "/tmp/archive", now: Date(timeIntervalSince1970: 30))
archiveCoordinator.appendCodexEvent(.agentMessage("new left activity"), to: archiveLeft.id, now: Date(timeIntervalSince1970: 40))
archiveCoordinator.selectConversation(archiveMiddle.id)
let archiveResult = archiveCoordinator.archiveConversation(archiveMiddle.id, now: Date(timeIntervalSince1970: 50))
expect(archiveResult?.activeConversationID == archiveLeft.id, "archive selects newest neighbor by activity")
expect(archiveCoordinator.activeConversation?.id == archiveLeft.id, "coordinator active conversation follows archive result")
expect(
    archiveCoordinator.visibleConversations(in: archiveCoordinator.snapshot.workspaces.first!.id).map(\.id) ==
        [archiveLeft.id, archiveRight.id],
    "archived conversation disappears from visible tabs"
)

let allArchivedCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [7001]))
let onlyConversation = allArchivedCoordinator.startConversation(prompt: "only", workspacePath: "/tmp/only")
let onlyArchiveResult = allArchivedCoordinator.archiveConversation(onlyConversation.id)
expect(onlyArchiveResult?.activeConversationID == nil, "archiving last conversation clears active conversation")
expect(allArchivedCoordinator.snapshot.workspaces.isEmpty, "archiving last conversation removes workspace tab")
expect(allArchivedCoordinator.activeConversation == nil, "no active conversation remains after last archive")

let draftArchiveCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [7101, 7102]))
let draftArchiveFirst = draftArchiveCoordinator.startConversation(
    prompt: "first",
    workspacePath: "/tmp/draft-archive-first",
    now: Date(timeIntervalSince1970: 60)
)
let draftArchiveSecond = draftArchiveCoordinator.startConversation(
    prompt: "second",
    workspacePath: "/tmp/draft-archive-second",
    now: Date(timeIntervalSince1970: 70)
)
let expectedRemainingWorkspaceID = draftArchiveCoordinator.snapshot.workspaces.first { workspace in
    workspace.path == ConversationWorkspacePolicy.normalizedPath("/tmp/draft-archive-second")
}?.id
draftArchiveCoordinator.selectConversation(draftArchiveFirst.id)
draftArchiveCoordinator.beginDraft(selectedWorkspacePath: "/tmp/custom-draft")
draftArchiveCoordinator.setDraftPrompt("Keep this draft prompt")
let draftArchiveResult = draftArchiveCoordinator.archiveConversation(
    draftArchiveFirst.id,
    now: Date(timeIntervalSince1970: 80)
)
expect(
    draftArchiveResult?.activeWorkspaceID == expectedRemainingWorkspaceID,
    "archiving the draft workspace retargets the active workspace to a remaining workspace"
)
expect(
    draftArchiveCoordinator.activeWorkspaceID == expectedRemainingWorkspaceID,
    "coordinator repairs the active workspace when draft mode archives its only conversation"
)
expect(
    draftArchiveCoordinator.activeConversationID == nil,
    "draft mode keeps no active conversation after archiving the draft workspace conversation"
)
expect(
    draftArchiveCoordinator.snapshot.draft?.prompt == "Keep this draft prompt",
    "draft mode preserves the pending prompt after archiving the active workspace conversation"
)
expect(
    draftArchiveCoordinator.snapshot.workspaces.map(\.path) ==
        [ConversationWorkspacePolicy.normalizedPath("/tmp/draft-archive-second")],
    "archiving the only conversation in the active draft workspace removes that workspace and keeps the remaining one"
)
expect(
    draftArchiveCoordinator.visibleConversations(in: expectedRemainingWorkspaceID ?? UUID()).map(\.id) == [draftArchiveSecond.id],
    "remaining workspace conversations stay visible after draft archive repair"
)

let draftArchiveLastCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [7201]))
let draftArchiveLastConversation = draftArchiveLastCoordinator.startConversation(
    prompt: "last",
    workspacePath: "/tmp/draft-archive-last",
    now: Date(timeIntervalSince1970: 90)
)
draftArchiveLastCoordinator.beginDraft(selectedWorkspacePath: "/tmp/custom-last-draft")
draftArchiveLastCoordinator.setDraftPrompt("Keep final draft prompt")
draftArchiveLastCoordinator.archiveConversation(draftArchiveLastConversation.id)
expect(
    draftArchiveLastCoordinator.snapshot.draft?.prompt == "Keep final draft prompt",
    "draft mode preserves prompt when archiving the last visible conversation"
)
expect(
    draftArchiveLastCoordinator.shortcutDecision() == .openFreshEntry,
    "shortcut opens compact entry after archiving the last visible conversation from draft mode"
)

let isolatedEventsCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [8001, 8002]))
let isolatedFirst = isolatedEventsCoordinator.startConversation(prompt: "one", workspacePath: "/tmp/events")
let isolatedSecond = isolatedEventsCoordinator.startConversation(prompt: "two", workspacePath: "/tmp/events")
isolatedEventsCoordinator.appendCodexEvent(.agentMessage("first only"), to: isolatedFirst.id)
let firstEvents = isolatedEventsCoordinator.conversation(with: isolatedFirst.id)?.events ?? []
let secondEvents = isolatedEventsCoordinator.conversation(with: isolatedSecond.id)?.events ?? []
expect(firstEvents.count == 2, "first conversation receives appended event")
expect(secondEvents.count == 1, "second conversation does not receive first event")

let chargingBattery = BatteryStatus.from(
    currentCapacity: 43,
    maxCapacity: 100,
    isCharging: true,
    powerSourceState: "AC Power"
)
expect(chargingBattery.percentage == 43, "charging battery percentage")
expect(chargingBattery.state == .charging, "charging battery state")

let fullBattery = BatteryStatus.from(
    currentCapacity: 100,
    maxCapacity: 100,
    isCharging: false,
    powerSourceState: "AC Power"
)
expect(fullBattery.percentage == 100, "full battery percentage")
expect(fullBattery.state == .full, "full battery state")

let dischargingBattery = BatteryStatus.from(
    currentCapacity: 66,
    maxCapacity: 100,
    isCharging: false,
    powerSourceState: "Battery Power"
)
expect(dischargingBattery.percentage == 66, "discharging battery percentage")
expect(dischargingBattery.state == .discharging, "discharging battery state")

let pluggedInBattery = BatteryStatus.from(
    currentCapacity: 95,
    maxCapacity: 100,
    isCharging: false,
    powerSourceState: "AC Power"
)
expect(pluggedInBattery.percentage == 95, "plugged in battery percentage")
expect(pluggedInBattery.state == .pluggedIn, "plugged in battery state")

let invalidBattery = BatteryStatus.from(
    currentCapacity: nil,
    maxCapacity: 0,
    isCharging: nil,
    powerSourceState: nil
)
expect(invalidBattery.percentage == nil, "invalid battery percentage")
expect(invalidBattery.state == .unknown, "invalid battery state")

let defaultTileOrder = DashboardTileOrder(rawValue: nil)
expect(defaultTileOrder.tiles == [.codexDesktop, .codexUsage, .dailyTokens], "dashboard tile order defaults to Codex Desktop, usage, then daily tokens")
expect(defaultTileOrder.rawValue == "codexDesktop,codexUsage,dailyTokens", "dashboard tile order serializes visible default order")
expect(
    CompactDashboardTileDragPolicy.dailyTokensTileWidth == CompactDashboardTileDragPolicy.tileStripHeight * 2,
    "daily token tile uses a 2:1 aspect ratio"
)
expect(
    CompactDashboardTileDragPolicy.tileStripWidth == 438,
    "compact dashboard tile strip accounts for the wider daily token tile"
)
expect(
    CompactDashboardTileDragPolicy.minimumPanelWidth == 474,
    "compact panel minimum width leaves horizontal padding around the full tile strip"
)

let packageRootForDashboardTiles = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let dailyTokenTileText = (try? String(
    contentsOf: packageRootForDashboardTiles.appendingPathComponent("Sources/CodexPlusApp/Views/DailyTokenTileView.swift"),
    encoding: .utf8
)) ?? ""
expect(
    dailyTokenTileText.contains("CompactDashboardTileDragPolicy.dailyTokensTileWidth"),
    "daily token tile view uses the shared 2:1 width constant"
)
let compactPanelControllerTextForDashboard = (try? String(
    contentsOf: packageRootForDashboardTiles.appendingPathComponent("Sources/CodexPlusApp/CompactPanelController.swift"),
    encoding: .utf8
)) ?? ""
expect(
    compactPanelControllerTextForDashboard.contains("NSSize(width: 500, height: 210)"),
    "compact panel default frame leaves room for the wider daily token tile"
)

let legacyTileOrder = DashboardTileOrder(rawValue: "battery,codexUsage")
expect(legacyTileOrder.tiles == [.codexDesktop, .codexUsage, .dailyTokens], "dashboard tile order migrates persisted battery to visible tiles")

let twoTileLegacyOrder = DashboardTileOrder(rawValue: "codexDesktop,codexUsage")
expect(twoTileLegacyOrder.tiles == [.codexDesktop, .codexUsage, .dailyTokens], "dashboard tile order adds daily tokens to two-tile persisted order")

let reorderedTwoTileLegacyOrder = DashboardTileOrder(rawValue: "codexUsage,codexDesktop")
expect(
    reorderedTwoTileLegacyOrder.tiles == [.codexUsage, .codexDesktop, .dailyTokens],
    "dashboard tile order preserves reordered two-tile persisted order and appends daily tokens"
)

let reversedTileOrder = DashboardTileOrder(rawValue: "dailyTokens,codexUsage,codexDesktop")
expect(reversedTileOrder.tiles == [.dailyTokens, .codexUsage, .codexDesktop], "dashboard tile order reads reversed persisted order")

let invalidTileOrder = DashboardTileOrder(rawValue: "battery,battery,unknown")
expect(invalidTileOrder.tiles == [.codexDesktop, .codexUsage, .dailyTokens], "dashboard tile order falls back to visible tiles when persisted order is invalid")

let swappedTileOrder = defaultTileOrder.swapping(.codexDesktop, with: .codexUsage)
expect(swappedTileOrder.tiles == [.codexUsage, .codexDesktop, .dailyTokens], "dashboard tile order swaps Codex Desktop and usage tiles")
expect(
    defaultTileOrder.previewingDrag(.codexDesktop, translationWidth: 43, threshold: 44).tiles == [
        .codexDesktop,
        .codexUsage,
        .dailyTokens
    ],
    "dashboard tile drag preview keeps order before crossing threshold"
)
expect(
    defaultTileOrder.previewingDrag(.codexDesktop, translationWidth: 44, threshold: 44).tiles == [
        .codexUsage,
        .codexDesktop,
        .dailyTokens
    ],
    "dashboard tile drag preview moves a tile right after crossing threshold"
)
expect(
    defaultTileOrder.previewingDrag(.codexDesktop, translationWidth: 213, threshold: 44).tiles == [
        .codexUsage,
        .codexDesktop,
        .dailyTokens
    ],
    "dashboard tile drag preview keeps the dragged tile in the second slot before the next slot boundary"
)
expect(
    defaultTileOrder.previewingDrag(.codexDesktop, translationWidth: 214, threshold: 44).tiles == [
        .codexUsage,
        .dailyTokens,
        .codexDesktop
    ],
    "dashboard tile drag preview moves the first tile to the third slot during one continuous drag"
)
expect(
    defaultTileOrder.previewingDrag(.dailyTokens, translationWidth: -44, threshold: 44).tiles == [
        .codexDesktop,
        .dailyTokens,
        .codexUsage
    ],
    "dashboard tile drag preview moves a tile left after crossing threshold"
)
expect(
    defaultTileOrder.previewingDrag(.dailyTokens, translationWidth: -236, threshold: 44).tiles == [
        .codexDesktop,
        .dailyTokens,
        .codexUsage
    ],
    "dashboard tile drag preview keeps the dragged tile in the second slot before the previous slot boundary"
)
expect(
    defaultTileOrder.previewingDrag(.dailyTokens, translationWidth: -237, threshold: 44).tiles == [
        .dailyTokens,
        .codexDesktop,
        .codexUsage
    ],
    "dashboard tile drag preview moves the last tile to the first slot during one continuous drag"
)
expect(
    defaultTileOrder.previewingDrag(.codexDesktop, translationWidth: -80, threshold: 44).tiles == [
        .codexDesktop,
        .codexUsage,
        .dailyTokens
    ],
    "dashboard tile drag preview keeps first tile in place when dragged left"
)
expect(
    defaultTileOrder.previewingDrag(.dailyTokens, translationWidth: 80, threshold: 44).tiles == [
        .codexDesktop,
        .codexUsage,
        .dailyTokens
    ],
    "dashboard tile drag preview keeps last tile in place when dragged right"
)
expect(
    defaultTileOrder.layoutTiles(excludingDragged: nil) == [.codexDesktop, .codexUsage, .dailyTokens],
    "dashboard tile layout shows visible tiles"
)
expect(
    defaultTileOrder.layoutTiles(excludingDragged: .codexDesktop) == [.codexUsage, .dailyTokens],
    "dashboard tile layout removes dragged Codex Desktop tile"
)
expect(
    reversedTileOrder.layoutTiles(excludingDragged: .codexUsage) == [.dailyTokens, .codexDesktop],
    "dashboard tile layout removes dragged codex usage from reversed order"
)
expect(
    DashboardTileLayoutPolicy.placements(for: defaultTileOrder.tiles) == [
        DashboardTilePlacement(tile: .codexDesktop, centerX: -173, width: 92),
        DashboardTilePlacement(tile: .codexUsage, centerX: -46, width: 138),
        DashboardTilePlacement(tile: .dailyTokens, centerX: 127, width: 184)
    ],
    "dashboard tile layout places Codex Desktop left of usage"
)
expect(
    DashboardTileLayoutPolicy.placements(for: reversedTileOrder.tiles) == [
        DashboardTilePlacement(tile: .dailyTokens, centerX: -127, width: 184),
        DashboardTilePlacement(tile: .codexUsage, centerX: 46, width: 138),
        DashboardTilePlacement(tile: .codexDesktop, centerX: 173, width: 92)
    ],
    "dashboard tile layout places reversed tiles at stable visual centers"
)
expect(
    DashboardTileLayoutPolicy.placements(for: defaultTileOrder.layoutTiles(excludingDragged: .codexDesktop)) == [
        DashboardTilePlacement(tile: .codexUsage, centerX: -98, width: 138),
        DashboardTilePlacement(tile: .dailyTokens, centerX: 75, width: 184)
    ],
    "dashboard tile layout recenters the remaining tiles while Codex Desktop is dragged"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 57, rowWidth: 460, tiles: defaultTileOrder.tiles) == .codexDesktop,
    "dashboard tile hit testing selects Codex Desktop at its visual center"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 184, rowWidth: 460, tiles: defaultTileOrder.tiles) == .codexUsage,
    "dashboard tile hit testing selects codex usage at its visual center"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 357, rowWidth: 460, tiles: defaultTileOrder.tiles) == .dailyTokens,
    "dashboard tile hit testing selects daily tokens at its visual center"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 109, rowWidth: 460, tiles: defaultTileOrder.tiles) == nil,
    "dashboard tile hit testing ignores the gap between tiles"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 103, rowWidth: 460, tiles: reversedTileOrder.tiles) == .dailyTokens,
    "dashboard tile hit testing follows reversed visual order"
)

let compactEntryBounds = CGRect(x: 0, y: 0, width: 460, height: 210)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 80, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact Codex Desktop tile blocks window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 207, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact codex usage tile blocks window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 357, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact daily tokens tile blocks window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 20, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact dashboard row outside the cards blocks window dragging"
)
expect(
    CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 230, y: 152),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact prompt area allows window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 80, y: 146),
        panelBounds: compactEntryBounds,
        verticalOrigin: .bottom
    ),
    "compact tile drag policy supports bottom-left AppKit coordinates"
)
expect(
    CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 230, y: 50),
        panelBounds: compactEntryBounds,
        verticalOrigin: .bottom
    ),
    "compact prompt drag policy supports bottom-left AppKit coordinates"
)

let compactSnapScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
let narrowCompactPanelFrame = CGRect(x: 510, y: 300, width: 420, height: 210)
expect(
    CompactDashboardTileDragPolicy.panelFrameFittingTileStrip(
        narrowCompactPanelFrame,
        in: compactSnapScreen
    ) == CGRect(x: 483, y: 300, width: 474, height: 210),
    "compact panel expands old two-tile frames to show all dashboard tiles"
)

let currentCompactPanelFrame = CGRect(x: 470, y: 300, width: 500, height: 210)
expect(
    CompactDashboardTileDragPolicy.panelFrameFittingTileStrip(
        currentCompactPanelFrame,
        in: compactSnapScreen
    ) == currentCompactPanelFrame,
    "compact panel keeps current dashboard-sized frames unchanged"
)

let compactNearMidlineFrame = CGRect(x: 520, y: 300, width: 420, height: 210)
expect(
    CompactPanelSnapPolicy.snappedFrame(
        for: compactNearMidlineFrame,
        in: compactSnapScreen
    ) == CGRect(x: 510, y: 300, width: 420, height: 210),
    "compact panel snaps its center to the screen midline when near it"
)

let compactFarFromMidlineFrame = CGRect(x: 560, y: 300, width: 420, height: 210)
expect(
    CompactPanelSnapPolicy.snappedFrame(
        for: compactFarFromMidlineFrame,
        in: compactSnapScreen
    ) == compactFarFromMidlineFrame,
    "compact panel moves freely after leaving the midline snap distance"
)

let offsetSnapScreen = CGRect(x: 100, y: 0, width: 1000, height: 800)
let offsetNearMidlineFrame = CGRect(x: 380, y: 260, width: 420, height: 210)
expect(
    CompactPanelSnapPolicy.snappedFrame(
        for: offsetNearMidlineFrame,
        in: offsetSnapScreen
    ) == CGRect(x: 390, y: 260, width: 420, height: 210),
    "compact panel snap uses the active screen midline"
)

let unknownCodexUsage = CodexUsageStatus.unknown
expect(unknownCodexUsage.fiveHourPercent == nil, "unknown codex usage has no five-hour percent")
expect(unknownCodexUsage.weeklyPercent == nil, "unknown codex usage has no weekly percent")
expect(unknownCodexUsage.ringColor(for: .fiveHour) == .inactive, "unknown codex usage uses inactive ring color")
expect(
    unknownCodexUsage.displayPercentText(for: .weekly) == "--%",
    "codex usage display text shows placeholder for missing percent"
)

let greenCodexUsage = CodexUsageStatus(fiveHourPercent: 42, weeklyPercent: 12, observedAt: Date(timeIntervalSince1970: 10))
expect(greenCodexUsage.fiveHourPercent == 42, "codex usage stores five-hour percent")
expect(greenCodexUsage.weeklyPercent == 12, "codex usage stores weekly percent")
expect(greenCodexUsage.ringColor(for: .fiveHour) == .lowUsageGreen, "codex usage below sixty percent is green")
expect(
    greenCodexUsage.displayPercentText(for: .fiveHour) == "42%",
    "codex usage display text shows known five-hour percent"
)

let stableGreenCodexUsage = CodexUsageStatus(fiveHourPercent: 65, weeklyPercent: 70, observedAt: nil)
expect(
    stableGreenCodexUsage.ringColor(for: .fiveHour) == .lowUsageGreen,
    "codex usage at sixty-five percent still uses the shared green"
)
expect(
    stableGreenCodexUsage.ringColor(for: .weekly) == .lowUsageGreen,
    "codex usage green-to-yellow transition starts from the shared green"
)

let yellowCodexUsage = CodexUsageStatus(fiveHourPercent: 80, weeklyPercent: 75, observedAt: nil)
expect(yellowCodexUsage.ringColor(for: .fiveHour) == .midUsageYellow, "codex usage at eighty percent is yellow")
expect(
    yellowCodexUsage.ringColor(for: .weekly) != .lowUsageGreen,
    "codex usage between seventy and eighty percent interpolates away from green"
)

let redCodexUsage = CodexUsageStatus(fiveHourPercent: 96, weeklyPercent: 100, observedAt: nil)
expect(redCodexUsage.ringColor(for: .fiveHour) != .midUsageYellow, "codex usage above eighty percent interpolates away from yellow")
expect(redCodexUsage.ringColor(for: .weekly) == .highUsageRed, "codex usage at one hundred percent is red")

let clampedCodexUsage = CodexUsageStatus(fiveHourPercent: -5, weeklyPercent: 140, observedAt: nil)
expect(clampedCodexUsage.fiveHourPercent == 0, "codex usage clamps low percent to zero")
expect(clampedCodexUsage.weeklyPercent == 100, "codex usage clamps high percent to one hundred")

let unknownDailyTokens = DailyTokenStatus.unknown
expect(unknownDailyTokens.inputText == "--", "unknown daily tokens show placeholder input")
expect(unknownDailyTokens.outputText == "--", "unknown daily tokens show placeholder output")
expect(unknownDailyTokens.hitRateText == "--", "unknown daily tokens show placeholder hit rate")

let compactDailyTokens = DailyTokenStatus(
    inputTokens: 1_234_431,
    outputTokens: 12_345,
    cachedInputTokens: 617_216,
    observedAt: Date(timeIntervalSince1970: 10)
)
expect(compactDailyTokens.inputText == "1.2M", "daily tokens compact large input totals")
expect(compactDailyTokens.outputText == "12K", "daily tokens compact medium output totals")
expect(compactDailyTokens.hitRateText == "50%", "daily tokens show rounded cache hit rate")

let dailyTokenSessionsDirectory = makeTemporaryDirectory(named: "daily-token-sessions")
let dailyTokenArchivesDirectory = makeTemporaryDirectory(named: "daily-token-archives")
defer {
    try? FileManager.default.removeItem(at: dailyTokenSessionsDirectory)
    try? FileManager.default.removeItem(at: dailyTokenArchivesDirectory)
}
var dailyTokenCalendar = Calendar(identifier: .gregorian)
dailyTokenCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let dailyTokenNow = ISO8601DateFormatter().date(from: "2026-07-03T12:00:00Z")!

writeText(
    """
    {malformed
    {"timestamp":"2026-07-02T23:59:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9000,"cached_input_tokens":9000,"output_tokens":900}}}}
    {"timestamp":"2026-07-03T01:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":50}}}}
    """,
    to: dailyTokenSessionsDirectory.appendingPathComponent("today.jsonl")
)
writeText(
    """
    {"timestamp":"2026-07-03T02:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1300,"output_tokens":150}}}}
    """,
    to: dailyTokenArchivesDirectory.appendingPathComponent("archived.jsonl")
)
writeText(
    """
    {"timestamp":"2026-07-03T03:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":9999,"cached_input_tokens":9999,"output_tokens":999}}}}
    """,
    to: dailyTokenSessionsDirectory.appendingPathComponent("ignored.txt")
)

let dailyTokenProvider = LocalDailyTokenUsageProvider(
    sessionDirectories: [dailyTokenSessionsDirectory],
    archiveDirectories: [dailyTokenArchivesDirectory],
    calendar: dailyTokenCalendar,
    now: { dailyTokenNow }
)
let dailyTokenStatus = dailyTokenProvider.currentStatus()
expect(dailyTokenStatus.inputTokens == 3000, "daily token provider sums today's input deltas")
expect(dailyTokenStatus.cachedInputTokens == 1500, "daily token provider sums today's cached input deltas")
expect(dailyTokenStatus.outputTokens == 200, "daily token provider sums today's output deltas")
expect(dailyTokenStatus.hitRateText == "50%", "daily token provider computes cache hit rate from summed input")
expect(
    dailyTokenStatus.observedAt == ISO8601DateFormatter().date(from: "2026-07-03T02:00:00Z"),
    "daily token provider preserves newest contributing timestamp"
)

let emptyDailyTokenDirectory = makeTemporaryDirectory(named: "daily-token-empty")
defer {
    try? FileManager.default.removeItem(at: emptyDailyTokenDirectory)
}
let emptyDailyTokenProvider = LocalDailyTokenUsageProvider(
    sessionDirectories: [emptyDailyTokenDirectory],
    archiveDirectories: [],
    calendar: dailyTokenCalendar,
    now: { dailyTokenNow }
)
expect(emptyDailyTokenProvider.currentStatus() == .unknown, "daily token provider returns unknown without token events")

let codexUsageSessionsDirectory = makeTemporaryDirectory(named: "codex-usage-sessions")
let codexUsageArchivesDirectory = makeTemporaryDirectory(named: "codex-usage-archives")
defer {
    try? FileManager.default.removeItem(at: codexUsageSessionsDirectory)
    try? FileManager.default.removeItem(at: codexUsageArchivesDirectory)
}

let olderUsageFile = codexUsageArchivesDirectory.appendingPathComponent("older.jsonl")
writeText(
    """
    {"timestamp":"2026-07-03T01:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":30,"window_minutes":300},"secondary":{"used_percent":40,"window_minutes":10080}}}}
    """,
    to: olderUsageFile
)

let newerUsageFile = codexUsageSessionsDirectory.appendingPathComponent("newer.jsonl")
writeText(
    """
    {not json
    {"timestamp":"2026-07-03T02:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":65,"window_minutes":300},"secondary":{"used_percent":55,"window_minutes":10080}}}}
    {"timestamp":"2026-07-03T03:00:00Z","type":"event_msg","payload":{"type":"agent_message","message":"ignored"}}
    """,
    to: newerUsageFile
)

let codexUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [codexUsageSessionsDirectory],
    archiveDirectories: [codexUsageArchivesDirectory]
)
let codexUsageStatus = codexUsageProvider.currentStatus()
expect(codexUsageStatus.fiveHourPercent == 65, "codex usage provider reads newest five-hour percent")
expect(codexUsageStatus.weeklyPercent == 55, "codex usage provider reads newest weekly percent")
expect(
    codexUsageStatus.observedAt == ISO8601DateFormatter().date(from: "2026-07-03T02:00:00Z"),
    "codex usage provider preserves newest usage timestamp"
)

let allFilesUsageDirectory = makeTemporaryDirectory(named: "codex-usage-all-files")
defer {
    try? FileManager.default.removeItem(at: allFilesUsageDirectory)
}
let newestEventByTimestampFile = allFilesUsageDirectory.appendingPathComponent("newest-event-by-timestamp.jsonl")
writeText(
    """
    {"timestamp":"2026-07-03T04:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":88,"window_minutes":300},"secondary":{"used_percent":78,"window_minutes":10080}}}}
    """,
    to: newestEventByTimestampFile
)
setModificationDate(Date(timeIntervalSince1970: 100), for: newestEventByTimestampFile)

for index in 0..<80 {
    let recentButOlderEventFile = allFilesUsageDirectory.appendingPathComponent("recent-\(index).jsonl")
    writeText(
        """
        {"timestamp":"2026-07-03T02:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":20,"window_minutes":300},"secondary":{"used_percent":30,"window_minutes":10080}}}}
        """,
        to: recentButOlderEventFile
    )
    setModificationDate(Date(timeIntervalSince1970: Double(200 + index)), for: recentButOlderEventFile)
}

let allFilesUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [allFilesUsageDirectory],
    archiveDirectories: []
)
let allFilesUsageStatus = allFilesUsageProvider.currentStatus()
expect(
    allFilesUsageStatus.fiveHourPercent == 88,
    "codex usage provider considers all files when choosing newest event timestamp"
)

let fractionalUsageDirectory = makeTemporaryDirectory(named: "codex-usage-fractional")
defer {
    try? FileManager.default.removeItem(at: fractionalUsageDirectory)
}
writeText(
    """
    {"timestamp":"2026-07-03T02:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":40,"window_minutes":300},"secondary":{"used_percent":50,"window_minutes":10080}}}}
    """,
    to: fractionalUsageDirectory.appendingPathComponent("whole-seconds.jsonl")
)
writeText(
    """
    {"timestamp":"2026-07-03T02:00:00.123Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":74,"window_minutes":300},"secondary":{"used_percent":84,"window_minutes":10080}}}}
    """,
    to: fractionalUsageDirectory.appendingPathComponent("fractional-seconds.jsonl")
)
let fractionalUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [fractionalUsageDirectory],
    archiveDirectories: []
)
let fractionalUsageStatus = fractionalUsageProvider.currentStatus()
let fractionalTimestampFormatter = ISO8601DateFormatter()
fractionalTimestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
expect(
    fractionalUsageStatus.fiveHourPercent == 74,
    "codex usage provider lets fractional-second timestamp win"
)
expect(
    fractionalUsageStatus.observedAt == fractionalTimestampFormatter.date(from: "2026-07-03T02:00:00.123Z"),
    "codex usage provider parses fractional-second timestamp"
)

let doublePercentUsageDirectory = makeTemporaryDirectory(named: "codex-usage-double-percent")
defer {
    try? FileManager.default.removeItem(at: doublePercentUsageDirectory)
}
writeText(
    """
    {"timestamp":"2026-07-03T05:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":42.6,"window_minutes":300},"secondary":{"used_percent":12.2,"window_minutes":10080}}}}
    """,
    to: doublePercentUsageDirectory.appendingPathComponent("double-percent.jsonl")
)
let doublePercentUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [doublePercentUsageDirectory],
    archiveDirectories: []
)
let doublePercentUsageStatus = doublePercentUsageProvider.currentStatus()
expect(doublePercentUsageStatus.fiveHourPercent == 43, "codex usage provider rounds double five-hour percent")
expect(doublePercentUsageStatus.weeklyPercent == 12, "codex usage provider rounds double weekly percent")

let jsonlOnlyUsageDirectory = makeTemporaryDirectory(named: "codex-usage-jsonl-only")
defer {
    try? FileManager.default.removeItem(at: jsonlOnlyUsageDirectory)
}
writeText(
    """
    {"timestamp":"2026-07-03T06:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":99,"window_minutes":300},"secondary":{"used_percent":99,"window_minutes":10080}}}}
    """,
    to: jsonlOnlyUsageDirectory.appendingPathComponent("tempting.txt")
)
writeText(
    """
    {"timestamp":"2026-07-03T05:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":33,"window_minutes":300},"secondary":{"used_percent":44,"window_minutes":10080}}}}
    """,
    to: jsonlOnlyUsageDirectory.appendingPathComponent("actual.jsonl")
)
let jsonlOnlyUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [jsonlOnlyUsageDirectory],
    archiveDirectories: []
)
expect(
    jsonlOnlyUsageProvider.currentStatus().fiveHourPercent == 33,
    "codex usage provider ignores non-jsonl files"
)

let cacheUsageDirectory = makeTemporaryDirectory(named: "codex-usage-cache")
defer {
    try? FileManager.default.removeItem(at: cacheUsageDirectory)
}
let cacheUsageFile = cacheUsageDirectory.appendingPathComponent("usage.jsonl")
let cacheMetadataDate = Date(timeIntervalSince1970: 1_700_000_000)
writeText(
    """
    {"timestamp":"2026-07-03T07:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":21,"window_minutes":300},"secondary":{"used_percent":22,"window_minutes":10080}}}}
    """,
    to: cacheUsageFile
)
setModificationDate(cacheMetadataDate, for: cacheUsageFile)

let cacheUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [cacheUsageDirectory],
    archiveDirectories: []
)
let firstCacheUsageStatus = cacheUsageProvider.currentStatus()
expect(firstCacheUsageStatus.fiveHourPercent == 21, "codex usage provider cache first read five-hour percent")
expect(firstCacheUsageStatus.weeklyPercent == 22, "codex usage provider cache first read weekly percent")

writeText(
    """
    {"timestamp":"2026-07-03T07:01:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":31,"window_minutes":300},"secondary":{"used_percent":32,"window_minutes":10080}}}}
    """,
    to: cacheUsageFile
)
setModificationDate(cacheMetadataDate, for: cacheUsageFile)
let unchangedMetadataUsageStatus = cacheUsageProvider.currentStatus()
expect(
    unchangedMetadataUsageStatus.fiveHourPercent == 21,
    "codex usage provider reuses cached status when file metadata is unchanged"
)

writeText(
    """
    {malformed
    {"timestamp":"2026-07-03T07:02:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":41,"window_minutes":300},"secondary":{"used_percent":52,"window_minutes":10080}}}}
    """,
    to: cacheUsageFile
)
setModificationDate(cacheMetadataDate.addingTimeInterval(1), for: cacheUsageFile)
let invalidatedCacheUsageStatus = cacheUsageProvider.currentStatus()
expect(
    invalidatedCacheUsageStatus.fiveHourPercent == 41,
    "codex usage provider invalidates cached status when file metadata changes"
)
expect(
    invalidatedCacheUsageStatus.weeklyPercent == 52,
    "codex usage provider invalidation reads new weekly percent"
)

let emptyUsageDirectory = makeTemporaryDirectory(named: "codex-usage-empty")
defer {
    try? FileManager.default.removeItem(at: emptyUsageDirectory)
}
let emptyUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [emptyUsageDirectory],
    archiveDirectories: []
)
expect(emptyUsageProvider.currentStatus() == .unknown, "codex usage provider returns unknown without usage data")

let batteryMonitorProvider = SequenceBatteryProvider([
    BatteryStatus(percentage: 20, state: .discharging),
    BatteryStatus(percentage: 21, state: .charging)
])
let batteryMonitor = BatteryStatusMonitor(provider: batteryMonitorProvider)
expect(batteryMonitor.status == .unknown, "battery monitor starts unknown before refresh")
batteryMonitor.refresh()
expect(
    batteryMonitor.status == BatteryStatus(percentage: 20, state: .discharging),
    "battery monitor refresh reads provider status"
)
batteryMonitor.refresh()
expect(
    batteryMonitor.status == BatteryStatus(percentage: 21, state: .charging),
    "battery monitor refresh updates status from provider"
)

let codexUsageMonitorProvider = SequenceCodexUsageProvider([
    CodexUsageStatus(fiveHourPercent: 11, weeklyPercent: 22, observedAt: nil),
    CodexUsageStatus(fiveHourPercent: 33, weeklyPercent: 44, observedAt: nil)
])
expect(
    CodexUsageMonitor.defaultRefreshInterval == 120,
    "codex usage monitor defaults to a two-minute refresh interval"
)
let codexUsageMonitor = CodexUsageMonitor(provider: codexUsageMonitorProvider, statusCache: nil)
expect(codexUsageMonitor.status == .unknown, "codex usage monitor starts unknown before refresh")
codexUsageMonitor.refresh()
let codexUsageMonitorFirstUpdate = waitUntil(timeout: 2) {
    codexUsageMonitor.status == CodexUsageStatus(fiveHourPercent: 11, weeklyPercent: 22, observedAt: nil)
}
expect(
    codexUsageMonitorFirstUpdate,
    "codex usage monitor refresh eventually reads provider status"
)
codexUsageMonitor.refresh()
let codexUsageMonitorSecondUpdate = waitUntil(timeout: 2) {
    codexUsageMonitor.status == CodexUsageStatus(fiveHourPercent: 33, weeklyPercent: 44, observedAt: nil)
}
expect(
    codexUsageMonitorSecondUpdate,
    "codex usage monitor refresh eventually updates status from provider"
)

let cachedCodexUsageStatus = CodexUsageStatus(
    fiveHourPercent: 7,
    weeklyPercent: 8,
    observedAt: Date(timeIntervalSince1970: 60)
)
let refreshedCodexUsageStatus = CodexUsageStatus(
    fiveHourPercent: 9,
    weeklyPercent: 10,
    observedAt: Date(timeIntervalSince1970: 70)
)
let cachedCodexUsageProvider = SequenceCodexUsageProvider([refreshedCodexUsageStatus])
let codexUsageStatusCache = MemoryCodexUsageStatusCache(cachedCodexUsageStatus)
let cachedCodexUsageMonitor = CodexUsageMonitor(
    provider: cachedCodexUsageProvider,
    statusCache: codexUsageStatusCache
)
expect(
    cachedCodexUsageMonitor.status == cachedCodexUsageStatus,
    "codex usage monitor loads cached status before the first provider refresh"
)
cachedCodexUsageMonitor.refresh()
let cachedCodexUsageMonitorUpdated = waitUntil(timeout: 2) {
    cachedCodexUsageMonitor.status == refreshedCodexUsageStatus
}
expect(
    cachedCodexUsageMonitorUpdated,
    "codex usage monitor replaces cached status after provider refresh"
)
expect(
    codexUsageStatusCache.savedStatus == refreshedCodexUsageStatus,
    "codex usage monitor saves refreshed status to local cache"
)

let codexUsageCacheSuiteName = "CodexPlusCoreTests.codexUsage.\(UUID().uuidString)"
if let codexUsageDefaults = UserDefaults(suiteName: codexUsageCacheSuiteName) {
    defer {
        codexUsageDefaults.removePersistentDomain(forName: codexUsageCacheSuiteName)
    }

    let persistedCodexUsageCache = UserDefaultsCodexUsageStatusCache(defaults: codexUsageDefaults)
    persistedCodexUsageCache.saveStatus(refreshedCodexUsageStatus)
    expect(
        UserDefaultsCodexUsageStatusCache(defaults: codexUsageDefaults).loadStatus() == refreshedCodexUsageStatus,
        "codex usage status cache persists and reloads status locally"
    )
} else {
    expect(false, "codex usage status cache test can create an isolated UserDefaults suite")
}

let lowVolumeDailyTokenStatus = DailyTokenStatus(
    inputTokens: 998_000,
    outputTokens: 1_999,
    cachedInputTokens: 0,
    observedAt: Date(timeIntervalSince1970: 40)
)
let highVolumeDailyTokenStatus = DailyTokenStatus(
    inputTokens: 999_000,
    outputTokens: 1_000,
    cachedInputTokens: 0,
    observedAt: Date(timeIntervalSince1970: 50)
)
expect(
    DailyTokenUsageMonitor.defaultLowVolumeRefreshInterval == 30,
    "daily token monitor low-volume refresh interval is thirty seconds"
)
expect(
    DailyTokenUsageMonitor.defaultHighVolumeRefreshInterval == 60,
    "daily token monitor high-volume refresh interval is sixty seconds"
)
expect(
    DailyTokenUsageMonitor.refreshInterval(for: lowVolumeDailyTokenStatus) == 30,
    "daily token monitor refreshes every thirty seconds below one million total tokens"
)
expect(
    DailyTokenUsageMonitor.refreshInterval(for: highVolumeDailyTokenStatus) == 60,
    "daily token monitor refreshes every sixty seconds at one million total tokens"
)

let dailyTokenMonitorProvider = SequenceDailyTokenProvider([
    lowVolumeDailyTokenStatus,
    highVolumeDailyTokenStatus
])
let dailyTokenMonitor = DailyTokenUsageMonitor(provider: dailyTokenMonitorProvider, statusCache: nil)
expect(dailyTokenMonitor.status == .unknown, "daily token monitor starts unknown before refresh")
dailyTokenMonitor.refresh()
let dailyTokenMonitorFirstUpdate = waitUntil(timeout: 2) {
    dailyTokenMonitor.status == lowVolumeDailyTokenStatus
}
expect(
    dailyTokenMonitorFirstUpdate,
    "daily token monitor refresh eventually reads provider status"
)
dailyTokenMonitor.refresh()
let dailyTokenMonitorSecondUpdate = waitUntil(timeout: 2) {
    dailyTokenMonitor.status == highVolumeDailyTokenStatus
}
expect(
    dailyTokenMonitorSecondUpdate,
    "daily token monitor refresh eventually updates status from provider"
)

let cachedDailyTokenStatus = DailyTokenStatus(
    inputTokens: 12_000,
    outputTokens: 340,
    cachedInputTokens: 6_000,
    observedAt: Date(timeIntervalSince1970: 80)
)
let refreshedDailyTokenStatus = DailyTokenStatus(
    inputTokens: 13_000,
    outputTokens: 450,
    cachedInputTokens: 7_000,
    observedAt: Date(timeIntervalSince1970: 90)
)
let cachedDailyTokenProvider = SequenceDailyTokenProvider([refreshedDailyTokenStatus])
let dailyTokenStatusCache = MemoryDailyTokenStatusCache(cachedDailyTokenStatus)
let cachedDailyTokenMonitor = DailyTokenUsageMonitor(
    provider: cachedDailyTokenProvider,
    statusCache: dailyTokenStatusCache
)
expect(
    cachedDailyTokenMonitor.status == cachedDailyTokenStatus,
    "daily token monitor loads cached status before the first provider refresh"
)
cachedDailyTokenMonitor.refresh()
let cachedDailyTokenMonitorUpdated = waitUntil(timeout: 2) {
    cachedDailyTokenMonitor.status == refreshedDailyTokenStatus
}
expect(
    cachedDailyTokenMonitorUpdated,
    "daily token monitor replaces cached status after provider refresh"
)
expect(
    dailyTokenStatusCache.savedStatus == refreshedDailyTokenStatus,
    "daily token monitor saves refreshed status to local cache"
)

var dailyTokenCacheCalendar = Calendar(identifier: .gregorian)
dailyTokenCacheCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
let dailyTokenCacheNow = Date(timeIntervalSince1970: 90)
let dailyTokenCacheSuiteName = "CodexPlusCoreTests.dailyTokens.\(UUID().uuidString)"
if let dailyTokenDefaults = UserDefaults(suiteName: dailyTokenCacheSuiteName) {
    defer {
        dailyTokenDefaults.removePersistentDomain(forName: dailyTokenCacheSuiteName)
    }

    let persistedDailyTokenCache = UserDefaultsDailyTokenStatusCache(
        defaults: dailyTokenDefaults,
        calendar: dailyTokenCacheCalendar,
        now: { dailyTokenCacheNow }
    )
    persistedDailyTokenCache.saveStatus(refreshedDailyTokenStatus)
    expect(
        UserDefaultsDailyTokenStatusCache(
            defaults: dailyTokenDefaults,
            calendar: dailyTokenCacheCalendar,
            now: { dailyTokenCacheNow }
        ).loadStatus() == refreshedDailyTokenStatus,
        "daily token status cache persists and reloads today's status locally"
    )

    let staleDailyTokenStatus = DailyTokenStatus(
        inputTokens: 1,
        outputTokens: 1,
        cachedInputTokens: 0,
        observedAt: dailyTokenCacheNow.addingTimeInterval(-86_400)
    )
    persistedDailyTokenCache.saveStatus(staleDailyTokenStatus)
    expect(
        UserDefaultsDailyTokenStatusCache(
            defaults: dailyTokenDefaults,
            calendar: dailyTokenCacheCalendar,
            now: { dailyTokenCacheNow }
        ).loadStatus() == nil,
        "daily token status cache ignores statuses from previous days"
    )
} else {
    expect(false, "daily token status cache test can create an isolated UserDefaults suite")
}

let asyncDailyTokenStatus = DailyTokenStatus(
    inputTokens: 15_000,
    outputTokens: 750,
    cachedInputTokens: 8_000,
    observedAt: Date(timeIntervalSince1970: 95)
)
let asyncDailyTokenProvider = BlockingDailyTokenProvider(status: asyncDailyTokenStatus)
let asyncDailyTokenMonitor = DailyTokenUsageMonitor(provider: asyncDailyTokenProvider, statusCache: nil)
DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(350)) {
    asyncDailyTokenProvider.release()
}
expect(!asyncDailyTokenMonitor.isRefreshing, "daily token monitor starts not refreshing")
let asyncDailyTokenRefreshStartedAt = Date()
asyncDailyTokenMonitor.refresh()
let asyncDailyTokenRefreshDuration = Date().timeIntervalSince(asyncDailyTokenRefreshStartedAt)
expect(
    asyncDailyTokenRefreshDuration < 0.15,
    "daily token monitor refresh returns before a slow provider finishes"
)
expect(
    asyncDailyTokenMonitor.isRefreshing,
    "daily token monitor marks itself refreshing while provider work is pending"
)
expect(
    asyncDailyTokenProvider.waitUntilFinished(),
    "daily token monitor slow provider finishes"
)
let asyncDailyTokenMonitorUpdated = waitUntil(timeout: 2) {
    asyncDailyTokenMonitor.status == asyncDailyTokenStatus && !asyncDailyTokenMonitor.isRefreshing
}
expect(
    asyncDailyTokenMonitorUpdated,
    "daily token monitor clears refreshing after publishing provider status"
)
asyncDailyTokenMonitor.stop()

let asyncCodexUsageStatus = CodexUsageStatus(
    fiveHourPercent: 66,
    weeklyPercent: 77,
    observedAt: Date(timeIntervalSince1970: 20)
)
let asyncCodexUsageProvider = BlockingCodexUsageProvider(status: asyncCodexUsageStatus)
let asyncCodexUsageMonitor = CodexUsageMonitor(provider: asyncCodexUsageProvider, statusCache: nil)
DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(350)) {
    asyncCodexUsageProvider.release()
}
expect(!asyncCodexUsageMonitor.isRefreshing, "codex usage monitor starts not refreshing")
let asyncRefreshStartedAt = Date()
asyncCodexUsageMonitor.refresh()
let asyncRefreshDuration = Date().timeIntervalSince(asyncRefreshStartedAt)
expect(
    asyncRefreshDuration < 0.15,
    "codex usage monitor refresh returns before a slow provider finishes"
)
expect(
    asyncCodexUsageProvider.waitUntilStarted(),
    "codex usage monitor refresh starts provider work"
)
expect(
    asyncCodexUsageMonitor.isRefreshing,
    "codex usage monitor marks itself refreshing while provider work is pending"
)
expect(
    asyncCodexUsageMonitor.status == .unknown,
    "codex usage monitor keeps status unchanged while background provider work is pending"
)
expect(
    asyncCodexUsageProvider.waitUntilFinished(),
    "codex usage monitor slow provider finishes"
)
let asyncCodexUsageMonitorUpdated = waitUntil(timeout: 2) {
    asyncCodexUsageMonitor.status == asyncCodexUsageStatus && !asyncCodexUsageMonitor.isRefreshing
}
expect(
    asyncCodexUsageMonitorUpdated,
    "codex usage monitor publishes background provider status and clears refreshing on the main actor"
)
expect(
    asyncCodexUsageProvider.callWasOnMainThread == false,
    "codex usage monitor calls provider off the main thread"
)

let stoppedCodexUsageStatus = CodexUsageStatus(
    fiveHourPercent: 81,
    weeklyPercent: 82,
    observedAt: Date(timeIntervalSince1970: 30)
)
let stoppedCodexUsageProvider = BlockingCodexUsageProvider(status: stoppedCodexUsageStatus)
let stoppedCodexUsageMonitor = CodexUsageMonitor(provider: stoppedCodexUsageProvider, statusCache: nil)
DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(350)) {
    stoppedCodexUsageProvider.release()
}
let stoppedRefreshStartedAt = Date()
stoppedCodexUsageMonitor.refresh()
let stoppedRefreshDuration = Date().timeIntervalSince(stoppedRefreshStartedAt)
expect(
    stoppedRefreshDuration < 0.15,
    "codex usage monitor stop test refresh returns before a slow provider finishes"
)
stoppedCodexUsageMonitor.stop()
expect(
    !stoppedCodexUsageMonitor.isRefreshing,
    "codex usage monitor stop clears the refreshing state"
)
expect(
    stoppedCodexUsageProvider.waitUntilFinished(),
    "codex usage monitor stopped provider finishes"
)
let stoppedCodexUsageMonitorUpdated = waitUntil(timeout: 0.3) {
    stoppedCodexUsageMonitor.status == stoppedCodexUsageStatus
}
expect(
    !stoppedCodexUsageMonitorUpdated,
    "codex usage monitor stop prevents in-flight refresh from updating status"
)

let compactPanelFrame = CGRect(x: 100, y: 100, width: 420, height: 210)
expect(
    CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode: CompactEntryDismissPolicy.escapeKeyCode),
    "compact dismiss policy dismisses on escape"
)
expect(
    !CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode: 0),
    "compact dismiss policy ignores non-escape keys"
)
expect(
    !CompactEntryDismissPolicy.shouldDismissForMouseDown(
        at: CGPoint(x: 200, y: 150),
        panelFrame: compactPanelFrame
    ),
    "compact dismiss policy keeps visible for inside clicks"
)
expect(
    CompactEntryDismissPolicy.shouldDismissForMouseDown(
        at: CGPoint(x: 20, y: 150),
        panelFrame: compactPanelFrame
    ),
    "compact dismiss policy dismisses for outside clicks"
)

let placementScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
expect(
    PanelPlacementPolicy.placement(
        for: CGRect(x: 10, y: 0, width: 460, height: 900),
        in: placementScreen
    ) == .attached(.left),
    "panel placement attaches near left edge"
)
expect(
    PanelPlacementPolicy.placement(
        for: CGRect(x: 970, y: 0, width: 460, height: 900),
        in: placementScreen
    ) == .attached(.right),
    "panel placement attaches near right edge"
)
expect(
    PanelPlacementPolicy.placement(
        for: CGRect(x: 420, y: 120, width: 460, height: 600),
        in: placementScreen
    ) == .free,
    "panel placement stays free away from edges"
)

expect(
    ConversationPanelLayoutPolicy.initialCenteredFrame(
        in: CGRect(x: 0, y: 0, width: 1500, height: 1000)
    ) == CGRect(x: 330, y: 90, width: 840, height: 820),
    "conversation panel initial frame is centered and sized for the main reading area"
)
expect(
    ConversationPanelLayoutPolicy.initialCenteredFrame(
        in: CGRect(x: 0, y: 0, width: 3000, height: 2000)
    ) == CGRect(x: 1070, y: 540, width: 860, height: 920),
    "conversation panel initial frame caps large desktop sizes"
)
expect(
    ConversationPanelLayoutPolicy.initialCenteredFrame(
        in: CGRect(x: 0, y: 0, width: 700, height: 600)
    ) == CGRect(x: 90, y: 24, width: 520, height: 552),
    "conversation panel initial frame keeps margins on compact screens"
)

let timelineUserID = UUID()
let timelineStatusID = UUID()
let timelineCommandID = UUID()
let timelineAssistantID = UUID()
let timelineParseWarningID = UUID()
let timelineItems = ConversationTimelineBuilder.items(from: [
    .userPrompt(id: timelineUserID, text: "hello"),
    .status(id: timelineStatusID, text: "Turn started"),
    .command(id: timelineCommandID, executionID: "cmd1", command: "pwd", status: .completed),
    .assistantMessage(id: timelineAssistantID, text: "Hi"),
    .parseWarning(id: timelineParseWarningID, text: "{broken")
])
expect(timelineItems.count == 4, "timeline builder groups consecutive technical events")
expect(timelineItems.first == .event(.userPrompt(id: timelineUserID, text: "hello")), "timeline builder keeps user prompt visible")
if case let .technicalGroup(id, events) = timelineItems[1] {
    expect(id == timelineStatusID, "timeline technical group uses first event id")
    expect(events.count == 2, "timeline technical group contains consecutive status and command")
} else {
    expect(false, "timeline builder creates technical group")
}
expect(
    timelineItems[2] == .event(.assistantMessage(id: timelineAssistantID, text: "Hi")),
    "timeline builder keeps assistant message visible"
)
if case let .technicalGroup(id, events) = timelineItems[3] {
    expect(id == timelineParseWarningID, "timeline technical group after assistant uses parse warning id")
    expect(events.count == 1, "timeline technical group restarts after visible event")
} else {
    expect(false, "timeline builder creates second technical group")
}

runWorkbenchProjectionTests()
runPersistenceTests()
runExecutionEngineTests()
runArchiveTests()
runWorkbenchStoreTests()

if failures.isEmpty {
    print("CodexPlusCoreTests passed: \(assertionCount) assertions")
} else {
    print("CodexPlusCoreTests failed: \(failures.count) of \(assertionCount) assertions failed")

    for failure in failures {
        print("- \(failure)")
    }

    exit(1)
}
