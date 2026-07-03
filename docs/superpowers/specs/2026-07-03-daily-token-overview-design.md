# Daily Token Overview Design

Date: 2026-07-03

## Goal

Add a compact dashboard tile that summarizes today's Codex token activity. The tile shows total input tokens, total output tokens, and cache hit rate for the local day.

## Metrics

The data source is Codex session JSONL under `~/.codex/sessions` and `~/.codex/archived_sessions`. The provider reads `payload.type == "token_count"` events and sums `payload.info.last_token_usage` for events whose timestamp falls inside the user's current calendar day.

- Input total: sum of `input_tokens`.
- Output total: sum of `output_tokens`.
- Hit rate: `cached_input_tokens / input_tokens`, rounded to the nearest percent.

Using `last_token_usage` avoids double-counting the cumulative `total_token_usage` values emitted within a single session.

## Dashboard Design

Add a new `Daily Token` tile to the compact dashboard row. The tile uses the existing Liquid Glass style and the same 138 by 92 footprint as Codex Usage. It shows three compact metric columns:

- `IN` with compact count text such as `842K` or `1.2M`.
- `OUT` with compact count text.
- `HIT` with percentage text.

Unknown or empty data displays `--`.

## Refresh Behavior

The monitor refreshes immediately when started. After each refresh, it schedules the next refresh based on the latest total token volume:

- 30 seconds when input plus output is below 1,000,000.
- 60 seconds when input plus output is at or above 1,000,000.

This keeps low-volume days responsive while reducing repeated JSONL scans on heavy days.

## Architecture

Core adds a daily token status model, provider, and monitor. The provider reuses the same read-only JSONL scanning pattern as Codex usage. SwiftUI receives a published status from `WindowCoordinator` and renders the new tile from display-ready values.

Dashboard ordering remains persisted through `DashboardTileOrder`; invalid stored orders fall back to the new default order.

## Error Handling

Unreadable directories, malformed JSON lines, non-JSONL files, token events without usage info, and timestamps outside the current day are ignored. If no event contributes data, the status is unknown.

## Testing

Core tests cover display formatting, daily aggregation, archived session inclusion, invalid line handling, non-JSONL filtering, cache hit rate rounding, unknown state, dynamic refresh interval selection, and dashboard layout/order updates.
