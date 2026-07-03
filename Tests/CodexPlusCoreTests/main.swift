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
    CodexCommandBuilder.arguments(prompt: "List files", permissionMode: .semiAutomatic) == ["exec", "--json", "--sandbox", "read-only", "--", "List files"],
    "semi-automatic command arguments"
)
expect(
    CodexCommandBuilder.arguments(prompt: "List files", permissionMode: .fullAccess) == ["exec", "--json", "--sandbox", "danger-full-access", "--", "List files"],
    "full access command arguments"
)
expect(
    CodexCommandBuilder.arguments(prompt: "--help", permissionMode: .semiAutomatic) == ["exec", "--json", "--sandbox", "read-only", "--", "--help"],
    "prompt beginning with dash remains after delimiter"
)
expectNoCodexDesktopHandoffIntegration()
expectCodexPlusNaming()

var splitLineBuffer = LineBuffer()
expect(splitLineBuffer.append("one\ntw") == ["one"], "line buffer returns complete first line")
expect(splitLineBuffer.append("o\nthree\n") == ["two", "three"], "line buffer completes partial and next line")
expect(splitLineBuffer.flush() == nil, "line buffer flush returns nil when empty")

var partialLineBuffer = LineBuffer()
expect(partialLineBuffer.append("partial").isEmpty, "line buffer keeps trailing partial line")
expect(partialLineBuffer.flush() == "partial", "line buffer flush returns partial line")
expect(partialLineBuffer.flush() == nil, "line buffer flush clears partial line")

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
let startFailureHandle = startFailureRunner.run(
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

let emptyConversationCoordinator = ConversationCoordinator()
expect(
    emptyConversationCoordinator.shortcutDecision() == .openFreshEntry,
    "shortcut opens fresh when no conversation"
)

let runningConversationCoordinator = ConversationCoordinator()
let runningConversation = runningConversationCoordinator.startConversation(prompt: "hello")
runningConversationCoordinator.markRunning(runningConversation.id)
expect(
    runningConversationCoordinator.shortcutDecision() == .recallExisting(runningConversation.id),
    "running conversation is recalled"
)

let pinnedConversationCoordinator = ConversationCoordinator()
let pinnedConversation = pinnedConversationCoordinator.startConversation(prompt: "pin me")
pinnedConversationCoordinator.setPinned(true, for: pinnedConversation.id)
expect(
    pinnedConversationCoordinator.shortcutDecision() == .recallExisting(pinnedConversation.id),
    "pinned conversation is recalled"
)

let keptConversationCoordinator = ConversationCoordinator()
let keptConversation = keptConversationCoordinator.startConversation(prompt: "keep me")
keptConversationCoordinator.setExplicitlyKept(true, for: keptConversation.id)
expect(
    keptConversationCoordinator.shortcutDecision() == .recallExisting(keptConversation.id),
    "explicitly kept conversation is recalled"
)

let completedConversationCoordinator = ConversationCoordinator()
let completedConversation = completedConversationCoordinator.startConversation(prompt: "complete me")
completedConversationCoordinator.setPermissionMode(.fullAccess, for: completedConversation.id)
completedConversationCoordinator.markCompleted(completedConversation.id)
expect(
    completedConversationCoordinator.activeConversation?.permissionMode == .semiAutomatic,
    "completed full-access conversation resets permission to semiAutomatic"
)
expect(
    completedConversationCoordinator.activeConversation?.state == .completed,
    "completed conversation state is completed"
)
expect(
    completedConversationCoordinator.shortcutDecision() == .openFreshEntry,
    "completed unkept conversation opens fresh shortcut entry"
)

let failedConversationCoordinator = ConversationCoordinator()
let failedConversation = failedConversationCoordinator.startConversation(prompt: "fail me")
failedConversationCoordinator.setPermissionMode(.fullAccess, for: failedConversation.id)
failedConversationCoordinator.markFailed(failedConversation.id, message: "boom")
expect(
    failedConversationCoordinator.activeConversation?.state == .failed,
    "failed conversation state is failed"
)
expect(
    failedConversationCoordinator.activeConversation?.permissionMode == .semiAutomatic,
    "failed full-access conversation resets permission to semiAutomatic"
)
if case let .error(_, text)? = failedConversationCoordinator.activeConversation?.events.last {
    expect(text == "boom", "failed conversation appends error message")
} else {
    expect(false, "failed conversation appends error message")
}

let stoppedConversationCoordinator = ConversationCoordinator()
let stoppedConversation = stoppedConversationCoordinator.startConversation(prompt: "stop me")
stoppedConversationCoordinator.setPermissionMode(.fullAccess, for: stoppedConversation.id)
stoppedConversationCoordinator.markStopped(stoppedConversation.id)
expect(
    stoppedConversationCoordinator.activeConversation?.state == .stopped,
    "stopped conversation state is stopped"
)
expect(
    stoppedConversationCoordinator.activeConversation?.permissionMode == .semiAutomatic,
    "stopped full-access conversation resets permission to semiAutomatic"
)

let closedConversationCoordinator = ConversationCoordinator()
let closedConversation = closedConversationCoordinator.startConversation(prompt: "close me")
closedConversationCoordinator.setPermissionMode(.fullAccess, for: closedConversation.id)
closedConversationCoordinator.setPinned(true, for: closedConversation.id)
closedConversationCoordinator.closeConversation(closedConversation.id)
expect(
    closedConversationCoordinator.activeConversation == nil,
    "closing a conversation clears the active conversation"
)
expect(
    closedConversationCoordinator.shortcutDecision() == .openFreshEntry,
    "closed conversation opens fresh shortcut entry"
)

let messageConversationCoordinator = ConversationCoordinator()
let messageConversation = messageConversationCoordinator.startConversation(prompt: "hello")
messageConversationCoordinator.appendCodexEvent(.agentMessage("world"), to: messageConversation.id)
expect(
    messageConversationCoordinator.activeConversation?.events.count == 2,
    "appending agent message creates a second event"
)
if case let .assistantMessage(_, text)? = messageConversationCoordinator.activeConversation?.events.last {
    expect(text == "world", "last appended event is assistant message text world")
} else {
    expect(false, "last appended event is assistant message text world")
}

let followUpConversationCoordinator = ConversationCoordinator()
let followUpConversation = followUpConversationCoordinator.startConversation(prompt: "hello")
followUpConversationCoordinator.appendUserPrompt("  follow up  ", to: followUpConversation.id)
expect(
    followUpConversationCoordinator.activeConversation?.events.count == 2,
    "appending follow-up user prompt creates a second event"
)
if case let .userPrompt(_, text)? = followUpConversationCoordinator.activeConversation?.events.last {
    expect(text == "follow up", "follow-up user prompt is trimmed and appended")
} else {
    expect(false, "follow-up user prompt appends user prompt event")
}

let cappedConversationCoordinator = ConversationCoordinator()
let cappedConversation = cappedConversationCoordinator.startConversation(prompt: "many events")
for index in 0..<520 {
    cappedConversationCoordinator.appendCodexEvent(.agentMessage("event \(index)"), to: cappedConversation.id)
}
let cappedEvents = cappedConversationCoordinator.activeConversation?.events ?? []
expect(
    cappedEvents.count == ConversationCoordinator.maxStoredEvents,
    "conversation coordinator caps stored display events"
)
if case let .assistantMessage(_, text)? = cappedEvents.first {
    expect(text == "event 20", "conversation event cap drops oldest events first")
} else {
    expect(false, "conversation event cap keeps recent assistant events")
}
if case let .assistantMessage(_, text)? = cappedEvents.last {
    expect(text == "event 519", "conversation event cap preserves latest event")
} else {
    expect(false, "conversation event cap preserves latest event")
}

let sideConversationCoordinator = ConversationCoordinator()
expect(sideConversationCoordinator.preferredSide == .right, "preferred side starts right")
sideConversationCoordinator.togglePreferredSide()
expect(sideConversationCoordinator.preferredSide == .left, "toggling preferred side switches right to left")
sideConversationCoordinator.togglePreferredSide()
expect(sideConversationCoordinator.preferredSide == .right, "toggling preferred side switches left to right")

let commandConversationCoordinator = ConversationCoordinator()
let commandConversation = commandConversationCoordinator.startConversation(prompt: "run pwd")
commandConversationCoordinator.appendCodexEvent(
    .command(id: "cmd1", command: "pwd", status: .completed),
    to: commandConversation.id
)
if case let .command(_, executionID, command, status)? = commandConversationCoordinator.activeConversation?.events.last {
    expect(executionID == "cmd1", "command display event preserves execution id")
    expect(command == "pwd", "command display event preserves command text")
    expect(status == .completed, "command display event preserves completed status")
} else {
    expect(false, "command display event preserves execution id, command text, and status")
}

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
expect(defaultTileOrder.tiles == [.battery, .codexUsage], "dashboard tile order defaults to battery then codex usage")
expect(defaultTileOrder.rawValue == "battery,codexUsage", "dashboard tile order serializes default order")

let reversedTileOrder = DashboardTileOrder(rawValue: "codexUsage,battery")
expect(reversedTileOrder.tiles == [.codexUsage, .battery], "dashboard tile order reads reversed persisted order")

let invalidTileOrder = DashboardTileOrder(rawValue: "battery,battery,unknown")
expect(invalidTileOrder.tiles == [.battery, .codexUsage], "dashboard tile order falls back when persisted order is invalid")

let swappedTileOrder = defaultTileOrder.swapping(.battery, with: .codexUsage)
expect(swappedTileOrder.tiles == [.codexUsage, .battery], "dashboard tile order swaps dragged and target tiles")
expect(
    defaultTileOrder.layoutTiles(excludingDragged: nil) == [.battery, .codexUsage],
    "dashboard tile layout shows all tiles when no tile is dragged"
)
expect(
    defaultTileOrder.layoutTiles(excludingDragged: .battery) == [.codexUsage],
    "dashboard tile layout removes dragged battery so codex usage can recenter"
)
expect(
    reversedTileOrder.layoutTiles(excludingDragged: .codexUsage) == [.battery],
    "dashboard tile layout removes dragged codex usage from reversed order"
)
expect(
    DashboardTileLayoutPolicy.placements(for: defaultTileOrder.tiles) == [
        DashboardTilePlacement(tile: .battery, centerX: -75, width: 92),
        DashboardTilePlacement(tile: .codexUsage, centerX: 52, width: 138)
    ],
    "dashboard tile layout places default tiles at stable visual centers"
)
expect(
    DashboardTileLayoutPolicy.placements(for: reversedTileOrder.tiles) == [
        DashboardTilePlacement(tile: .codexUsage, centerX: -52, width: 138),
        DashboardTilePlacement(tile: .battery, centerX: 75, width: 92)
    ],
    "dashboard tile layout places reversed tiles at stable visual centers"
)
expect(
    DashboardTileLayoutPolicy.placements(for: defaultTileOrder.layoutTiles(excludingDragged: .battery)) == [
        DashboardTilePlacement(tile: .codexUsage, centerX: 0, width: 138)
    ],
    "dashboard tile layout recenters the remaining codex tile while battery is dragged"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 135, rowWidth: 420, tiles: defaultTileOrder.tiles) == .battery,
    "dashboard tile hit testing selects battery at its visual center"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 262, rowWidth: 420, tiles: defaultTileOrder.tiles) == .codexUsage,
    "dashboard tile hit testing selects codex usage at its visual center"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 187, rowWidth: 420, tiles: defaultTileOrder.tiles) == nil,
    "dashboard tile hit testing ignores the gap between tiles"
)
expect(
    DashboardTileLayoutPolicy.tile(atX: 158, rowWidth: 420, tiles: reversedTileOrder.tiles) == .codexUsage,
    "dashboard tile hit testing follows reversed visual order"
)

