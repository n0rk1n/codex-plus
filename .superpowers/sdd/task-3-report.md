# Task 3 Report

## Scope

Migrated the Task 3 workbench/shared app button surfaces to `CodexButton` rules in the 12 task-owned source/test files only. I did not edit, stage, or commit `Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift`.

## What Changed

- Routed workbench strip, project card, composer action, archive, restore-link, launcher, compact entry, desktop tile, side affordance, error-dismiss, and technical-group row buttons through `CodexButton`.
- Moved disabled/help/accessibility metadata into wrapper arguments where the migrated buttons needed it.
- Removed page-owned `.buttonStyle(.plain)` and button hit-area helper calls from the migrated button sites.
- Updated source tests from old hit-area assertions to rule-wrapper assertions for the archived row, top project card, and top-strip icon button checks.
- Swapped two remaining Task 3 page-level glass usages that still tripped source tests:
  - `WorkbenchView` error banner now uses `LiquidGlassContainer`.
  - `SideEdgeAffordanceView` no longer applies page-owned button glass styling inside the label.

## Verification

Command run:

```bash
swift run CodexPlusCoreLegacyTests
```

Result: exited with code `1`, but the remaining failures are limited to the expected non-Task-3 areas:

- `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`
- `Sources/CodexPlusApp/Legacy/Views/ConversationDraftView.swift`
- `Sources/CodexPlusApp/Legacy/Views/ConversationView.swift`
- `Sources/CodexPlusApp/Legacy/Views/ConversationTabHeaderView.swift`
- `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift` for the still-native input/glass control pieces
- `Sources/CodexPlusApp/Workbench/ArchivedConversationView.swift` for the still-native search `TextField`

Task 3-owned workbench/shared button wrapper failures were cleared in the rerun.

## Self-Review

- Kept edits within the task-owned files and left the unrelated `WorkbenchPanelController.swift` change alone.
- Followed the Task 2 interface update by using `isDisabled:` on migrated app-owned buttons instead of leaving trailing `.disabled(...)`.
- Preserved existing copy, help text, accessibility labels, swipe actions, and card/menu behavior.
- `WorkbenchLauncherView` now uses `CodexButton` for rule compliance; the panel host still owns click-vs-drag behavior externally, so the wrapper action remains empty by design in this task.

## Review Fixes

- Restored the top-strip project card rail in `TopProjectStripView`:
  - `cards: [WorkbenchProjectCard]` is present again.
  - the horizontal `ScrollView(.horizontal)` rail is back behind `WorkbenchInteractionPolicies.shouldShowProjectCardRail(projectCardCount: cards.count)`.
  - project cards again preserve the pre-Task-3 content and native `Menu` rows, but now route through `CodexButton(rule: .cardRounded(cornerRadius: WorkbenchMetrics.projectCardCornerRadius), action: ...)`.
- Wired `WorkbenchLauncherView` to a real activation closure:
  - `let onActivate: () -> Void`
  - `CodexButton(..., action: onActivate)`
  - `WorkbenchLauncherPanelController.show()` now passes `WorkbenchLauncherView(onActivate: onOpenWorkbench)` while keeping `onClick: onOpenWorkbench` in the host for the existing click/drag path.
- Removed the unrelated workbench sizing assertion from `PromptTemplateManagerAppSourceTests.swift`.
- Replaced the rail-deletion approval assertion with positive source checks that the top strip still contains the rail and uses the shared rounded card rule.
- Restored `SideEdgeAffordanceView` visual structure through `CodexButton(rule: .toolbarCapsule)` by returning the capsule label with padding and keeping glass ownership in the rule layer. No `CodexButton.swift` change was needed because `.toolbarCapsule` already carried the required visual treatment.

## Review Fix Verification

Re-ran:

```bash
swift run CodexPlusCoreLegacyTests
```

Result: exited with code `1`, with remaining failures limited to the expected non-Task-3 areas:

- `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`
- `Sources/CodexPlusApp/Legacy/Views/ConversationDraftView.swift`
- `Sources/CodexPlusApp/Legacy/Views/ConversationView.swift`
- `Sources/CodexPlusApp/Legacy/Views/ConversationTabHeaderView.swift`
- `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift`
- `Sources/CodexPlusApp/Workbench/ArchivedConversationView.swift`

The new review-targeted source assertions passed:

- top-strip rail exists and uses `.cardRounded(...)`
- launcher button and host click path both use `onOpenWorkbench`
- no Task 3-owned workbench/shared button failures reappeared
