import CoreGraphics

public enum WorkbenchInteractionPolicies {
    public static func composerAction(for state: ConversationRunState?) -> WorkbenchComposerAction {
        state == .running ? .stop : .send
    }

    public static func canStartNewConversation(activeConversationState: ConversationRunState?) -> Bool {
        guard let activeConversationState else {
            return false
        }

        return activeConversationState != .running
    }

    public static func shouldShowProjectCardRail(projectCardCount: Int) -> Bool {
        projectCardCount > 0
    }

    public static func shouldHideForOutsideClick(
        isPinned: Bool,
        clickPoint: CGPoint,
        panelFrame: CGRect
    ) -> Bool {
        !isPinned && !panelFrame.contains(clickPoint)
    }

    public static func requiresStopBeforeArchive(state: ConversationRunState) -> Bool {
        state == .running
    }
}
