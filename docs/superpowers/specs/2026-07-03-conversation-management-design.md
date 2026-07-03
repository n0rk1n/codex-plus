# Conversation Management Design

Date: 2026-07-03

## Goal

Add browser-like conversation management to the top area of the side panel. Codex+ should support multiple parallel Codex tasks, grouped by working directory, with draggable tabs, archive actions, and a new-conversation draft state that can choose or create a workspace before the first prompt is sent.

This is the first slice of task and conversation control. It should feel close to the Codex Desktop app model: one window can multitask across projects, and each project is anchored to a local directory.

## Decisions

- Use a two-level tab model: workspace tabs first, conversation tabs second.
- A workspace tab represents one normalized local working directory.
- A conversation tab belongs to exactly one workspace after its first prompt is sent.
- Conversation titles are generated as `对话_1234`-style random names for this slice.
- New conversations start as a draft with a directory picker and prompt input.
- Selecting a directory is optional. If the user sends without selecting a directory, Codex+ creates a default workspace under `~/Documents/Codex Plus Workspace/YYYY-MM-DD-random`.
- If the chosen or default workspace path already has a workspace tab, the new conversation is merged into that workspace. Otherwise Codex+ creates a new workspace tab.
- After the first prompt is sent, the conversation workspace is fixed and the directory picker disappears.
- Multiple conversations can run in parallel. Switching tabs only switches the visible conversation.
- Tabs use archive actions instead of close actions.
- The archive icon appears on the left side of each conversation tab to match macOS tab habits.
- Workspace tabs and conversation tabs are both draggable. Conversation tabs only reorder within their current workspace.

## User Experience

The red-box header area becomes a compact task switcher.

The first row shows workspace tabs. Each workspace tab displays the directory name and uses a tooltip for the full path. The active workspace is highlighted. A workspace with at least one running conversation can show a small activity indicator.

The second row shows conversation tabs for the active workspace. Each tab has:

- Left archive icon.
- Generated title such as `对话_4821`.
- Small status indicator for running, completed, failed, or stopped.

The row also includes a `+` button for creating a new draft conversation.

The panel body has two states:

- Draft state: shows a directory picker and the prompt input. Sending creates or resolves the workspace, creates the conversation tab, and starts the first run.
- Conversation state: shows the selected conversation timeline and follow-up input. Follow-ups run in the conversation's fixed workspace.

When every active conversation is archived, the side panel animates back to the original compact input shape. The archive manager is out of scope for this slice.

## Archiving

Archiving removes the conversation from active tabs and marks it as archived. It does not delete conversation data.

If the conversation is running, Codex+ asks for confirmation. Confirming stops that conversation's run, marks it stopped, and archives it. Canceling keeps the run active.

If the conversation is already terminal, Codex+ archives immediately without confirmation.

When the active conversation is archived, selection changes as follows:

1. Look at the archived conversation's immediate left and right neighbors in the same workspace.
2. If both exist, select the one with the newest `lastActivityAt`.
3. If only one exists, select it.
4. If no conversation remains in that workspace, remove that workspace tab from the active tab row.
5. Select the remaining workspace with the newest `lastActivityAt`.
6. If no active conversation remains anywhere, enter draft/compact input state.

## Data Model

`ConversationSession` keeps its current fields and adds:

- `title: String`
- `workspacePath: String`
- `createdAt: Date`
- `lastActivityAt: Date`
- `isArchived: Bool`

`WorkspaceSessionGroup` is a lightweight grouping model:

- `id: UUID`
- `path: String`
- `displayName: String`
- `conversationIDs: [UUID]`
- `lastActivityAt: Date`

Workspaces do not need a persisted archive flag in this slice. A workspace appears when it has at least one unarchived conversation.

`ConversationCoordinator` owns the pure state transitions:

- Draft creation and cancellation.
- First-prompt commit into a workspace.
- Workspace path normalization and merge-by-path.
- Generated conversation titles with collision retries.
- Workspace ordering.
- Conversation ordering inside a workspace.
- Active workspace and active conversation selection.
- Archive selection fallback.
- Event append and `lastActivityAt` updates.
- Terminal state updates.

