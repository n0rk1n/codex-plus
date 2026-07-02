# Quick AI Dashboard MVP Smoke Test - 2026-07-02

Run from the repository root.

## Automated Checks

- [ ] Build
  - Run: `swift build`
  - Expect: build completes successfully.
- [ ] Unit/core harness
  - Run: `swift run QuickAIDashboardCoreTests`
  - Expect: custom test harness completes successfully.

## Manual Smoke

- [ ] App launch
  - Run: `swift run QuickAIDashboardApp`
  - Expect: app launches as an accessory app without a Dock window.
- [ ] Global shortcut
  - Press: Control-Option-Space
  - Expect: compact panel opens near the upper third and centered horizontally.
- [ ] Compact panel layout
  - Expect: exactly two vertical layers.
  - Expect: top layer contains one square battery tile.
  - Expect: bottom layer contains one focused AI input.
  - Press Enter with an empty input.
  - Expect: compact panel does not expand.
- [ ] Conversation start
  - Type: `Say hello in one sentence.`
  - Press Enter.
  - Expect: compact panel hides.
  - Expect: side conversation opens on the right edge.
  - Expect: Codex events stream, or a clear Codex startup error appears.
- [ ] Window hide and recall behavior
  - Move the mouse outside the unpinned window.
  - Expect: window hides.
  - Press Control-Option-Space while a conversation is running.
  - Expect: existing conversation is recalled.
  - Pin the window and move the mouse outside.
  - Expect: pinned window does not hide.
  - Press Control-Option-Space while pinned.
  - Expect: existing conversation is recalled.
- [ ] Side switch
  - Switch side from right to left, then left to right.
  - Expect: window moves to the selected screen edge each time.
- [ ] Stop and permission reset
  - Start a conversation, then stop it.
  - Expect: conversation state changes to stopped.
  - Set permission to Full Access and complete, fail, or stop a run.
  - Expect: permission resets to Semi-Automatic after stop, complete, or fail.

## Out Of Scope

- History and persistence are intentionally out of MVP smoke scope.
- System switches are intentionally out of MVP smoke scope.
- Homebrew packaging is intentionally out of MVP smoke scope.
- Diagnostics are intentionally out of MVP smoke scope.