let compactEntryBounds = CGRect(x: 0, y: 0, width: 420, height: 210)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 110, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact battery tile blocks window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 290, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact codex usage tile blocks window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 50, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact dashboard row outside the cards blocks window dragging"
)
expect(
    CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 210, y: 152),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact prompt area allows window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 110, y: 146),
        panelBounds: compactEntryBounds,
        verticalOrigin: .bottom
    ),
    "compact tile drag policy supports bottom-left AppKit coordinates"
)
expect(
    CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 210, y: 50),
        panelBounds: compactEntryBounds,
        verticalOrigin: .bottom
    ),
    "compact prompt drag policy supports bottom-left AppKit coordinates"
)

let compactSnapScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
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

let yellowCodexUsage = CodexUsageStatus(fiveHourPercent: 80, weeklyPercent: 75, observedAt: nil)
expect(yellowCodexUsage.ringColor(for: .fiveHour) == .midUsageYellow, "codex usage at eighty percent is yellow")
expect(
    yellowCodexUsage.ringColor(for: .weekly) != .lowUsageGreen,
    "codex usage between sixty and eighty percent interpolates away from green"
)

let redCodexUsage = CodexUsageStatus(fiveHourPercent: 96, weeklyPercent: 100, observedAt: nil)
expect(redCodexUsage.ringColor(for: .fiveHour) != .midUsageYellow, "codex usage above eighty percent interpolates away from yellow")
expect(redCodexUsage.ringColor(for: .weekly) == .highUsageRed, "codex usage at one hundred percent is red")

