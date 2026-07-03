# Codex Usage Metric Card Design

Date: 2026-07-03

## Goal

Replace the Codex usage double-ring tile with a simpler Liquid Glass metric card. The card should match the battery tile's compact dashboard style and show the two Codex quota windows side by side:

- Left: `5h`
- Right: `1w`
- Each side shows its usage percent below the label.

## Design

The top dashboard keeps two square tiles: battery first, Codex usage second. The Codex tile remains a single rounded square block with the existing glass background, border, and shadow treatment. Inside the tile, content is arranged as two equal columns separated by spacing, not a visible divider.

Each column contains a small uppercase window label and a larger percentage value. The percentage uses the existing Codex usage color scale: green below 60%, yellow around the middle of the warning range, and red near or at 100%. Unknown values display `--%` in the inactive color.

## Architecture

No data model changes are required. `CodexUsageStatus` continues to provide percentages and colors. The UI change stays inside the app view layer by replacing the ring composition in `CodexUsageRingTileView` with a metric-card composition. Keeping the existing file name avoids touching call sites for a visual-only change.

## Components

- `CodexUsageRingTileView`: becomes the square metric card container.
- A small private metric subview renders one window label and percent.
- Existing `CodexUsageStatus.ringColor(for:)` remains the color source, even though the UI no longer draws rings.

## Data Flow

`WindowCoordinator` still owns `CodexUsageMonitor`. `CompactEntryView` still receives the current `CodexUsageStatus` and passes it to the Codex usage tile. The tile reads `fiveHourPercent` and `weeklyPercent` through the existing status API.

## Error Handling

When usage data is missing, either side shows `--%` with inactive styling. The card remains visible so the dashboard layout does not jump.

## Testing

Core parsing and monitoring tests remain unchanged. Add focused view-logic coverage for the display values and colors if practical in the current SwiftPM test target; otherwise verify with `swift run CodexPlusCoreTests`, `swift build`, and a GUI smoke launch.
