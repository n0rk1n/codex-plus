# Main Panel Window Behavior Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add live midline snapping while dragging the side conversation panel and make Escape hide that panel only when it is the current key or main window.

**Architecture:** Reuse the existing `DraggableHostingView` manual drag loop and `CompactPanelSnapPolicy` instead of adding a new controller path. `SidePanelController` opts its hosting view into the side-panel drag mode and tightens its existing Escape monitor.

**Tech Stack:** Swift 6.2 package, AppKit `NSPanel`/`NSEvent`, SwiftUI hosting views, assert-style `CodexPlusCoreTests` executable.

## Global Constraints

- Applies only to the `SidePanelController` panel.
- The compact prompt panel keeps its existing drag and Escape behavior.
- Do not alter conversation state, archiving, pinning, run cancellation, or the side-edge affordance.
- Midline snapping uses `CompactPanelSnapPolicy.snappedFrame(for:in:)`.
- Escape dismissal for the side panel requires the panel to be visible and either `isKeyWindow` or `isMainWindow`.
- Verification commands: `swift run CodexPlusCoreTests` and `swift build`.

---

## File Structure

- Modify `Tests/CodexPlusCoreTests/main.swift`: add regression checks for side-panel-sized midline snapping and source-level integration hooks.
- Modify `Sources/CodexPlusApp/DraggableHostingView.swift`: add a side-panel drag mode and share the existing manual drag path.
- Modify `Sources/CodexPlusApp/SidePanelController.swift`: install the side-panel drag mode and require current-window status before Escape hides the panel.

### Task 1: Add Failing Regression Checks

**Files:**
- Modify: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Consumes: `CompactPanelSnapPolicy.snappedFrame(for:in:)`
- Produces: failing assertions that Task 2 must satisfy:
  - `WindowDragMode.sidePanel` appears in app source.
  - `contentView.windowDragMode = .sidePanel` appears in `SidePanelController`.
  - `panel.isKeyWindow || panel.isMainWindow` appears in side-panel Escape handling.

- [ ] **Step 1: Add source path for `DraggableHostingView.swift`**

In the existing file path block near the other app source path constants, add:

```swift
let draggableHostingViewPath = "Sources/CodexPlusApp/DraggableHostingView.swift"
```

- [ ] **Step 2: Add failing side-panel source checks**

After the existing `sidePanelControllerText` Escape and outside-click checks, add:

```swift
let draggableHostingViewText = (try? String(
    contentsOf: packageRoot.appendingPathComponent(draggableHostingViewPath),
    encoding: .utf8
)) ?? ""
expect(
    draggableHostingViewText.contains("case sidePanel")
        && sidePanelControllerText.contains("contentView.windowDragMode = .sidePanel"),
    "side panel opts into manual drag mode for live midline snapping"
)
expect(
    sidePanelControllerText.contains("panel.isKeyWindow || panel.isMainWindow"),
    "side panel escape dismissal only applies to the current key or main window"
)
```

- [ ] **Step 3: Add failing side-panel geometry check**

Near the existing `CompactPanelSnapPolicy` assertions, after `offsetNearMidlineFrame`, add:

```swift
let sidePanelNearMidlineFrame = CGRect(x: 298, y: 80, width: 860, height: 720)
expect(
    CompactPanelSnapPolicy.snappedFrame(
        for: sidePanelNearMidlineFrame,
        in: compactSnapScreen
    ) == CGRect(x: 290, y: 80, width: 860, height: 720),
    "side-panel-sized frames snap their center to the screen midline"
)
```

- [ ] **Step 4: Run test to verify it fails**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: FAIL with messages for missing side-panel drag mode and missing current-window Escape check. The geometry assertion may already pass because it reuses the existing snap policy.

- [ ] **Step 5: Keep the red tests in the working tree**

Do not commit while the test executable reports failures. Leave the changed
`Tests/CodexPlusCoreTests/main.swift` file in the working tree for Task 2.

### Task 2: Implement Main Panel Drag Mode And Escape Gate

**Files:**
- Modify: `Sources/CodexPlusApp/DraggableHostingView.swift`
- Modify: `Sources/CodexPlusApp/SidePanelController.swift`

**Interfaces:**
- Consumes:
  - `DraggableHostingView.WindowDragMode.sidePanel`
  - `CompactPanelSnapPolicy.snappedFrame(for:in:)`
  - `CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode:)`
- Produces:
  - `WindowDragMode.sidePanel`
  - `contentView.windowDragMode = .sidePanel`
  - Escape handling guarded by `panel.isKeyWindow || panel.isMainWindow`

- [ ] **Step 1: Add the side-panel drag mode**

