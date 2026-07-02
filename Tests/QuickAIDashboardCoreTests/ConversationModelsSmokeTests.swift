import XCTest
@testable import QuickAIDashboardCore

final class ConversationModelsSmokeTests: XCTestCase {
    func testPermissionModeDisplayName() {
        XCTAssertEqual(PermissionMode.semiAutomatic.displayName, "Semi-Automatic")
        XCTAssertEqual(PermissionMode.fullAccess.displayName, "Full Access")
    }

    func testTerminalStates() {
        XCTAssertFalse(ConversationRunState.idle.isTerminal)
        XCTAssertFalse(ConversationRunState.running.isTerminal)
        XCTAssertTrue(ConversationRunState.completed.isTerminal)
        XCTAssertTrue(ConversationRunState.failed.isTerminal)
        XCTAssertTrue(ConversationRunState.stopped.isTerminal)
    }
}
