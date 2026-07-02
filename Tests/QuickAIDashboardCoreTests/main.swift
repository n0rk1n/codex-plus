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

expect(!ConversationRunState.idle.isTerminal, "idle should not be terminal")
expect(!ConversationRunState.running.isTerminal, "running should not be terminal")
expect(ConversationRunState.completed.isTerminal, "completed should be terminal")
expect(ConversationRunState.failed.isTerminal, "failed should be terminal")
expect(ConversationRunState.stopped.isTerminal, "stopped should be terminal")

if failures.isEmpty {
    print("QuickAIDashboardCoreTests passed: \(assertionCount) assertions")
} else {
    print("QuickAIDashboardCoreTests failed: \(failures.count) of \(assertionCount) assertions failed")

    for failure in failures {
        print("- \(failure)")
    }

    exit(1)
}
