# Codex+ Enhancement Target Design

Date: 2026-07-03

## Summary

Codex+ should evolve from a compact Codex entry panel into a native macOS enhancement layer for Codex. Its main value is not a larger menu tree by itself, but a desktop workflow surface that makes Codex faster to start, easier to monitor, safer to authorize, richer in context, and cleaner to finish.

The target product identity is a personal AI workbench for Mac: a global shortcut opens the current task surface, top-level menus expose repeatable Codex workflows, dashboard tiles show useful local state, and the side conversation panel carries the task from prompt to completion.

## Product Thesis

Codex already provides the reasoning and execution engine. Codex+ should provide the surrounding operating layer:

- Fast entry for common actions.
- Project and system awareness before a task starts.
- Clear task state while Codex runs.
- Safer permission decisions.
- Reusable summaries and handoff artifacts when work finishes.

The menu system should act as an information architecture for these workflows. It should not become a decorative list of features that still require the user to manually compose prompts every time.

## Current Baseline

The app already has:

- A global shortcut that opens a compact Liquid Glass entry panel.
- A top dashboard tile row with Battery and Codex Usage.
- User-reorderable dashboard tiles.
- A side conversation window powered by `codex exec --json`.
- Conversation states for idle, running, completed, failed, and stopped.
- Semi-Automatic and Full Access permission modes.
- Pin, stop, close, side-toggle, follow-up, and edge affordance behavior.

Future work should build on these surfaces rather than introduce a separate full dashboard app too early.

## Target Capabilities

### 1. Task Entry Center

Codex+ should expose repeatable Codex actions through a small set of first-level categories:

- Ask
- Fix
- Review
- Explain
- Commit
- Ship
- Archive

Each first-level category can contain second-level actions:

- Ask: Ask Codex, Ask with current project, Ask with selected files.
- Fix: Fix current error, fix failing tests, fix selected issue.
- Review: Review git diff, review selected files, review current branch.
- Explain: Explain selected text, explain current file, explain recent output.
- Commit: Generate commit message, stage summary, prepare commit checklist.
- Ship: Write PR description, prepare release notes, summarize verification.
- Archive: Summarize current thread, extract lessons learned, create archive note.

Pain point solved: users should not need to repeatedly rebuild the same prompt shape, describe the same context, or remember the right Codex invocation pattern.

### 2. Project-Aware Dashboard

The compact dashboard should grow into a set of glanceable tiles that answer "what context will Codex operate in?"

Candidate tiles:

- Battery status.
- Codex usage status.
- Current project or working directory.
- Git branch and dirty state.
- Last Codex task result.
- Recent test status.
- Active task count.
- Permission mode for the current conversation.

Pain point solved: Codex tasks are risky when the user cannot quickly see which project, branch, state, or quota context they are about to use.

### 3. Task And Conversation Control

The side panel should become a lightweight task control surface:

- Show running, completed, failed, and stopped tasks.
- Recall recent tasks.
- Resume or follow up on the latest task.
- Pin important conversations.
- Copy final answers or summaries.
- Keep a small local history without trying to become a full database product immediately.

Pain point solved: long Codex tasks are easy to lose once the panel closes or another prompt starts. Users need a task lifecycle, not only a chat transcript.

### 4. Context Tray

Codex+ should help users attach relevant local context before a run:

- Current clipboard text.
- Selected text.
- Selected files.
- Current git diff.
- Recent terminal error output.
- Current working directory.
- Optional screenshot or screen region later.

The context tray should make the selected context visible before submission, so users know what Codex will see.

Pain point solved: most prompt friction comes from explaining "what just happened" and "which files matter." Codex+ can remove that repeated setup work.

### 5. Safety And Permission Preview

Full Access should remain conversation-scoped, but the app should make permission decisions easier:

- Explain what Full Access means for the current task.
- Show the working directory before starting a run.
- Preview likely command or file-operation risk when available.
- Make destructive or broad operations visually distinct.
- Reset elevated permission after the task ends.
- Show changed files after a run completes.

Pain point solved: users are not only deciding whether to trust Codex. They are deciding whether they understand the scope of this particular run.

### 6. Result Handoff

When a Codex task finishes, the side panel should offer structured output:

- What changed.
- Files touched.
- Verification run and result.
- Remaining risks.
- Suggested commit message.
- Suggested PR description.
- Archive-ready summary or lessons learned.

