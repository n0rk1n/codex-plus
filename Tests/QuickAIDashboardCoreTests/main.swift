import Foundation
import QuickAIDashboardCore

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

@MainActor
func makeTemporaryScript(named name: String, contents: String) -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "quick-ai-dashboard-\(UUID().uuidString)-\(name).sh"
    )

    do {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        expect(false, "temporary script \(name) can be written")
    }

    return url.path
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
    "quick-ai-dashboard-missing-\(UUID().uuidString)"
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

if failures.isEmpty {
    print("QuickAIDashboardCoreTests passed: \(assertionCount) assertions")
} else {
    print("QuickAIDashboardCoreTests failed: \(failures.count) of \(assertionCount) assertions failed")

    for failure in failures {
        print("- \(failure)")
    }

    exit(1)
}
