# Codex+ Mac Dashboard MVP Design

Date: 2026-07-02

## Summary

Build a native macOS utility that provides a fast global AI entry point with a small Liquid Glass dashboard. The first version is intentionally narrow: one battery tile above an AI input box. Submitting text expands the compact entry into a side conversation window powered by Codex CLI.

The product direction is a personal Mac operations cockpit, but this MVP focuses only on the interaction core: summon quickly, see a tiny status signal, type into AI, expand into a side conversation, and control the current task safely.

## Product Decisions

### Approved Direction

- Native macOS app using SwiftUI/AppKit.
- Default global shortcut: Control-Option-Space.
- Liquid Glass visual style: transparent, blurred, lightly bordered, readable over desktop content.
- Two-layer quick entry:
  - Top layer: square dashboard icon tiles.
  - Bottom layer: AI conversation input.
- The first dashboard tile shows battery percentage and charging state.
- Pressing Enter in the AI input expands the entry into a side conversation window.
- The side conversation window can attach to the left or right screen edge.
- Moving the cursor away hides the side window.
- The side window remains the same active conversation until the user closes it or starts a new task by shortcut according to the session rules.
- AI integration starts with `codex exec --json`.
- Default execution mode is semi-automatic.
- A single conversation can be switched to Full Access, similar to Codex, and this mode resets when that conversation ends, fails, stops, or closes.
- Default expanded side: right edge of the active screen.

### Explicitly Out Of Scope For MVP

- System toggles.
- Development environment management.
- Homebrew package or service management.
- Maintenance diagnostics.
- Full overview dashboard.
- Persistent history.
- Markdown audit export.
- SQLite search or conversation recovery.
- Multi-dashboard tiles beyond the battery tile.
- Deep Codex SDK or app-server integration.

These items remain future expansion areas, not MVP requirements.

## References And Market Notes

The design borrows selectively from existing Mac tools:

- Cork: Homebrew-focused status and operations console.
- Applite: lightweight Mac app installation/update experience.
- OnyX and TinkerTool: dense, careful, reversible macOS system controls.
- Raycast AI: fast global AI entry and command-oriented workflow.

The MVP should not copy any of these products directly. Its first useful identity is a translucent, fast, personal AI surface for Codex-backed tasks.

## User Experience

### Quick Entry

The global shortcut opens a compact floating panel. The panel has two vertical sections:

1. Dashboard strip:
   - Contains square icon tiles.
   - MVP contains one tile: Battery.
   - The tile shows battery percentage and charging state.
   - The tile should be visually tappable but does not need an expanded detail view in MVP.

2. AI input:
   - Default keyboard focus lands in the input box.
   - The input uses a translucent Liquid Glass container.
   - Pressing Enter submits the prompt.
   - Empty submissions do nothing.

The compact panel should feel like a small system overlay, not a full app window.
It opens centered horizontally near the upper third of the active screen.

### Conversation Expansion

After a non-empty prompt is submitted:

- The compact panel expands into a side conversation window.
- The prompt becomes the first user message in the conversation.
- The app starts a Codex task through `codex exec --json`.
- JSONL events stream into the conversation body.
- The final Codex message is shown when the task completes.

The expanded window keeps the Liquid Glass style. It needs enough contrast for text, progress state, and controls to remain readable over varied wallpapers and app content.

### Side Window Behavior

- The side window can attach to the left or right edge of the active screen.
- The app remembers the last chosen side during the current app session.
- When the cursor leaves the side window area, the window hides.
- Hidden side windows leave a slim edge affordance so the user can rediscover them.
- If a task is running, hiding the window does not stop the task.
- The user can pin the side window so it stays visible.
- The user can close the side window, which ends the active conversation UI. If a task is running, closing asks whether to stop the task.

### Shortcut Session Rule

The global shortcut uses a smart default:

- If a conversation is running, pinned, or explicitly kept, the shortcut recalls that conversation.
- Otherwise, the shortcut opens a fresh compact quick entry for a new task.

This preserves fast new-task entry while avoiding accidental interruption of active Codex work.

## UI Specification

### Compact Panel

- Visual language: Liquid Glass, transparent blur, subtle highlight, thin border.
- Layout: exactly two vertical layers.
- Top layer: square tile grid or row. MVP has one square Battery tile.
- Bottom layer: AI input box.
- No sidebar, no dense settings, no visible feature explanations.
- The input box is the main interaction target and receives focus immediately.

### Battery Tile

The tile displays:

- Battery percentage.
- Charging, discharging, full, or unknown state.
- A compact battery icon.

If battery data is unavailable, show an unknown state without blocking the AI input.

### Conversation Window

Header controls:

- Permission mode selector or indicator.
- Running/completed/failed/stopped state.
- Pin/unpin.
- Stop button while a task is running.
- Close button.

Body:

- User prompt.
- Streamed Codex progress events.
- Command or tool events summarized in readable rows.
- Final assistant answer.
- Error state when execution fails.

Footer:

- Follow-up input for the same conversation.
- Enter submits the follow-up.

## Architecture

### Main App Layer

Responsibilities:

- Menu bar presence or background app lifecycle.
- Global keyboard shortcut registration.
- Compact panel window.
- Side conversation window.
- Liquid Glass visual treatment.
- Battery tile rendering.
- Conversation UI state.

