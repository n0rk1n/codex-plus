# Native Liquid Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the app's custom `.ultraThinMaterial` glass treatment with SwiftUI's native macOS 26 Liquid Glass APIs.

**Architecture:** Keep `LiquidGlassContainer` as the app's shared glass abstraction and change its implementation to SwiftUI `glassEffect`. Raise the package minimum to macOS 26, wrap the compact dashboard row in `GlassEffectContainer`, and convert the side edge affordance from hand-rolled material to native glass.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit-backed macOS package, macOS 26 SDK.

## Global Constraints

- The project will intentionally require macOS 26 or newer.
- There is no compatibility fallback for macOS 14 or 15 in this change.
- Use SwiftUI native Liquid Glass as the primary implementation.
- Do not bridge SwiftUI content into AppKit `NSGlassEffectView`.
- Do not redesign tile layout, sizing, colors, copy, or conversation behavior.
- Do not rework buttons to `.buttonStyle(.glass)` in this pass.
- Preserve unrelated pre-existing checkout changes. In the isolated worktree, keep `CompactEntryView.swift` behavior unchanged except for the `GlassEffectContainer` wrapper.

---

## File Structure

- `Package.swift`: owns Swift package metadata and the macOS platform minimum.
- `Sources/CodexPlusApp/Views/LiquidGlassContainer.swift`: shared SwiftUI container for app glass panels and tiles.
- `Sources/CodexPlusApp/Views/CompactEntryView.swift`: compact dashboard row and prompt entry; will add only the `GlassEffectContainer` scope around dashboard tiles.
- `Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift`: collapsed side-panel affordance capsule; will use `glassEffect` directly.

---

### Task 1: Native Liquid Glass Surfaces

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/CodexPlusApp/Views/LiquidGlassContainer.swift`
- Modify: `Sources/CodexPlusApp/Views/CompactEntryView.swift`
- Modify: `Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift`

**Interfaces:**
- Consumes: existing `LiquidGlassContainer(cornerRadius:content:)` call sites.
- Produces: the same `LiquidGlassContainer<Content: View>` type and initializer, now backed by SwiftUI `glassEffect`.
- Produces: existing dashboard tile row wrapped in `GlassEffectContainer(spacing: nil)`.

- [ ] **Step 1: Verify the current custom material baseline**

Run:

```bash
rg -n "ultraThinMaterial|glassEffect|GlassEffectContainer|macOS\\(\\.v" Package.swift Sources/CodexPlusApp/Views
```

Expected before implementation:

```text
Package.swift:8:        .macOS(.v14)
Sources/CodexPlusApp/Views/LiquidGlassContainer.swift:19:                    .fill(.ultraThinMaterial)
Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift:9:                .fill(.ultraThinMaterial)
```

The exact line numbers may differ if the worktree has local edits, but the search must show `.macOS(.v14)` and `.ultraThinMaterial` in the two glass views before the change.

- [ ] **Step 2: Raise the package platform floor**

Change `Package.swift` platforms from:

```swift
    platforms: [
        .macOS(.v14)
    ],
```

to:

```swift
    platforms: [
        .macOS(.v26)
    ],