let clampedCodexUsage = CodexUsageStatus(fiveHourPercent: -5, weeklyPercent: 140, observedAt: nil)
expect(clampedCodexUsage.fiveHourPercent == 0, "codex usage clamps low percent to zero")
expect(clampedCodexUsage.weeklyPercent == 100, "codex usage clamps high percent to one hundred")

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
let codexUsageMonitor = CodexUsageMonitor(provider: codexUsageMonitorProvider)
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

let asyncCodexUsageStatus = CodexUsageStatus(
    fiveHourPercent: 66,
    weeklyPercent: 77,
    observedAt: Date(timeIntervalSince1970: 20)
)
let asyncCodexUsageProvider = BlockingCodexUsageProvider(status: asyncCodexUsageStatus)
let asyncCodexUsageMonitor = CodexUsageMonitor(provider: asyncCodexUsageProvider)
DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(350)) {
    asyncCodexUsageProvider.release()
}
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
    asyncCodexUsageMonitor.status == .unknown,
    "codex usage monitor keeps status unchanged while background provider work is pending"
)
expect(
    asyncCodexUsageProvider.waitUntilFinished(),
    "codex usage monitor slow provider finishes"
)
let asyncCodexUsageMonitorUpdated = waitUntil(timeout: 2) {
    asyncCodexUsageMonitor.status == asyncCodexUsageStatus
}
expect(
    asyncCodexUsageMonitorUpdated,
    "codex usage monitor publishes background provider status on the main actor"
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
let stoppedCodexUsageMonitor = CodexUsageMonitor(provider: stoppedCodexUsageProvider)
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

if failures.isEmpty {
    print("CodexPlusCoreTests passed: \(assertionCount) assertions")
} else {
    print("CodexPlusCoreTests failed: \(failures.count) of \(assertionCount) assertions failed")

    for failure in failures {
        print("- \(failure)")
    }

    exit(1)
}
