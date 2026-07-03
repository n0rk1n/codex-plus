# Codex Usage Background Refresh and Wide Card Design

Date: 2026-07-03

## Goal

Codex usage should refresh in the app background every two minutes instead of starting only when the compact entry panel appears. The Codex usage tile should also become wider, with a 1.5:1 width-to-height ratio.

## Design

The app starts the Codex usage monitor during `WindowCoordinator` initialization. The compact panel no longer controls that monitor's lifetime, so hiding the compact panel does not stop usage refresh. The battery monitor keeps its existing panel-scoped behavior because this request only changes Codex usage.

The Codex usage monitor uses a default interval of 120 seconds. It should still refresh immediately when started, then continue on the repeating timer. Calling `start()` remains idempotent.

The Codex usage tile keeps its Liquid Glass treatment and text layout, but changes from `92 x 92` to `138 x 92`. This produces the requested 1.5:1 ratio while preserving the current dashboard height and alignment with the battery tile.

## Architecture

- `CodexUsageMonitor` owns the default background interval as a testable constant.
- `WindowCoordinator` starts `codexUsageMonitor` once during initialization and stops it only during coordinator teardown.
- `dismissCompactPanel()` no longer stops `codexUsageMonitor`.
- `CodexUsageRingTileView` changes only its fixed frame and internal horizontal spacing.

## Error Handling

If usage data is unavailable, the tile continues to show the existing `--%` values and inactive colors. Background refresh failure behavior remains unchanged because `LocalCodexUsageProvider` already returns `.unknown` when it cannot find usable data.

## Testing

Add core coverage for the 120-second default interval. Verify the app target with `swift build`, run the existing core tests, and smoke-launch the app after the UI change.
