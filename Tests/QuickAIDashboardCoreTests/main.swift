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

let invalidBattery = BatteryStatus.from(
    currentCapacity: nil,
    maxCapacity: 0,
    isCharging: nil,
    powerSourceState: nil
)
expect(invalidBattery.percentage == nil, "invalid battery percentage")
expect(invalidBattery.state == .unknown, "invalid battery state")

if failures.isEmpty {
    print("QuickAIDashboardCoreTests passed: \(assertionCount) assertions")
} else {
    print("QuickAIDashboardCoreTests failed: \(failures.count) of \(assertionCount) assertions failed")

    for failure in failures {
        print("- \(failure)")
    }

    exit(1)
}
