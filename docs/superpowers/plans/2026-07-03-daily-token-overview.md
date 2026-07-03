# Daily Token Overview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a compact dashboard tile showing today's Codex input tokens, output tokens, and cache hit rate.

**Architecture:** Add a focused Core status/provider/monitor for daily token totals, then wire it through the existing compact dashboard path. Reuse the existing JSONL scanning style and Liquid Glass tile treatment.

**Tech Stack:** Swift 6, SwiftUI, Foundation JSONSerialization, SwiftPM executable tests.

## Global Constraints

- Work only in `/Users/oriki/Documents/codex-plus/.worktrees/daily-token-overview`.
- Read Codex session JSONL files only; do not modify user session files.
- Sum `last_token_usage` for events in the current local calendar day.
- Display large counts compactly, such as `1.2M`.
- Refresh every 30 seconds below 1,000,000 total daily tokens and every 60 seconds at or above 1,000,000.
- Add no new dependencies.

---

### Task 1: Core Daily Token Status And Provider

**Files:**
- Create: `Sources/CodexPlusCore/DailyTokenStatus.swift`
- Create: `Sources/CodexPlusCore/LocalDailyTokenUsageProvider.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Produces: `DailyTokenStatus(inputTokens: Int, outputTokens: Int, cachedInputTokens: Int, observedAt: Date?)`
- Produces: `DailyTokenUsageProviding.currentStatus() -> DailyTokenStatus`
- Produces: `LocalDailyTokenUsageProvider.currentStatus() -> DailyTokenStatus`

- [ ] **Step 1: Write failing tests for status display and JSONL aggregation**

Add tests that expect compact count strings, hit-rate percentage text, same-day filtering, malformed-line ignoring, and archived-session inclusion.

- [ ] **Step 2: Run the tests to verify RED**

Run: `swift run CodexPlusCoreTests`

Expected: FAIL because `DailyTokenStatus` and `LocalDailyTokenUsageProvider` do not exist.

- [ ] **Step 3: Implement minimal status and provider**

Create the status type, parse `payload.info.last_token_usage`, sum same-day events, and ignore unreadable or malformed data.

- [ ] **Step 4: Run the tests to verify GREEN**

Run: `swift run CodexPlusCoreTests`

Expected: PASS for the new daily token assertions.

### Task 2: Dynamic Monitor And Dashboard Model

**Files:**
- Create: `Sources/CodexPlusCore/DailyTokenUsageMonitor.swift`
- Modify: `Sources/CodexPlusCore/DashboardTileOrder.swift`
- Modify: `Sources/CodexPlusCore/DashboardTileLayoutPolicy.swift`
- Modify: `Sources/CodexPlusCore/CompactDashboardTileDragPolicy.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Produces: `DailyTokenUsageMonitor.defaultLowVolumeRefreshInterval == 30`
- Produces: `DailyTokenUsageMonitor.defaultHighVolumeRefreshInterval == 60`
- Produces: new dashboard tile case `.dailyTokens`

- [ ] **Step 1: Write failing tests for dynamic interval and dashboard layout**

Add tests expecting `.dailyTokens` in the default order, stable placement for three tiles, invalid persisted order fallback, and interval selection based on token totals.

- [ ] **Step 2: Run the tests to verify RED**

Run: `swift run CodexPlusCoreTests`

Expected: FAIL because the monitor and dashboard tile case do not exist.

- [ ] **Step 3: Implement minimal monitor and tile model changes**

Add the monitor, dashboard enum case, widths, strip width calculation, and persisted order validation.

- [ ] **Step 4: Run the tests to verify GREEN**

Run: `swift run CodexPlusCoreTests`

Expected: PASS for the new monitor and dashboard assertions.

### Task 3: SwiftUI Tile Integration

**Files:**
- Create: `Sources/CodexPlusApp/Views/DailyTokenTileView.swift`
- Modify: `Sources/CodexPlusApp/Views/CompactEntryHostView.swift`
- Modify: `Sources/CodexPlusApp/Views/CompactEntryView.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`

**Interfaces:**
- Consumes: `DailyTokenStatus`
- Consumes: `DailyTokenUsageMonitor`

- [ ] **Step 1: Implement the tile view**

Render `IN`, `OUT`, and `HIT` columns inside `LiquidGlassContainer`, using `DailyTokenStatus` display text.

- [ ] **Step 2: Wire the monitor through the compact entry**

Create `DailyTokenUsageMonitor` in `WindowCoordinator`, start it with the other monitors, pass its status through `CompactEntryHostView`, and render `.dailyTokens` in `CompactEntryView`.

- [ ] **Step 3: Verify build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Verify full tests**

Run: `swift run CodexPlusCoreTests`

Expected: PASS.
