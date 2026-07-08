import CodexPlusCore
import SwiftUI

struct TopProjectStripView: View {
    let isPinned: Bool
    let isNewConversationDisabled: Bool
    let isShowingArchiveSearch: Bool
    let actions: ProjectStripActions

    var body: some View {
        HStack(spacing: 8) {
            stripActionButton(title: firstActionTitle, systemName: firstActionSystemName, action: firstAction)
                .disabled(!isShowingArchiveSearch && isNewConversationDisabled)
                .opacity(!isShowingArchiveSearch && isNewConversationDisabled ? 0.45 : 1)
            stripActionButton(title: WorkbenchStrings.archived, systemName: "archivebox", action: actions.openArchive)
            Spacer(minLength: 0)
            iconActionButton(
                help: WorkbenchStrings.openSettingsHelp,
                systemName: "gearshape",
                accessibilityLabel: WorkbenchStrings.openSettings,
                action: actions.openSettings
            )
            pinButton
        }
    }

    private var firstActionTitle: String {
        isShowingArchiveSearch ? "回到对话" : WorkbenchStrings.newConversation
    }

    private var firstActionSystemName: String {
        isShowingArchiveSearch ? "bubble.left" : "square.and.pencil"
    }

    private var firstAction: () -> Void {
        isShowingArchiveSearch ? actions.returnToConversation : actions.newConversation
    }

    private var pinButton: some View {
        iconActionButton(
            help: isPinned ? WorkbenchStrings.unpinWindow : WorkbenchStrings.pinWindow,
            systemName: isPinned ? "pin.fill" : "pin",
            accessibilityLabel: isPinned ? WorkbenchStrings.unpinWindow : WorkbenchStrings.pinWindow,
            action: actions.togglePin
        )
    }

    private func stripActionButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        CodexButton(rule: .toolbarCapsule, action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private func iconActionButton(
        help: String,
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        CodexButton(
            rule: .toolbarIconCircle,
            help: help,
            accessibilityLabel: accessibilityLabel,
            action: action
        ) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
        }
    }
}
