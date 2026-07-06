import CoreGraphics

public enum WorkbenchInteractionPolicies {
    public static func composerAction(for state: ConversationRunState?) -> WorkbenchComposerAction {
        state == .running ? .stop : .send
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