`lastActivityAt` updates when a user prompt is appended, a Codex event is appended, a run starts, a run finishes, a run fails, or a run is stopped.

## Default Workspace

If the user sends a first prompt without selecting a directory:

1. Codex+ creates the parent directory `~/Documents/Codex Plus Workspace` if needed.
2. It creates a child directory named `YYYY-MM-DD-random`, for example `2026-07-03-4821`.
3. If the generated directory already exists, it retries with a new random suffix.
4. The created directory becomes the conversation workspace.

The directory-creation logic belongs outside pure UI code. The core can provide the naming policy; the app layer performs filesystem creation and reports failures back to the coordinator.

## Parallel Runs

`CodexRunController` changes from one active run to a run registry keyed by conversation ID.

It stores:

- Active run handles by conversation ID.
- Run IDs by conversation ID.
- Stopped run IDs.
- Event handlers and finish handlers that include the conversation ID.

Starting a run is allowed when that conversation has no active run. Other conversations may already be running.

Stopping a run stops only the requested conversation. Finish callbacks are ignored unless both the conversation ID and run ID still match the current registered run.

`ProcessCodexRunner` should accept a working directory URL so each `codex exec --json` process runs in the conversation's fixed workspace.

## Window And App Responsibilities

The app layer owns:

- `NSOpenPanel` directory selection.
- Creating default workspace directories.
- Archive confirmation alerts for running conversations.
- Starting and stopping Codex processes.
- Panel frame transitions between compact input and conversation workspace.
- SwiftUI rendering and drag gestures.

The core layer owns:

- Selection decisions.
- Ordering decisions.
- Workspace grouping.
- Title and default directory naming policy.
- Per-conversation event routing state.

This keeps the hardest behavior testable without AppKit.

## Error Handling

If default workspace creation fails, Codex+ does not start a run. It shows an error in the draft state so the user can choose a directory and retry.

If the user selects a missing or inaccessible directory, the selection is rejected and the draft remains active.

If `codex exec` fails to start, only that conversation is marked failed. Other running conversations continue.

If a running conversation is archived and stopping fails or exits nonzero, Codex+ still records a stopped/archived state and appends a status or error event for future archive inspection.

If concurrent callbacks arrive while the user switches tabs, each event is routed by conversation ID, never by the currently visible tab.

## Testing

Core tests should cover:

- Default workspace parent and child naming.
- Workspace merge when two conversations use the same normalized path.
- Workspace creation when paths differ.
- Generated `对话_1234` titles are unique within the coordinator.
- Workspace reorder.
- Conversation reorder within one workspace.
- Conversation reorder does not move a conversation to another workspace.
- Archiving the active conversation selects the left or right neighbor with the newest `lastActivityAt`.
- Archiving the last conversation in a workspace selects the newest remaining workspace.
- Archiving the last active conversation leaves no active conversation and enters draft/compact state.
- Appending events to one conversation does not affect another conversation.
- Parallel run registry allows two different conversation IDs to run at once.
- Parallel run registry rejects starting a second run for the same conversation.
- Stopping one conversation does not stop another conversation.

Manual verification should cover:

- Start two long-running conversations in two workspaces.
- Switch between tabs while both update.
- Archive a running conversation, cancel the confirmation, and confirm the run continues.
- Archive a running conversation, confirm, and verify only that run stops.
- Archive a completed conversation and verify it disappears immediately.
- Drag workspace tabs and conversation tabs.
- Use `+` to create a draft and send without choosing a directory.
- Confirm the default directory is created under `~/Documents/Codex Plus Workspace`.
- Archive all active conversations and verify the panel returns to compact input.

## Out Of Scope

- Archive manager UI.
- Persistent history restore across app launches.
- Codex Desktop Local/Worktree/Cloud mode selection.
- Worktree creation.
- Smart conversation title generation.
- Cross-workspace conversation drag and drop.
- Searching archived or active conversations.
