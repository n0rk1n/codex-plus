# Codex Usage Background Refresh and Wide Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Codex usage refresh every two minutes in the background and widen its dashboard tile to a 1.5:1 ratio.

**Architecture:** Keep the existing provider and monitor threading model. Make the monitor default interval testable, start it from `WindowCoordinator` initialization instead of compact-panel presentation, and widen only the usage tile frame.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM executable test target.

---

### Task 1: Codex Usage Monitor Default Interval

**Files:**
- Modify: `Sources/QuickAIDashboardCore/CodexUsageMonitor.swift`
- Modify: `Tests/QuickAIDashboardCoreTests/main.swift`

- [ ] **Step 1: Write the failing test**

Add near the existing Codex usage monitor tests:

```swift
expect(
    CodexUsageMonitor.defaultRefreshInterval == 120,
    "codex usage monitor defaults to a two-minute refresh interval"
)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run QuickAIDashboardCoreTests`

Expected: compile failure because `defaultRefreshInterval` does not exist.

- [ ] **Step 3: Implement the constant and default**

In `CodexUsageMonitor`, add:

```swift
public static let defaultRefreshInterval: TimeInterval = 120
```

Then change the initializer default from:

```swift
interval: TimeInterval = 60
```

to:

```swift
interval: TimeInterval = CodexUsageMonitor.defaultRefreshInterval
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run QuickAIDashboardCoreTests`

Expected: `QuickAIDashboardCoreTests passed`.

### Task 2: Background Lifecycle

**Files:**
- Modify: `Sources/QuickAIDashboardApp/WindowCoordinator.swift`

- [ ] **Step 1: Start usage monitor during coordinator initialization**

After `super.init()` in `WindowCoordinator.init`, add:

```swift
codexUsageMonitor.start()
```

- [ ] **Step 2: Keep teardown owned by the monitor**

Do not call `codexUsageMonitor.stop()` from `WindowCoordinator.deinit`. `CodexUsageMonitor` already invalidates its timer in its own `deinit`, and Swift 6 does not allow calling the MainActor-isolated `stop()` from `WindowCoordinator.deinit`.

- [ ] **Step 3: Remove panel-scoped usage start**

Delete this line from `showCompactPanel()`:

```swift
codexUsageMonitor.start()
```

- [ ] **Step 4: Remove panel-scoped usage stop**

Delete this line from `dismissCompactPanel()`:

```swift
codexUsageMonitor.stop()
```

- [ ] **Step 5: Verify app build**

Run: `swift build`

Expected: build succeeds.

### Task 3: Wide Codex Usage Tile

**Files:**
- Modify: `Sources/QuickAIDashboardApp/Views/CodexUsageRingTileView.swift`

- [ ] **Step 1: Change fixed tile size**

Change:

```swift
.frame(width: 92, height: 92)
```

to:

```swift
.frame(width: 138, height: 92)
```

- [ ] **Step 2: Tighten metric row width**

Change the metric `HStack` spacing from:

```swift
HStack(spacing: 0)
```

to:

```swift
HStack(spacing: 10)
```

- [ ] **Step 3: Verify app build**

Run: `swift build`

Expected: build succeeds.

### Task 4: Verification and Commit

**Files:**
- Modify: `Sources/QuickAIDashboardCore/CodexUsageMonitor.swift`
- Modify: `Sources/QuickAIDashboardApp/WindowCoordinator.swift`
- Modify: `Sources/QuickAIDashboardApp/Views/CodexUsageRingTileView.swift`
- Modify: `Tests/QuickAIDashboardCoreTests/main.swift`

- [ ] **Step 1: Run full verification**

Run:

```bash
swift run QuickAIDashboardCoreTests
swift build
git diff --check
```

Expected: tests pass, build succeeds, diff check has no output.

- [ ] **Step 2: GUI smoke launch**

Run: `swift run QuickAIDashboardApp`

Expected: app launches without immediate crash. Stop the run after smoke verification.

- [ ] **Step 3: Commit**

```bash
git add Sources/QuickAIDashboardCore/CodexUsageMonitor.swift Sources/QuickAIDashboardApp/WindowCoordinator.swift Sources/QuickAIDashboardApp/Views/CodexUsageRingTileView.swift Tests/QuickAIDashboardCoreTests/main.swift
git commit -m "feat: refresh codex usage in background"
```
