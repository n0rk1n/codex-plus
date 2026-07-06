import CodexPlusCore
import SwiftUI

struct WorkbenchView: View {
    @ObservedObject var store: WorkbenchStore

    var body: some View {
        LiquidGlassScene(padding: 0, minWidth: 980, minHeight: 620) {
            VStack(spacing: 12) {
                TopProjectStripView(
                    cards: store.snapshot.projectCards,
                    isPinned: store.snapshot.isPinned,
                    onNewConversation: { store.beginNewConversationDraft() },
                    onOpenArchive: { store.showArchiveSearch() },
                    onTogglePin: { store.togglePin() },
                    onSelectProject: { store.selectProject($0) },
                    onSelectConversation: { store.selectConversation($0) }
                )

                if store.snapshot.isShowingArchiveSearch {
                    ArchivedConversationView(
                        results: store.snapshot.archiveSearchResults,
                        openedConversation: store.snapshot.openedArchiveConversation,
                        onSearch: { store.searchArchives($0) },
                        onOpen: { store.openArchive($0) }
                    )
                } else {
                    WorkbenchConversationView(
                        snapshot: store.snapshot,
                        onArchiveConversation: { _ = store.archiveConversation($0) }
                    )

                    WorkbenchComposerView(
                        snapshot: store.snapshot,
                        onSend: { store.submitPrompt($0) },
                        onStop: { store.stopActiveRun() }
                    )
                }

                WorkbenchStatusBarView(state: store.snapshot.statusBar)
            }
            .padding(18)
            .alert("终止任务后归档？", isPresented: pendingArchiveConfirmationBinding) {
                Button("取消", role: .cancel) {
                    store.cancelArchiveConfirmation()
                }
                Button("停止并归档", role: .destructive) {
                    store.confirmPendingStopAndArchive()
                }
            } message: {
                Text("这个对话仍在运行。归档前需要先停止当前 Codex 任务；停止后会保存完整事件流，并将对话标记为已归档。")
            }
        }
    }

    private var pendingArchiveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { store.snapshot.pendingArchiveConfirmationConversationID != nil },
            set: { isPresented in
                if !isPresented {
                    store.cancelArchiveConfirmation()
                }
            }
        )
    }
}
