# Dashboard Tile Reorder Design

Date: 2026-07-03

## Goal

Let the top dashboard tiles be reordered by dragging. The current dashboard has two tiles: Battery and Codex Usage. Dragging one tile horizontally toward the other should swap their positions, and the chosen order should persist across app launches.

## Design

The top row remains a compact horizontal dashboard. Each tile can be dragged along the x-axis. While dragging, the active tile follows the pointer slightly and lifts visually using scale and opacity. When the drag ends past a small horizontal threshold toward the other tile, the order swaps. If the drag is too short, the tile snaps back.

The persisted order lives in `UserDefaults` as a compact string. The default order is Battery first, Codex Usage second. Invalid stored values fall back to the default order.

## Architecture

Core owns the order model so parsing, sanitizing, and swapping are testable without SwiftUI. The app view owns presentation state: the currently dragged tile and drag offset. `CompactEntryView` reads and writes the persisted order with `@AppStorage`, converts it through the core model, and renders tiles in that order.

## Components

- `DashboardTile`: identifies `battery` and `codexUsage`.
- `DashboardTileOrder`: parses persisted strings, enforces valid unique tile order, serializes order, and swaps tiles.
- `CompactEntryView`: renders the ordered tile list and applies the drag gesture to each tile.

## Error Handling

If `UserDefaults` contains an unknown, duplicate, or incomplete order, `DashboardTileOrder` uses the default order. The user can still drag to save a new valid order.

## Testing

Add core tests for default parsing, reversed parsing, invalid fallback, and swapping. Verify the app target with `swift build`, run the core tests, and smoke-launch the app.
