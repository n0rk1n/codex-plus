# Codex Usage Rings Design

## Goal

Add a compact Codex usage dashboard item above the quick AI input. The item should show the current Codex 5-hour and 1-week usage progress from Codex's own local usage records.

## Data Source

The app will read the latest `token_count` event from Codex session JSONL files under:

- `~/.codex/sessions`
- `~/.codex/archived_sessions`

The usage values come from `payload.rate_limits`:

- `primary.used_percent` with `window_minutes == 300` represents the 5-hour usage window.
- `secondary.used_percent` with `window_minutes == 10080` represents the 1-week usage window.

The app only reads these files. It must not write to, move, delete, or rewrite Codex session files.

## Dashboard Design

Replace the earlier two separate usage tile idea with one Liquid Glass square tile:

- Outer large ring: 5-hour usage.
- Inner smaller ring: 1-week usage.
- Center text: stacked percentages, with `5H` larger on top and `1W` smaller below.
- Secondary label: `Codex`.

The existing battery tile remains in the top dashboard row. The new Codex usage tile sits beside it with the same square footprint and liquid glass treatment.

## Color Rules

Each ring is colored from its own usage percentage:

- Below 60%: green.
- 60% to 100%: interpolate from green toward yellow near the middle of the range, then toward red as it approaches 100%.
- At or above 100%: red.
- Missing data: secondary gray with `--%`.

The color transition should be deterministic and testable in Core. UI code should consume a resolved display model rather than duplicate color thresholds.

## Refresh Behavior

The usage monitor refreshes when the compact entry appears and then every 60 seconds while the compact entry is active. It should avoid expensive repeated full scans where practical by choosing the newest relevant session files first.

## Empty And Error States

If no usable Codex usage event is found, the tile displays:

- Center: `5H --%` and `1W --%`
- Label: `No Data`
- Rings: gray inactive strokes

Malformed JSONL lines are ignored. A single bad file must not break the tile.

## Architecture

Core adds:

- `CodexUsageStatus`: 5-hour and 1-week percentages plus freshness metadata.
- `CodexUsageProvider`: protocol for reading usage.
- `LocalCodexUsageProvider`: reads Codex session JSONL files and extracts the newest rate limit event.
- `CodexUsageMonitor`: ObservableObject timer wrapper, matching the existing battery monitor pattern.

App adds:

- `CodexUsageRingTileView`: renders the double ring with Liquid Glass.
- `CompactEntryHostView` passes both battery status and Codex usage status into `CompactEntryView`.

## Testing

Core tests should cover:

- Extracting primary and secondary usage percentages from a token count event.
- Selecting the newest valid usage event across multiple files.
- Ignoring malformed JSONL lines.
- Returning unknown status when no usage data exists.
- Color band calculation for green, yellow-range, red, and missing data.

SwiftUI rendering is verified by build and manual smoke testing because the app does not currently have UI snapshot tests.
