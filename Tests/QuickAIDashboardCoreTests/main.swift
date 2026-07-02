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

expect(!ConversationRunState.idle.isTerminal, "idle should not be terminal")
expect(!ConversationRunState.running.isTerminal, "running should not be terminal")
expect(ConversationRunState.completed.isTerminal, "completed should be terminal")
expect(ConversationRunState.failed.isTerminal, "failed should be terminal")
expect(ConversationRunState.stopped.isTerminal, "stopped should be terminal")

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