SwiftUI can own most view composition. AppKit should be used where SwiftUI alone is awkward, especially global shortcut handling, borderless translucent panels, non-activating windows, side attachment, and hover-based hide behavior.

### Battery Status Service

Responsibilities:

- Read battery percentage.
- Read charging state.
- Publish updates to the UI.
- Return an unknown state when data is unavailable.

Implementation should use macOS native power APIs rather than shelling out.

### Conversation Coordinator

Responsibilities:

- Create in-memory conversation sessions.
- Apply shortcut session rules.
- Expand compact panel into side window.
- Track running, completed, failed, and stopped states.
- Reset per-conversation Full Access after terminal states.

MVP conversations are in memory only. App restart loses conversation state.

### Codex Runner

Responsibilities:

- Locate the `codex` executable.
- Start `codex exec --json` with the user's prompt.
- Read stdout JSONL events.
- Read stderr for diagnostics.
- Map Codex events to UI events.
- Stop the child process when requested.
- Surface structured failures.

The runner should treat JSONL parsing as best effort. If a line cannot be parsed, it should be displayed as raw text with an event parsing warning.

In semi-automatic mode, the runner should start Codex in read-only sandbox mode. If a task needs broader access, the app asks the user to switch that conversation to Full Access before starting or continuing the run. In Full Access mode, the runner may pass explicit full-access Codex flags for that run only.

### Permission Controller

Responsibilities:

- Default to semi-automatic mode.
- Allow one conversation to switch to Full Access.
- Make Full Access visible in the header.
- Reset Full Access when the conversation ends, fails, stops, or closes.

MVP should not persist permission mode across app restarts.
Full Access UI copy should read: "Full Access for this conversation. Codex can make broader local changes until this task ends or you stop it."

## Data Flow

### Quick Entry Open

1. User presses global shortcut.
2. App evaluates the shortcut session rule.
3. If a running, pinned, or kept conversation exists, show that side window.
4. Otherwise, show compact quick entry.
5. Battery service updates the battery tile.
6. AI input receives focus.

### Prompt Submission

1. User types a prompt.
2. User presses Enter.
3. App ignores empty input.
4. App creates an in-memory conversation.
5. Compact panel expands into the side window.
6. Codex Runner starts `codex exec --json`.
7. JSONL events update the conversation body.
8. Completion, failure, or stop transitions the conversation to a terminal state.
9. Permission Controller restores semi-automatic mode.

## Error Handling

- Battery read fails: show unknown battery state and keep AI input usable.
- `codex` is missing: show a clear missing-Codex message in the conversation window and allow retry after installation.
- Codex exits non-zero: show stderr summary and preserve the submitted prompt for retry.
- JSONL line cannot parse: show raw line fragment and mark the event as an event parsing warning.
- User stops task: terminate the Codex process, mark conversation as stopped, and restore semi-automatic mode.
- Full Access task ends, fails, stops, or closes: restore semi-automatic mode.
- Closing a running conversation: ask whether to stop the running Codex process.

## Testing And Verification

### Unit Tests

- Battery status mapping: percentage, charging state, full state, unknown state.
- Shortcut session rule:
  - Running conversation is recalled.
  - Pinned conversation is recalled.
  - Kept conversation is recalled.
  - Otherwise a fresh compact entry opens.
- Conversation state transitions:
  - Idle to running.
  - Running to completed.
  - Running to failed.
  - Running to stopped.
  - Terminal states reset Full Access.
- Codex JSONL parser:
  - Parses thread and turn events.
  - Parses agent message events.
  - Handles malformed lines without crashing.
- Stop behavior terminates the child process abstraction.

### UI Verification

- Compact panel has exactly two visible layers.
- Battery tile is square and stable.
- Input box receives focus immediately.
- Empty Enter does not create a conversation.
- Non-empty Enter expands to side conversation.
- Side window attaches left and right.
- Mouse-out hide works.
- Pin prevents hide.
- Text remains readable over light and dark desktop backgrounds.

### Manual Smoke Test

1. Launch the app.
2. Press the global shortcut.
3. Confirm compact Liquid Glass panel appears.
4. Confirm battery tile shows a state or unknown.
5. Confirm AI input is focused.
6. Submit a simple prompt.
7. Confirm side conversation opens.
8. Confirm Codex progress streams or a clear missing-Codex error appears.
9. Stop a running task and confirm state becomes stopped.
10. Switch to Full Access for one conversation and confirm it resets after termination.

## Future Expansion

After the MVP works well, add modules incrementally:

- More dashboard tiles: network, proxy, Codex usage, Homebrew services.
- Persistent local history.
- Markdown audit export.
- System toggles with reversible actions.
- Development environment checks.
- Homebrew management.
- Maintenance diagnostics.
- Deeper Codex SDK or app-server integration for richer streamed control.

## Fixed MVP Defaults

- Global shortcut: Control-Option-Space.
- Compact panel position: centered horizontally near the upper third of the active screen.
- Expanded side: right edge first, with a control to switch left.
- Permission default: semi-automatic/read-only Codex run.
- Full Access warning copy: "Full Access for this conversation. Codex can make broader local changes until this task ends or you stop it."
