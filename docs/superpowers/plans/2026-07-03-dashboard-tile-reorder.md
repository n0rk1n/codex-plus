# Dashboard Tile Reorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the Battery and Codex Usage dashboard tiles to be reordered by dragging, with the chosen order persisted across launches.

**Architecture:** Add a small core order model for parsing, validating, serializing, and swapping tile order. `CompactEntryView` stores the raw order string with `@AppStorage`, renders tiles from the model, and uses a horizontal drag gesture to swap the two tiles when the drag passes a threshold.

**Tech Stack:** Swift 6, SwiftUI, SwiftPM executable test target, `UserDefaults` via `@AppStorage`.

---

### Task 1: Core Tile Order Model

**Files:**
- Create: `Sources/QuickAIDashboardCore/DashboardTileOrder.swift`
- Modify: `Tests/QuickAIDashboardCoreTests/main.swift`

- [ ] **Step 1: Write failing tests**

Add near the existing model tests:

```swift
let defaultTileOrder = DashboardTileOrder(rawValue: nil)
expect(defaultTileOrder.tiles == [.battery, .codexUsage], "dashboard tile order defaults to battery then codex usage")
expect(defaultTileOrder.rawValue == "battery,codexUsage", "dashboard tile order serializes default order")

let reversedTileOrder = DashboardTileOrder(rawValue: "codexUsage,battery")
expect(reversedTileOrder.tiles == [.codexUsage, .battery], "dashboard tile order reads reversed persisted order")

let invalidTileOrder = DashboardTileOrder(rawValue: "battery,battery,unknown")
expect(invalidTileOrder.tiles == [.battery, .codexUsage], "dashboard tile order falls back when persisted order is invalid")

let swappedTileOrder = defaultTileOrder.swapping(.battery, with: .codexUsage)
expect(swappedTileOrder.tiles == [.codexUsage, .battery], "dashboard tile order swaps dragged and target tiles")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run QuickAIDashboardCoreTests`

Expected: compile failure because `DashboardTileOrder` and `DashboardTile` do not exist.

- [ ] **Step 3: Implement minimal model**

Create `DashboardTileOrder.swift`:

```swift
import Foundation

public enum DashboardTile: String, CaseIterable, Equatable, Sendable {
    case battery
    case codexUsage
}

public struct DashboardTileOrder: Equatable, Sendable {
    public static let defaultTiles: [DashboardTile] = [.battery, .codexUsage]

    public let tiles: [DashboardTile]

    public init(rawValue: String?) {
        guard let rawValue else {
            self.tiles = Self.defaultTiles
            return
        }

        let parsedTiles = rawValue
            .split(separator: ",")
            .compactMap { DashboardTile(rawValue: String($0)) }

        self.tiles = Self.validated(parsedTiles)
    }

    public init(tiles: [DashboardTile]) {
        self.tiles = Self.validated(tiles)
    }

    public var rawValue: String {
        tiles.map(\.rawValue).joined(separator: ",")
    }

    public func swapping(_ source: DashboardTile, with target: DashboardTile) -> DashboardTileOrder {
        guard source != target,
              let sourceIndex = tiles.firstIndex(of: source),
              let targetIndex = tiles.firstIndex(of: target)
        else {
            return self
        }

        var nextTiles = tiles
        nextTiles.swapAt(sourceIndex, targetIndex)
        return DashboardTileOrder(tiles: nextTiles)
    }

    private static func validated(_ tiles: [DashboardTile]) -> [DashboardTile] {
        guard tiles.count == defaultTiles.count,
              Set(tiles) == Set(defaultTiles)
        else {
            return defaultTiles
        }

        return tiles
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run QuickAIDashboardCoreTests`

Expected: `QuickAIDashboardCoreTests passed`.

### Task 2: Drag Gesture and Persistence

**Files:**
- Modify: `Sources/QuickAIDashboardApp/Views/CompactEntryView.swift`

- [ ] **Step 1: Add persistent order and drag state**

Add state to `CompactEntryView`:

```swift
@AppStorage("dashboard.tileOrder") private var dashboardTileOrderRaw = DashboardTileOrder(rawValue: nil).rawValue
@State private var draggedTile: DashboardTile?
@State private var dragTranslation: CGSize = .zero
```

Add helpers:

```swift
private var dashboardTileOrder: DashboardTileOrder {
    DashboardTileOrder(rawValue: dashboardTileOrderRaw)
}

private let reorderThreshold: CGFloat = 44
```

- [ ] **Step 2: Render tiles from the model**

Replace the static `HStack` tile content with:

```swift
HStack(spacing: 12) {
    ForEach(dashboardTileOrder.tiles, id: \.self) { tile in
        tileView(for: tile)
            .offset(x: draggedTile == tile ? dragTranslation.width : 0)
            .scaleEffect(draggedTile == tile ? 1.03 : 1)
            .opacity(draggedTile == tile ? 0.92 : 1)
            .zIndex(draggedTile == tile ? 1 : 0)
            .highPriorityGesture(dragGesture(for: tile))
    }
}
.animation(.snappy(duration: 0.18), value: dashboardTileOrderRaw)
```

- [ ] **Step 3: Add tile rendering helper**

```swift
@ViewBuilder
private func tileView(for tile: DashboardTile) -> some View {
    switch tile {
    case .battery:
        BatteryTileView(status: batteryStatus)
    case .codexUsage:
        CodexUsageRingTileView(status: codexUsageStatus)
    }
}
```

- [ ] **Step 4: Add drag gesture helper**

```swift
private func dragGesture(for tile: DashboardTile) -> some Gesture {
    DragGesture(minimumDistance: 8)
        .onChanged { value in
            draggedTile = tile
            dragTranslation = CGSize(width: value.translation.width, height: 0)
        }
        .onEnded { value in
            reorderIfNeeded(tile: tile, translationWidth: value.translation.width)
            draggedTile = nil
            dragTranslation = .zero
        }
}
```

- [ ] **Step 5: Add reorder helper**

```swift
private func reorderIfNeeded(tile: DashboardTile, translationWidth: CGFloat) {
    guard abs(translationWidth) >= reorderThreshold else {
        return
    }

    let order = dashboardTileOrder
    guard let tileIndex = order.tiles.firstIndex(of: tile) else {
        return
    }

    let targetIndex = translationWidth > 0 ? tileIndex + 1 : tileIndex - 1
    guard order.tiles.indices.contains(targetIndex) else {
        return
    }

    let nextOrder = order.swapping(tile, with: order.tiles[targetIndex])
    dashboardTileOrderRaw = nextOrder.rawValue
}
```

- [ ] **Step 6: Verify app build**

Run: `swift build`

Expected: build succeeds.

### Task 3: Verification and Commit

**Files:**
- Create: `Sources/QuickAIDashboardCore/DashboardTileOrder.swift`
- Modify: `Sources/QuickAIDashboardApp/Views/CompactEntryView.swift`
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
git add Sources/QuickAIDashboardCore/DashboardTileOrder.swift Sources/QuickAIDashboardApp/Views/CompactEntryView.swift Tests/QuickAIDashboardCoreTests/main.swift
git commit -m "feat: reorder dashboard tiles"
```