```

- [ ] **Step 3: Replace the shared glass container implementation**

Replace the `body` in `Sources/CodexPlusApp/Views/LiquidGlassContainer.swift` with:

```swift
    var body: some View {
        content
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
```

Keep the existing `LiquidGlassContainer` type, stored properties, and initializer unchanged.

- [ ] **Step 4: Wrap the compact dashboard row in `GlassEffectContainer`**

In `Sources/CodexPlusApp/Views/CompactEntryView.swift`, wrap the existing first `GeometryReader` block in `body` with `GlassEffectContainer`. The result should keep the row's existing tile iteration, offset calculation, gesture handling, and animation triggers:

```swift
            GlassEffectContainer {
                GeometryReader { geometry in
                    ZStack {
                        ForEach(dashboardTileOrder.tiles, id: \.self) { tile in
                            tileView(for: tile)
                                .position(
                                    x: (geometry.size.width / 2) + tileOffset(for: tile),
                                    y: tileRowHeight / 2
                                )
                                .scaleEffect(draggedTile == tile ? 1.03 : 1)
                                .opacity(draggedTile == tile ? 0.92 : 1)
                                .zIndex(draggedTile == tile ? 1 : 0)
                                .contentShape(Rectangle())
                        }
                    }
                    .contentShape(Rectangle())
                    .highPriorityGesture(rowDragGesture(rowWidth: geometry.size.width))
                }
                .frame(height: tileRowHeight)
                .animation(.snappy(duration: 0.18), value: draggedTile)
                .animation(.snappy(duration: 0.18), value: dashboardTileOrderRaw)
            }
```

Do not add placeholder views, preview-order helpers, tile sizing changes, tile ordering changes, drag threshold changes, or prompt-entry layout changes.

- [ ] **Step 5: Convert the side edge affordance capsule**

Replace the button label in `Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift` with:

```swift
            Capsule(style: .continuous)
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                .padding(2)
```

Keep `.buttonStyle(.plain)`, `.help("Show Conversation")`, and `.accessibilityLabel("Show Conversation")` unchanged.

- [ ] **Step 6: Verify source no longer uses the old material treatment**

Run:

```bash
rg -n "ultraThinMaterial|glassEffect|GlassEffectContainer|macOS\\(\\.v" Package.swift Sources/CodexPlusApp/Views
```

Expected after implementation:

```text
Package.swift:8:        .macOS(.v26)
Sources/CodexPlusApp/Views/LiquidGlassContainer.swift:
Sources/CodexPlusApp/Views/CompactEntryView.swift:
Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift:
```

The output for those three files must include `.glassEffect(` for `LiquidGlassContainer.swift`, `GlassEffectContainer {` for `CompactEntryView.swift`, and `.glassEffect(` for `SideEdgeAffordanceView.swift`. There must be no `.ultraThinMaterial` matches in `Sources/CodexPlusApp/Views`.

- [ ] **Step 7: Build with the macOS 26 SDK**

Run:

```bash
swift build
```

Expected: build succeeds. If SwiftPM rejects `.v26`, use the spelling supported by this SDK's `PackageDescription.Platform.MacOSVersion` and rerun `swift build`.

- [ ] **Step 8: Run the existing core test executable**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: all existing tests pass. These tests do not validate visual rendering, but they catch regressions in dashboard ordering and drag behavior.

- [ ] **Step 9: Check the implementation diff for unrelated changes**

Run:

```bash
git diff -- Package.swift Sources/CodexPlusApp/Views/LiquidGlassContainer.swift Sources/CodexPlusApp/Views/CompactEntryView.swift Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift
```

Expected: the diff only contains the platform floor change and the Liquid Glass API replacements described above. In `CompactEntryView.swift`, the diff must only wrap the existing dashboard `GeometryReader` in `GlassEffectContainer`.

- [ ] **Step 10: Commit only this task's hunks if requested**

If committing, stage only this task's changes. In a clean file this is safe:

```bash
git add Package.swift Sources/CodexPlusApp/Views/LiquidGlassContainer.swift Sources/CodexPlusApp/Views/SideEdgeAffordanceView.swift
```

For `Sources/CodexPlusApp/Views/CompactEntryView.swift`, inspect the diff first and stage only the `GlassEffectContainer` hunk. If unrelated edits are mixed into the same hunk, skip committing and report the exact reason.

Use this commit message:

```bash
git commit -m "feat: use native liquid glass"
```

---

## Manual Visual Check

If running the GUI is available, launch the app after `swift build` and confirm:

- The compact dashboard tiles render with native glass.
- The prompt entry renders with native glass.
- Conversation header, body, footer, and draft surfaces remain readable.
- The side edge affordance appears as a native glass capsule and still activates the side panel.
