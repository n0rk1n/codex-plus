import XCTest
@testable import CodexPlusCore

final class ProjectSelectionPolicyTests: XCTestCase {
    func testFallbackSelectsFirstVisibleConversationInWorkspace() {
        let workspaceID = UUID()
        let visibleID = UUID()
        let archivedID = UUID()
        let workspace = WorkspaceSessionGroup(
            id: workspaceID,
            path: "/tmp/project",
            displayName: "project",
            conversationIDs: [archivedID, visibleID],
            lastActivityAt: Date(timeIntervalSince1970: 20)
        )
        let conversations = [
            ConversationSession(id: archivedID, title: "archived", prompt: "", workspacePath: "/tmp/project", isArchived: true),
            ConversationSession(id: visibleID, title: "visible", prompt: "", workspacePath: "/tmp/project")
        ]

        let selected = ProjectSelectionPolicy.firstVisibleConversationID(
            in: workspaceID,
            workspaces: [workspace],
            conversations: conversations
        )

        XCTAssertEqual(selected, visibleID)
    }

    func testClearingActiveConversationFallsBackInsideActiveWorkspace() {
        let workspaceID = UUID()
        let removedID = UUID()
        let nextID = UUID()
        var state = WorkbenchState.empty
        state.workspaces = [
            WorkspaceSessionGroup(
                id: workspaceID,
                path: "/tmp/project",
                displayName: "project",
                conversationIDs: [removedID, nextID],
                lastActivityAt: Date()
            )
        ]
        state.conversations = [
            ConversationSession(id: removedID, title: "removed", prompt: "", workspacePath: "/tmp/project", isArchived: true),
            ConversationSession(id: nextID, title: "next", prompt: "", workspacePath: "/tmp/project")
        ]
        state.activeWorkspaceID = workspaceID
        state.activeConversationID = removedID

        let updated = ProjectSelectionPolicy.repairActiveSelection(in: state)

        XCTAssertEqual(updated.activeWorkspaceID, workspaceID)
        XCTAssertEqual(updated.activeConversationID, nextID)
    }
}
