# Codex Plus V1 Redesign Design

Date: 2026-07-05

## Summary

Codex Plus V1 is a native macOS enhancement shell for Codex. It should first make Codex's basic workflow reliable inside a local desktop app: choose a project, start a Codex CLI task, view the full conversation and execution stream, continue or stop the task, archive the complete conversation, search archived conversations, and reopen an archived conversation with its full event history.

V1 is not the full long-term memory product. Memory work in V1 is limited to local persistence foundations: schemas, files, indexes, and references that allow future memory cards, injection, extraction, and review workflows to build on stable data. Manual memory injection, automatic memory extraction, STAR review, and periodic review are post-V1 features.

The old codebase is treated as historical product exploration only. It may inform interaction ideas such as the floating activity window, but the V1 product, architecture, and implementation plan should be designed from first principles.

## Process Gate

Development must not start until requirements, prototypes, and this design are approved by the user.

If the user is dissatisfied with any requirement, prototype, or design section, the project remains in design and does not move to implementation planning or code changes.

## Product Boundary

V1 must implement:

- Project or working-directory selection.
- Creating a new Codex task.
- Running Codex CLI through an execution engine adapter.
- Displaying user messages, assistant messages, command events, errors, and raw execution events.
- Sending follow-up prompts in the same conversation.
- Stopping a running task.
- Basic execution mode and permission configuration.
- Archiving a complete conversation.
- Searching archived conversations.
- Reopening an archived conversation from search results.
- Preserving local data structures for future memory features.

V1 must not implement:

- Manual memory injection into the active conversation.
- Automatic memory extraction from completed tasks.
- Full memory card review boards.
- STAR review generation as a required flow.
- Periodic review.
- Similar-task memory recommendation.
- Custom agent execution beyond the Codex CLI adapter.
- Plugin systems.

## Primary Product Surfaces

### Main Window

The main window is the source of truth for project navigation, conversation execution, archive search, and reopened archived conversations.

It follows a three-area structure:

- Left navigation: projects, active conversations, archived conversation entry points, and search.
- Center work area: current conversation, execution stream, follow-up composer, stop action, and archive action.
- Right auxiliary area: environment state such as current project path, Git branch, dirty state, execution mode, Codex CLI availability, and future extension slots.

The V1 complexity should live primarily in the left navigation and center work area. The right auxiliary area stays lightweight.

### Floating Activity Window

Codex Plus keeps the original floating-window idea, but defines it as a companion layer rather than a replacement for the main window.

The floating window handles:

- Global shortcut invocation.
- Fast first prompt entry.
- Recent or current project selection.
- Running task status.
- Quick follow-up for the active task.
- Stop action for the active running task.
- Opening the corresponding full conversation in the main window.
- Completion notification and archive prompt.

The floating window and main window must share the same task state. They must not maintain separate copies of conversation or run data.

## Information Architecture

### Left Navigation

The left navigation contains:

- New conversation.
- Search.
- Project list.
- Conversations grouped by project.
- Conversation states: running, completed, failed, stopped, archived.
- Archived conversation entry points.

Future navigation items can include:

- Memory library.
- Plugins.
- Scheduled tasks.

These future items must not be required for V1 completion.

### Center Work Area

The center work area contains:

- Full conversation message stream.
- User prompts.
- Assistant responses.
- Codex CLI JSON events mapped into readable rows.
- Command events.
- Error and warning rows.
- Raw event preservation for diagnostics.
- Follow-up composer.
- Stop action while running.
- Archive action after completion, failure, or stop.
- Reopened archived conversation view.

Archived conversations default to read-only. Restoring an archived conversation into a new active conversation is a post-V1 extension.

### Right Auxiliary Area

The right area contains compact local context:

- Project path.
- Git branch.
- File change counts.
- Execution mode and permission state.
- Codex CLI availability.

It can later host memory and context tools, but V1 does not require memory injection UI.

## Task Lifecycle

A V1 task follows this flow:

1. User selects or confirms a project or working directory.
2. User creates a conversation and sends the first prompt.
3. The app creates a task record and conversation record.
4. `CodexCLIEngine` starts Codex CLI in the selected working directory.
5. Codex stdout JSON events stream into the app.
6. The app stores raw events and structured conversation events.
7. The user can send follow-up prompts while the conversation remains active.
8. The user can stop the running task.
9. The task reaches completed, failed, or stopped state.
10. The user archives the conversation.
11. The app writes a complete structured archive and a readable Markdown archive.
12. Search indexes are updated.
13. User can search archives and reopen the full conversation.

Task state transitions:

- Draft.
- Running.
- Completed.
- Failed.
- Stopped.
- Archived.

Only running tasks can be stopped. Archived conversations are preserved and searchable.

## Execution Engine

V1 defines an execution engine abstraction and implements only `CodexCLIEngine`.

The engine interface must support:

- Starting a task.
- Continuing a conversation.
- Stopping a running task.
- Streaming raw events.
- Streaming structured display events.
- Reporting completion, failure, and stop results.
- Exposing engine metadata for archives.

`CodexCLIEngine` is responsible for:

- Checking whether Codex CLI is available.
- Starting Codex CLI in a selected working directory.
- Requesting JSON output from Codex CLI.
- Parsing user-visible event types.
- Capturing stderr.
- Preserving raw JSON lines.
- Stopping the child process.
- Reporting startup failure clearly.

The task and archive systems must depend on the execution engine interface, not on Codex CLI command-line details.

Future engines can include:

- OpenAI API agent engine.
- Other CLI agent engines.
- Local model engines.
- Remote execution engines.

