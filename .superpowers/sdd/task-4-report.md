# Task 4 Report: App Integration And Tab UI

## Status

Completed the Task 4 app-side integration in the worktree at `/Users/oriki/Documents/codex-plus/.worktrees/conversation-management`.

## Scope

Modified:

- `Sources/CodexPlusApp/PermissionPrompter.swift`
- `Sources/CodexPlusApp/WindowCoordinator.swift`
- `Sources/CodexPlusApp/Views/ConversationPanelHostView.swift`
- `Sources/CodexPlusApp/Views/ConversationView.swift`

Created:

- `Sources/CodexPlusApp/Views/ConversationTabHeaderView.swift`
- `Sources/CodexPlusApp/Views/ConversationDraftView.swift`

No core model changes, archive manager work, persistence, smart titles, worktree modes, cross-workspace drag, or search were added.

## Implementation Summary

### Side panel snapshot and draft rendering

- Replaced the side-panel model from a single `ConversationSession` binding to a full `ConversationCoordinatorSnapshot`.
- Updated `ConversationPanelHostView` and `ConversationView` to render either:
  - the active conversation timeline and follow-up composer, or
  - the draft composer when there is no active conversation.
- Used a stable panel identity:
  - active conversation -> `"conversation-<uuid>"`
  - draft -> `"conversation-draft"`
  so draft state is not reset by a volatile `.id(UUID())`.

### Two-level tab header

- Added `ConversationTabHeaderView` with:
  - workspace tabs on the first row
  - conversation tabs for the active workspace on the second row
  - a `+` action to start a draft
  - archive affordance on the left side of each conversation tab
  - drag reorder for workspace tabs and conversation tabs
- Kept archive and tab selection as separate controls to avoid nested SwiftUI buttons.

### Draft flow and workspace selection

- Added `ConversationDraftView` with:
  - optional workspace picker
  - draft error display
  - first-prompt composer
- Added `NSOpenPanel`-based workspace picking in `WindowCoordinator`.
- Added default workspace creation under:
  - `~/Documents/Codex Plus Workspace/YYYY-MM-DD-random`
  when the user starts the first prompt without selecting a workspace.
- Existing conversations continue using their fixed workspace path after the first prompt.

### Run and archive behavior

- `showSidePanel()` now supports rendering draft state when `activeConversation == nil`.
- `refreshSidePanelContent()` now updates/install content even without an active conversation.
- `handleFollowUp` now blocks only duplicate runs in the same conversation via `runController.isRunning(sessionID:)`.
- `startCodexRun` now:
  - checks running state per session
  - reads permission mode from the target session ID
  - passes `workingDirectoryURL` from that conversation's workspace path
- Added archive confirmation for running conversations:
  - confirm -> stop that session, mark stopped, archive
  - cancel -> leave the run untouched
- Idle/completed/failed/stopped conversations archive directly.
- Archiving the active final conversation animates the side panel back to compact entry.

## Verification

### Build

Command:

```bash
swift build
```

Result:

- PASS

### Core tests

Sandboxed attempt:

```bash
swift run CodexPlusCoreTests
```

Result:

- failed before execution due:
  - sandboxed module cache write denial at `/Users/oriki/.cache/clang/ModuleCache/...`
  - local SDK/compiler mismatch reported by Swift manifest compilation

Escalated rerun:

```bash
swift run CodexPlusCoreTests
```

Result:

- PASS
- `CodexPlusCoreTests passed: 231 assertions`

## Self-Review Against Required Checks

- Draft rendering without active conversation:
  - verified in code path by removing the old `activeConversation` guard from `refreshSidePanelContent` and letting `showSidePanel()` accept draft snapshots.
- Archive confirmation flow:
  - running sessions confirm before archive; confirmed path stops only that session and archives; cancel returns early.
- Per-session running checks:
  - follow-up and start guards use `runController.isRunning(sessionID:)`.
  - permission mode lookup also uses the target session ID.
- Default workspace creation path:
  - created through `ConversationWorkspacePolicy.defaultWorkspacePath(...)` rooted at the current user's home directory.
- Drag reorder compile:
  - new `onDrag` / `onDrop` tab code compiled successfully in `swift build`.
- Nested button avoidance:
  - archive button and conversation-selection button are siblings inside the tab row, not nested.

## Commit

Prepared for commit with the requested Task 4 scope.
