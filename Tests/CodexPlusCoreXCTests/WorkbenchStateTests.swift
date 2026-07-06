import XCTest
@testable import CodexPlusCore

final class WorkbenchStateTests: XCTestCase {
    func testWorkbenchErrorStateFactoryKeepsUserVisibleMessage() {
        let error = WorkbenchErrorState(
            title: "无法保存对话",
            message: "SQLite write failed",
            recoverySuggestion: "请检查磁盘空间后重试。"
        )

        XCTAssertFalse(error.id.uuidString.isEmpty)
        XCTAssertEqual(error.title, "无法保存对话")
        XCTAssertEqual(error.message, "SQLite write failed")
        XCTAssertEqual(error.recoverySuggestion, "请检查磁盘空间后重试。")
    }

    func testWorkbenchStateEmptyInitialState() {
        let state = WorkbenchState.empty

        XCTAssertTrue(state.workspaces.isEmpty)
        XCTAssertTrue(state.conversations.isEmpty)
        XCTAssertNil(state.activeWorkspaceID)
        XCTAssertNil(state.activeConversationID)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isShowingArchiveSearch)
    }
}
