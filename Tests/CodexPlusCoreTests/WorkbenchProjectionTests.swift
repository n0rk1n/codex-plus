import Foundation
import CoreGraphics
import CodexPlusCore

@MainActor
func runWorkbenchProjectionTests() {
    let workspaceA = WorkspaceSessionGroup(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        path: "/tmp/mft-project",
        displayName: "mft-project",
        conversationIDs: [],
        lastActivityAt: Date(timeIntervalSince1970: 10)
    )
    let workspaceBID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let conversationB1ID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBB01")!
    let conversationB2ID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBB02")!
    let archivedB3ID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBB03")!
    let workspaceB = WorkspaceSessionGroup(
        id: workspaceBID,
        path: "/tmp/codex-plus",
        displayName: "codex-plus",
        conversationIDs: [conversationB1ID, conversationB2ID, archivedB3ID],
        lastActivityAt: Date(timeIntervalSince1970: 20)
    )
    let conversations = [
        ConversationSession(
            id: conversationB1ID,
            title: "重设计 Codex 软件",
            prompt: "start",
            workspacePath: "/tmp/codex-plus",
            state: .running,
            lastActivityAt: Date(timeIntervalSince1970: 40)
        ),
        ConversationSession(
            id: conversationB2ID,
            title: "整理实现计划",
            prompt: "plan",
            workspacePath: "/tmp/codex-plus",
            state: .completed,
            lastActivityAt: Date(timeIntervalSince1970: 30)
        ),
        ConversationSession(
            id: archivedB3ID,
            title: "已归档旧会话",
            prompt: "archive",
            workspacePath: "/tmp/codex-plus",
            state: .completed,
            isArchived: true,
            lastActivityAt: Date(timeIntervalSince1970: 50)
        )
    ]

    let cards = WorkbenchProjection.projectCards(
        workspaces: [workspaceA, workspaceB],
        conversations: conversations,
        activeWorkspaceID: workspaceBID,
        activeConversationID: conversationB1ID
    )

    expect(cards.count == 1, "workbench projection hides workspaces without visible conversations")
    expect(!cards.contains(where: { $0.projectPath == "/tmp/mft-project" }), "empty workspace does not render a project card")
    expect(cards[0].projectName == "codex-plus", "project card keeps workspace display name")
    expect(cards[0].conversationTitle == "重设计 Codex 软件", "active conversation is displayed first")
    expect(cards[0].visibleConversationCount == 2, "archived conversations are excluded from count")
    expect(cards[0].overflowCount == 2, "multiple visible conversations produce a dropdown count")
    expect(
        cards[0].conversationSummaries.map(\.id) == [conversationB1ID, conversationB2ID],
        "multiple visible conversations are available for overflow selection"
    )
    expect(cards[0].isActive, "active workspace card is marked active")

    expect(
        !WorkbenchInteractionPolicies.shouldShowProjectCardRail(projectCardCount: 0),
        "empty workbench top strip does not reserve project card rail height"
    )
    expect(
        WorkbenchInteractionPolicies.shouldShowProjectCardRail(projectCardCount: cards.count),
        "workbench top strip shows the project card rail when cards exist"
    )

    expect(
        WorkbenchInteractionPolicies.composerAction(for: .running) == .stop,
        "running conversation shows stop action"
    )
    expect(
        WorkbenchInteractionPolicies.composerAction(for: .completed) == .send,
        "completed conversation shows send action"
    )
    expect(
        WorkbenchInteractionPolicies.composerAction(for: .failed) == .send,
        "failed conversation shows send action"
    )
    expect(
        !WorkbenchInteractionPolicies.canStartNewConversation(activeConversationState: nil),
        "blank workbench cannot start another blank new conversation"
    )
    expect(
        WorkbenchInteractionPolicies.canStartNewConversation(activeConversationState: .completed),
        "completed conversation can start a new conversation"
    )
    expect(
        WorkbenchInteractionPolicies.canStartNewConversation(activeConversationState: .stopped),
        "stopped conversation can start a new conversation"
    )
    expect(
        !WorkbenchInteractionPolicies.canStartNewConversation(activeConversationState: .running),
        "running conversation cannot start a new conversation"
    )
    expect(
        WorkbenchInteractionPolicies.shouldHideForOutsideClick(
            isPinned: false,
            clickPoint: CGPoint(x: 20, y: 20),
            panelFrame: CGRect(x: 100, y: 100, width: 800, height: 500)
        ),
        "unpinned workbench hides for outside click"
    )
    expect(
        !WorkbenchInteractionPolicies.shouldHideForOutsideClick(
            isPinned: false,
            clickPoint: CGPoint(x: 200, y: 200),
            panelFrame: CGRect(x: 100, y: 100, width: 800, height: 500)
        ),
        "unpinned workbench stays visible for inside click"
    )
    expect(
        !WorkbenchInteractionPolicies.shouldHideForOutsideClick(
            isPinned: true,
            clickPoint: CGPoint(x: 20, y: 20),
            panelFrame: CGRect(x: 100, y: 100, width: 800, height: 500)
        ),
        "pinned workbench ignores outside click"
    )
    expect(
        WorkbenchInteractionPolicies.requiresStopBeforeArchive(state: .running),
        "running conversation requires stop before archive"
    )
}
