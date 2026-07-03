# Final Review Fix Report

Date: 2026-07-03
Branch: `codex/conversation-management`

## Scope

Fixed the two requested findings within the allowed write scope:

1. `ConversationCoordinator.shortcutDecision()` now prefers draft recall over the archive-only fallback.
2. The compact folder button now carries the current prompt into the draft-opening path so typed text is preserved.

## Changes Made

### `Sources/CodexPlusCore/ConversationCoordinator.swift`

- Reordered `shortcutDecision()` so `.recallDraft` is checked before the archive-only `.openFreshEntry` fallback.
- Preserved the existing `.recallConversation`, `.recallDraft`, and `.openFreshEntry` API.

### `Tests/CodexPlusCoreTests/main.swift`

- Added a regression test for the archive-only + draft case:
  - archive the only conversation,
  - create a draft,
  - expect `shortcutDecision()` to return `.recallDraft`.

### `Sources/CodexPlusApp/Views/CompactEntryView.swift`

- Changed `onOpenDraft` to accept the current prompt string.
- The folder button now passes the live compact prompt into that closure.

### `Sources/CodexPlusApp/Views/CompactEntryHostView.swift`

- Updated the `onOpenDraft` closure type to match the new prompt-aware callback.

### `Sources/CodexPlusApp/WindowCoordinator.swift`

- Forwarded the prompt from the compact entry view into `openDraftFromCompactEntry(prompt:)`.
- `openDraftFromCompactEntry(prompt:)` now calls `conversationCoordinator.beginDraft(prompt: prompt)` so the typed text survives the transition.

## RED / GREEN

### Red

The first test run after adding the regression case hit the environment blocker before the test could execute:

- `swift run CodexPlusCoreTests`
- blocker: `sandbox-exec: sandbox_apply: Operation not permitted`
- initial run also reported the default SwiftPM module-cache / SDK mismatch issues from this container toolchain.

### Green

After rerunning with escalated SwiftPM execution, the regression passed:

- `CodexPlusCoreTests passed: 243 assertions`

Then the package build passed:

- `Build complete!`

## Notes

- The shortcut behavior now correctly distinguishes "archive-only history with no draft" from "archive-only history with an active draft."
- The compact entry button now preserves the user’s typed prompt instead of opening an empty draft.
