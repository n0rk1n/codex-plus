# Button Hit Area Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared hit-area abstraction for Codex Plus self-drawn SwiftUI buttons and apply it to existing custom plain buttons.

**Architecture:** Create a focused app-layer SwiftUI helper that wraps `contentShape` behind semantic modifiers for circle, capsule, rectangle, and rounded rectangle hit targets. Apply those modifiers only to app-owned custom `.buttonStyle(.plain)` buttons, preserving system controls and existing visual styling.

**Tech Stack:** Swift, SwiftUI, Swift Package Manager, XCTest source guardrail tests.

---

## File Structure

- Create `Sources/CodexPlusApp/Views/ButtonHitAreaModifier.swift` for shared hit-area modifiers.
- Modify SwiftUI view files under `Sources/CodexPlusApp` that define app-owned custom plain buttons.
- Modify `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift` to guard key prompt-template manager call sites.
- Modify `Tests/CodexPlusCoreTests/LegacyMainTests.swift` or add a nearby source-level test file if broader view-source guardrails fit better.

### Task 1: Add Shared Hit-Area Modifiers

**Files:**
- Create: `Sources/CodexPlusApp/Views/ButtonHitAreaModifier.swift`
- Test: `Tests/CodexPlusCoreTests/PromptTemplateManagerAppSourceTests.swift`

- [ ] **Step 1: Write the failing source guardrail test**

Add an assertion that `PromptTemplateManagerView.swift` contains the shared modifier name for capsule action buttons:

```swift
XCTAssertTrue(
    managerView.contains(".codexCapsuleButtonHitArea()"),
    "Prompt template manager action buttons should use the shared capsule hit-area modifier."
)
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `swift test --filter PromptTemplateManagerAppSourceTests`

Expected: FAIL because `.codexCapsuleButtonHitArea()` does not exist in the source yet.

- [ ] **Step 3: Add the shared modifier file**

Create:

```swift
import SwiftUI

private struct CodexButtonHitAreaModifier<HitShape: Shape>: ViewModifier {
    let shape: HitShape

    func body(content: Content) -> some View {
        content.contentShape(shape)
    }
}

extension View {
    func codexRectangleButtonHitArea() -> some View {
        modifier(CodexButtonHitAreaModifier(shape: Rectangle()))
    }

    func codexCapsuleButtonHitArea() -> some View {
        modifier(CodexButtonHitAreaModifier(shape: Capsule(style: .continuous)))
    }

    func codexCircularButtonHitArea() -> some View {
        modifier(CodexButtonHitAreaModifier(shape: Circle()))
    }

    func codexRoundedButtonHitArea(cornerRadius: CGFloat) -> some View {
        modifier(
            CodexButtonHitAreaModifier(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        )
    }
}
```

- [ ] **Step 4: Apply one capsule call site minimally**

In `PromptTemplateManagerView.swift`, add `.codexCapsuleButtonHitArea()` to `headerActionLabel(...)` and `footerActionLabel(...)` after their padding/glass visual shape is applied.

- [ ] **Step 5: Run the focused test to verify it passes**

Run: `swift test --filter PromptTemplateManagerAppSourceTests`

Expected: PASS.

### Task 2: Apply Modifiers Across Custom Plain Buttons

**Files:**
- Modify: `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/ArchivedConversationView.swift`
- Modify: `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`
- Modify: `Sources/CodexPlusApp/Views/CodexDesktopTileView.swift`
- Modify: other `Sources/CodexPlusApp` files with custom `.buttonStyle(.plain)` buttons where the visual control is app-owned.

- [ ] **Step 1: Replace ad hoc shapes with shared modifiers**

Use these mappings:

```swift
.contentShape(Circle())
// becomes
.codexCircularButtonHitArea()

.contentShape(Capsule(style: .continuous))
// becomes
.codexCapsuleButtonHitArea()

.contentShape(Rectangle())
// becomes
.codexRectangleButtonHitArea()

.contentShape(RoundedRectangle(cornerRadius: WorkbenchMetrics.projectCardCornerRadius, style: .continuous))
// becomes
.codexRoundedButtonHitArea(cornerRadius: WorkbenchMetrics.projectCardCornerRadius)
```

- [ ] **Step 2: Add missing hit areas to visual buttons**

For custom plain buttons without an existing shape, add the modifier that matches the visible surface:

```swift
.buttonStyle(.plain)
.codexCapsuleButtonHitArea()
```

or:

```swift
.buttonStyle(.plain)
.codexCircularButtonHitArea()
```

or:

```swift
.buttonStyle(.plain)
.codexRoundedButtonHitArea(cornerRadius: 22)
```

- [ ] **Step 3: Keep system controls unchanged**

Do not add these modifiers to:

```swift
.menuStyle(.borderlessButton)
.pickerStyle(...)
.toggleStyle(.button)
.alert(...)
Button("取消", role: .cancel)
Button("删除", role: .destructive)
```

- [ ] **Step 4: Run source search to inspect remaining custom buttons**

Run: `rg -n "Button\\(|\\.buttonStyle\\(\\.plain\\)|contentShape" Sources/CodexPlusApp`

Expected: every app-owned custom plain button either uses a shared `codex...ButtonHitArea` modifier or is intentionally excluded because it is a system control or nested menu.

### Task 3: Verify Build and Regression Coverage

**Files:**
- Modify tests only if Task 2 identifies a better source guardrail location.

- [ ] **Step 1: Run focused source guardrail tests**

Run: `swift test --filter PromptTemplateManagerAppSourceTests`

Expected: PASS.

- [ ] **Step 2: Run the full package test suite**

Run: `swift test`

Expected: PASS.

- [ ] **Step 3: Inspect final diff**

Run: `git diff -- Sources/CodexPlusApp Tests docs/superpowers/specs/2026-07-08-button-hit-area-design.md docs/superpowers/plans/2026-07-08-button-hit-area.md`

Expected: diff only contains the shared modifier, targeted view updates, focused tests, and the two docs.

## Self-Review

- Spec coverage: the plan creates a shared app-layer helper, applies it to custom plain buttons, avoids system controls, and verifies with source guardrails plus package tests.
- Placeholder scan: no unresolved placeholder markers or deferred implementation notes remain.
- Type consistency: modifier names are consistent across the plan: `codexRectangleButtonHitArea`, `codexCapsuleButtonHitArea`, `codexCircularButtonHitArea`, and `codexRoundedButtonHitArea(cornerRadius:)`.