Pain point solved: the end of a Codex run often contains useful information, but it is buried in a long conversation. Codex+ should turn completion into a clean handoff.

### 7. Showcase Mode

Codex+ should include a presentation-safe mode for demos:

- Hide or redact sensitive paths.
- Use simulated project and task data.
- Show representative first-level and second-level menus.
- Reset to a clean demo state.
- Avoid exposing real clipboard, file paths, branch names, or usage details.

Pain point solved: a tool that is useful in a personal workspace can be hard to demonstrate safely. Showcase Mode makes the product explainable without leaking local details.

## Recommended Development Slices

### Slice 1: Useful Workflow Entry

Build the first version of the task entry center and result handoff. This gives Codex+ a stronger identity immediately: users can pick a common workflow, run it, and receive a structured end state.

Initial actions:

- Ask Codex.
- Review git diff.
- Explain selected text or clipboard text.
- Generate commit message.
- Summarize current thread.

### Slice 2: Project Awareness

Add a minimal project-aware dashboard tile set:

- Current working directory or project name.
- Git branch and dirty state.
- Last task result.

This should remain compact and glanceable. It should not become a full project management interface.

### Slice 3: Context Tray

Introduce explicit context attachments:

- Clipboard text.
- Git diff.
- Selected files or manually added files.

The user should see the attached context before submitting the task.

### Slice 4: Task History And Handoff

Persist a small local task history:

- Prompt.
- Action type.
- State.
- Started and finished timestamps.
- Final summary.
- Files changed when available.

The side panel can then recall recent tasks and support archive or PR handoff workflows.

### Slice 5: Safety Preview And Showcase Mode

Add richer permission preview and demo-safe presentation controls after the core workflows are proven.

## Architecture Implications

Keep the existing split between app-specific UI and testable core logic.

Core should own:

- Action definitions and prompt templates.
- Menu category and second-level action models.
- Dashboard state models.
- Context attachment models.
- Task summary and handoff models.
- Pure parsing and formatting rules.

App should own:

- Menu rendering.
- Global shortcut and window behavior.
- Clipboard, selected text, selected files, and macOS integration.
- Dashboard tile views.
- Context tray UI.
- Conversation and handoff controls.

Runner integration should remain centered on Codex execution. It can later accept action templates and context attachments, but the first implementation should keep command construction understandable and testable.

## Data Flow

1. User opens Codex+ by shortcut or menu.
2. App shows dashboard state and available actions.
3. User chooses a task category and second-level action.
4. App builds a prompt from the action template and selected context.
5. User reviews attached context and permission mode.
6. Codex+ starts `codex exec --json`.
7. Events stream into the side conversation panel.
8. On completion, Codex+ generates or displays structured handoff artifacts.
9. The task can be copied, continued, archived, or used to prepare a commit or PR.

## Error Handling

- Missing project context should fall back to a generic Ask Codex flow.
- Git-dependent actions should show unavailable state outside a git repository.
- Clipboard and selected-text actions should be disabled or show a clear empty-state when no usable text exists.
- Context collection failures should not block manual prompting.
- Handoff generation should degrade to a plain final answer if structured data cannot be inferred.
- Showcase Mode must never read real sensitive local state unless the user explicitly exits demo mode.

## Testing Targets

Core tests should cover:

- Action category and action parsing.
- Prompt template construction.
- Context attachment formatting.
- Git status model formatting.
- Task summary and handoff model behavior.
- Safety preview state transitions.

App smoke checks should cover:

- Menu category navigation.
- Compact panel layout with additional tiles.
- Side panel handoff controls.
- Empty and unavailable states.
- Showcase Mode redaction.

## Non-Goals

- Do not replace the Codex app.
- Do not build a full IDE.
- Do not create a large persistent knowledge database in the next slice.
- Do not require cloud services.
- Do not make all possible menu actions before validating a small high-value set.
- Do not persist Full Access beyond a single conversation.

## Success Criteria

Codex+ succeeds as an enhancement layer when:

- A user can start common Codex workflows without rewriting prompts.
- The app makes the active project and task state obvious before execution.
- Permission decisions feel scoped and understandable.
- Completed tasks produce useful handoff artifacts.
- The product is easy to demo without exposing private workspace data.