In `Sources/CodexPlusApp/DraggableHostingView.swift`, change the enum and drag decision methods to:

```swift
enum WindowDragMode {
    case automatic
    case compactPrompt
    case sidePanel
}

override var mouseDownCanMoveWindow: Bool {
    switch windowDragMode {
    case .automatic:
        return true
    case .compactPrompt, .sidePanel:
        return false
    }
}

private func shouldPerformManualWindowDrag(for event: NSEvent) -> Bool {
    switch windowDragMode {
    case .automatic:
        return false
    case .compactPrompt:
        return CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
            at: convert(event.locationInWindow, from: nil),
            panelBounds: bounds,
            verticalOrigin: isFlipped ? .top : .bottom
        )
    case .sidePanel:
        return true
    }
}
```

- [ ] **Step 2: Share the manual drag loop**

Rename `performCompactPromptDrag(from:)` to `performManualWindowDrag(from:)`, update `mouseDown(with:)` to call the new name, and rename `compactPromptDragResult(for:window:)` to `snappedDragResult(for:window:)`:

```swift
override func mouseDown(with event: NSEvent) {
    guard shouldPerformManualWindowDrag(for: event) else {
        super.mouseDown(with: event)
        return
    }

    performManualWindowDrag(from: event)
}
```

Inside the drag loop, replace:

```swift
let dragResult = compactPromptDragResult(for: proposedFrame, window: window)
```

with:

```swift
let dragResult = snappedDragResult(for: proposedFrame, window: window)
```

Keep the existing `CompactPanelSnapPolicy.snappedFrame(for:in:)` call unchanged inside the renamed helper.

- [ ] **Step 3: Install side-panel drag mode**

In `Sources/CodexPlusApp/SidePanelController.swift`, replace the direct content assignment in `installContent(in:model:actions:)` with a local variable:

```swift
let contentView = DraggableHostingView(
    rootView: ConversationPanelHostView(
        model: model,
        onSubmitDraft: actions.onSubmitDraft,
        onFollowUp: actions.onFollowUp,
        onStop: actions.onStop,
        onTogglePin: actions.onTogglePin,
        onToggleSide: actions.onToggleSide,
        onToggleFullAccess: actions.onToggleFullAccess,
        onSelectWorkspace: actions.onSelectWorkspace,
        onSelectConversation: actions.onSelectConversation,
        onNewDraft: actions.onNewDraft,
        onArchiveConversation: actions.onArchiveConversation,
        onPickWorkspace: actions.onPickWorkspace,
        onReorderWorkspace: actions.onReorderWorkspace,
        onReorderConversation: actions.onReorderConversation
    )
)
contentView.windowDragMode = .sidePanel
panel.contentView = contentView
```

- [ ] **Step 4: Gate Escape by current window**

In `SidePanelController.installDismissMonitorsIfNeeded()`, change the key monitor guard to bind the panel and require current-window status:

```swift
guard
    let panel = self.panel,
    panel.isVisible,
    panel.isKeyWindow || panel.isMainWindow,
    CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode: event.keyCode)
else {
    return event
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: PASS, with no failures reported by the test executable.

- [ ] **Step 6: Run build**

Run:

```bash
swift build
```

Expected: exit code 0.

- [ ] **Step 7: Commit tests and implementation**

```bash
git add Tests/CodexPlusCoreTests/main.swift Sources/CodexPlusApp/DraggableHostingView.swift Sources/CodexPlusApp/SidePanelController.swift
git commit -m "feat: snap main panel drag to midline"
```

### Task 3: Final Verification And Review

**Files:**
- Inspect: `git diff HEAD~1..HEAD`

**Interfaces:**
- Consumes: green implementation commit from Task 2.
- Produces: final evidence that the implementation matches the approved spec.

- [ ] **Step 1: Run full verification**

Run:

```bash
swift run CodexPlusCoreTests
swift build
```

Expected: both commands exit 0.

- [ ] **Step 2: Inspect final diff**

Run:

```bash
git diff HEAD~1..HEAD -- Sources/CodexPlusApp/DraggableHostingView.swift Sources/CodexPlusApp/SidePanelController.swift Tests/CodexPlusCoreTests/main.swift
```

Expected: diff only covers the side-panel drag mode, side-panel Escape guard, and regression checks.

- [ ] **Step 3: Confirm spec coverage**

Check these items manually against the diff:

```text
Side panel installs .sidePanel drag mode.
Manual drag uses CompactPanelSnapPolicy.snappedFrame(for:in:).
Side-panel Escape handling requires isKeyWindow or isMainWindow.
Compact prompt code still sets .compactPrompt.
No conversation, archive, pin, run cancellation, or affordance logic changed.
```