## Local Persistence

V1 uses SQLite plus Markdown and attachment files.

SQLite is the source of truth for structured data and reconstruction. Markdown is a readable export and archive surface, not the only persisted representation.

### SQLite Tables

`projects`

- Stores project ID, display name, normalized path, created time, last opened time, and archive count metadata.

`conversations`

- Stores conversation ID, project ID, title, state, engine ID, working directory, created time, updated time, archived time, and archive file path.

`conversation_events`

- Stores event ID, conversation ID, sequence number, event type, display text, structured payload JSON, raw engine payload, timestamp, and searchable text.

`archive_index`

- Stores archive ID, conversation ID, project ID, title, searchable text, command text, error text, project path, and timestamps for archive search.

`memory_cards`

- Stores local memory foundations for post-V1 features. Fields include card ID, scope, type, title, summary, body text, content shape, status, created time, updated time, and source metadata.

`memory_sources`

- Links a memory card to a source conversation, event, archived fragment, file path, screenshot, or attachment.

`attachments`

- Stores attachment ID, owner type, owner ID, file path, original file path, content type, size, checksum, created time, and whether it is a snapshot copy.

### Memory Card Foundations

Memory cards are persisted locally in V1 so they can be searched and expanded later.

Supported memory scopes:

- Project-level.
- User-level.

Supported content shapes:

- Text.
- Image plus text.
- File reference.
- File snapshot.
- Task excerpt.

Supported fixed memory types:

1. Product constraint.
2. Prototype or design material.
3. Architecture decision.
4. Implementation rule or code convention.
5. API or data contract.
6. Test boundary.
7. Bad case or pitfall.
8. Operation flow or command.
9. Retrospective or STAR note.

Memory cards can also have free-form tags. V1 storage must allow create, rename, edit, delete, summary edit, scope change, and source management at the data-model level. Full memory management UI is not required for V1 completion.

### File Layout

Global app data stores:

- SQLite database.
- User-level memory attachments.
- Global archive exports if a conversation does not belong to a project-specific storage area.

Project data can store:

- `.codex-plus/archives/`
- `.codex-plus/memory/`
- `.codex-plus/attachments/`

V1 defaults to global app data storage for SQLite, archive records, memory foundations, and attachments. Project-local `.codex-plus/` folders are created only when the user opts into project-local storage or explicitly exports project artifacts into the project. The data model must support both global and project-local storage from the beginning.

## Archive And Search

Archiving must preserve complete conversations, not only summaries.

An archive includes:

- Project ID and path.
- Conversation metadata.
- Engine metadata.
- User messages.
- Assistant messages.
- Command events.
- Error events.
- Raw JSON lines where available.
- stderr excerpts.
- Completion state.
- Created, updated, completed, stopped, failed, and archived timestamps where applicable.

Search must support:

- Conversation title.
- Project name and path.
- User messages.
- Assistant messages.
- Command text.
- Error text.
- Searchable event text.

Opening a search result must reconstruct the full conversation from SQLite event records. Markdown export can be opened as a readable artifact, but UI reconstruction must not depend solely on Markdown parsing.

Search indexes must be rebuildable from stored conversation and archive records.

## Error Handling

Codex CLI missing:

- Main window and floating window show Codex unavailable.
- User can configure or retry the executable path.
- Task creation is blocked until the engine is available.

Project path missing or inaccessible:

- Task does not start.
- Prompt draft and selected project state are preserved.

Codex startup failure:

- Conversation receives a failure event.
- stderr and startup error details are stored.

JSON parse failure:

- Raw line is preserved.
- UI shows a parse warning.
- Archive remains complete.

Window closed while task runs:

- Closing a window does not automatically discard the task.
- App quit requires confirmation if tasks are running.

Stop failure:

- Task records stop request failure.
- Error details are stored.

Archive failure:

- Active conversation is not deleted.
- User can retry archive.

Search indexing failure:

- Archive still completes if complete records are stored.
- Index can be rebuilt later.

## Testing Targets

Core tests should cover:

- Execution engine protocol behavior using fake engines.
- Codex CLI event parser samples.
- Raw JSON preservation.
- Event sequence ordering.
- Task state transitions.
- Stop behavior for one running task.
- Conversation event persistence.
- Archive record creation.
- Markdown archive rendering.
- Search index creation.
- Search over user message, assistant message, command, error, and project path.
- Reopening archived conversation from stored event records.
- Memory card schema creation and basic CRUD at the data layer.

App smoke checks should cover:

- Creating a task from the main window.
- Creating a task from the floating window.
- Showing running status in both surfaces.
- Opening a running task from the floating window in the main window.
- Stopping a task.
- Archiving a completed conversation.
- Searching and reopening an archived conversation.
- Codex CLI unavailable state.

## V1 Completion Criteria

V1 is complete when:

- A user can create a Codex task from the main window.
- A user can create a Codex task from the floating window.
- The app shows the full execution process.
- The app supports follow-up prompts.
- The app supports stopping a running task.
- The app archives a complete conversation.
- The app searches archived conversations.
- A user can reopen a full archived conversation from search results.
- Floating window and main window share task state.
- Memory card data foundations exist locally but do not need injection or automatic extraction workflows.

## Post-V1 Roadmap

Post-V1 features include:

- Manual memory injection into active conversations.
- Automatic memory extraction from archived tasks.
- Memory card review board.
- STAR summary generation.
- Similar-task memory recommendation.
- Periodic review.
- Full memory library UI.
- Restoring archived conversations into new active conversations.
- Additional execution engines.
- Plugin workflows.
