# Codex Usage Metric Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Codex usage double-ring dashboard tile with one Liquid Glass metric card that shows `5h` and `1w` percentages side by side.

**Architecture:** Keep the existing usage monitor and status provider unchanged. Add a small display helper to `CodexUsageStatus` so the UI does not format optional percentages itself, then replace the SwiftUI ring layout with two metric columns inside the existing tile container.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM executable test target.

---

### Task 1: Core Display Text

**Files:**
- Modify: `Sources/CodexPlusCore/CodexUsageStatus.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Write the failing test**

Add assertions near the existing Codex usage status tests:

```swift
expect(greenCodexUsage.displayPercentText(for: .fiveHour) == "42%", "codex usage display text shows known five-hour percent")
expect(unknownCodexUsage.displayPercentText(for: .weekly) == "--%", "codex usage display text shows placeholder for missing percent")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run CodexPlusCoreTests`

Expected: compile failure because `displayPercentText(for:)` does not exist.

- [ ] **Step 3: Add minimal implementation**

Add to `CodexUsageStatus`:

```swift
public func displayPercentText(for window: CodexUsageWindow) -> String {
    guard let percent = percent(for: window) else {
        return "--%"
    }

    return "\(percent)%"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run CodexPlusCoreTests`

Expected: `CodexPlusCoreTests passed`.

### Task 2: SwiftUI Metric Card

**Files:**
- Modify: `Sources/CodexPlusApp/Views/CodexUsageRingTileView.swift`

- [ ] **Step 1: Replace ring layout with two columns**

Use this structure inside the existing `LiquidGlassContainer`:

```swift
VStack(spacing: 7) {
    HStack(spacing: 0) {
        UsageMetricColumn(label: "5h", value: status.displayPercentText(for: .fiveHour), color: color(for: .fiveHour))
        UsageMetricColumn(label: "1w", value: status.displayPercentText(for: .weekly), color: color(for: .weekly))
    }

    Text(labelText)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
}
.frame(width: 92, height: 92)
```

- [ ] **Step 2: Add private metric column view**

```swift
private struct UsageMetricColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
    }
}
```

- [ ] **Step 3: Remove unused ring code**

Delete the private `UsageRing` view and the old local `percentText(_:)` helper from `CodexUsageRingTileView.swift`.

- [ ] **Step 4: Verify app build**

Run: `swift build`

Expected: build succeeds.

### Task 3: Verification and Commit

**Files:**
- Modify: `Sources/CodexPlusCore/CodexUsageStatus.swift`
- Modify: `Sources/CodexPlusApp/Views/CodexUsageRingTileView.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Run full verification**

Run:

```bash
swift run CodexPlusCoreTests
swift build
git diff --check
```

Expected: tests pass, build succeeds, diff check has no output.

- [ ] **Step 2: GUI smoke launch**

Run: `swift run CodexPlusApp`

Expected: app launches without immediate crash. Stop the run after smoke verification.

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexPlusCore/CodexUsageStatus.swift Sources/CodexPlusApp/Views/CodexUsageRingTileView.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: simplify codex usage tile"
```
