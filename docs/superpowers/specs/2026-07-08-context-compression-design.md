# Codex Plus Context Compression Design

Status: expanded approved design draft
Last updated: 2026-07-09

## Purpose

Context compression is a core Codex Plus workflow. It preserves long-running conversation continuity by sending a compressed, version-controlled model-input chain to the LLM while keeping the user-visible conversation fully traceable and recoverable.

This feature is not a transcript cleanup tool. It is a model-context projection system over immutable original conversation records.

## Core Principles

- The main conversation window defaults to showing original dialogue records.
- Original source records are never deleted by compression, edit, exclusion, rollback, or archive operations.
- The LLM receives only the final active model-input lineage.
- Compression, manual edits, exclusions, failed attempts, rollback branches, and joined-compression relationships are version-controlled.
- Users are responsible for intentional context edits. The app should not block aggressive shortening; it should preserve traceability and rollback.
- Visual design must satisfy Apple-style macOS aesthetics: calm, precise, spatially clear, lightweight by default, and visually richer only when relationships need explanation.
- Compression controls and lineage markers must feel native to the current Liquid Glass workbench, not like a separate technical dashboard.

## End-To-End Mental Model

The feature has three synchronized layers:

1. **Source layer:** immutable conversation events stored by conversation and shown as the default timeline.
2. **Version layer:** user-visible and model-input versions built over dialogue rounds. This layer records edits, compression, exclusion, rollback, tombstone, and lineage.
3. **Assembly layer:** a deterministic projection that converts the active version layer into the exact text sent to the model.

The user mostly reads the source layer. The app sends the assembly layer. The version layer explains why those two can differ without losing traceability.

Every feature path must preserve this invariant:

```text
source events remain recoverable
    -> active lineage can be recomputed
    -> assembled model input can be reproduced
    -> archive can preserve both source and lineage
```

If any operation cannot maintain that chain, it should fail without changing the active lineage.

## Existing State

The codebase already contains partial compression-related pieces:

- `ConversationContextCompressionSnapshot`
- `ConversationContextCompressionRepository`, backed by memory cards
- `ConversationContextCompressionAssembler`
- `ConversationTimelineBuilder.items(from:compressionSnapshots:)`
- `ConversationCompressionSnapshotRow`
- Built-in `conversationContextCompression` prompt template

These pieces prove the direction, but they are not the final product architecture. The old memory-card-backed compression snapshot format is abandoned experimental data and does not need migration.

## Selected Architecture

Use the complete architecture path:

- Dedicated compression version-control tables.
- Explicit model-context budget and compression execution provider interfaces.
- A Codex CLI adapter for the first implementation.
- Full active-lineage model input assembly.
- Main timeline markers, popover preview, right-side inspector, edit dialog, and model input preview.

This approach is chosen over reusing the old memory-card snapshot layer or shipping a manual-only MVP because the feature must satisfy data correctness, UI usability, and long-context continuity in the first complete version.

## Provider Boundaries

The compression feature must not hard-code itself directly to Codex CLI.

Business logic depends on capability interfaces:

- `ContextBudgetProvider`: supplies model context window, assembled-context token usage, and budget state.
- `CompressionExecutionProvider`: performs compression work and returns success or failure results.

The first implementation should provide a Codex CLI adapter. If the underlying Codex CLI is replaced later, Codex Plus should replace the adapter while preserving:

- Compression version storage
- Active lineage rules
- User-visible original records
- Version history UI
- Model input assembly
- Archive behavior
- Tombstone and rollback behavior

## Data Model

Context compression needs dedicated structured persistence. It should not store complete version control state as generic memory cards.

Dedicated storage must represent:

- Dialogue rounds
- User segments
- AI segments
- Segment versions
- Parent-child version relationships
- Joined-compression source relationships
- Active lineage selection
- Tombstoned branches
- Compression input records
- Run lifecycle boundaries

### Proposed Storage Shape

The exact SQLite column names can change during implementation, but the model needs these concepts as first-class records.

`compression_rounds`

- `id`
- `conversation_id`
- `round_index`
- `user_event_id`
- `first_ai_event_id`
- `last_ai_event_id`
- `run_state`
- `run_started_at`
- `run_finished_at`
- `created_at`
- `updated_at`

Purpose: stable round identity. The round is the minimum unit used by selection, compression source metadata, lineage, and archive recovery.

`compression_round_events`

- `id`
- `round_id`
- `event_id`
- `role_bucket` with values `user` or `ai`
- `ordinal`

Purpose: precise event membership for each round. This avoids relying on event ordering assumptions after the fact.

`compression_versions`

- `id`
- `conversation_id`
- `scope_kind` with values such as `round`, `range`, or `assembled`
- `operation` with values such as `original`, `manual_edit`, `default_compression`, `custom_compression`, `system_compression`, `exclude`, `failed_compression`, or `tombstone`
- `status` with values such as `active`, `historical`, `failed`, or `tombstoned`
- `content`
- `created_at`
- `updated_at`
- `template_id`
- `compression_input_id`
- `error_message`

Purpose: store the actual version body and the operation that created it.

`compression_version_sources`

- `id`
- `version_id`
- `source_kind` with values `round`, `version`, or `range`
- `source_id`
- `ordinal`

Purpose: describe what the version was generated from. A joined compression version has multiple source versions or source ranges.

`compression_lineage_edges`

- `id`
- `parent_version_id`
- `child_version_id`
- `edge_kind` with values such as `edit`, `compress`, `join`, `exclude`, `rollback`, or `system_compress`
- `created_at`

Purpose: preserve the history graph even though the normal UI presents it as a linear history.

`compression_active_versions`

- `conversation_id`
- `round_id` or `range_id`
- `active_version_id`

Purpose: make the active model-input projection explicit and quick to load.

`compression_inputs`

- `id`
- `conversation_id`
- `mode` with values `default_template`, `custom_template`, or `system`
- `template_id`
- `user_instruction`
- `input_snapshot`
- `provider_name`
- `provider_model`
- `created_at`

Purpose: record what was sent to the compression provider. `user_instruction` is stored here and hidden from normal history by default.

`compression_tombstones`

- `id`
- `version_id`
- `reason`
- `replaced_by_version_id`
- `created_at`

Purpose: hide deleted downstream branches from normal UI while retaining audit and recovery data.

### Data Invariants

- Every source conversation event belongs to zero or one compression round.
- Every round has exactly one user segment and one AI segment, but the AI segment may contain zero events if a run failed before producing output.
- Original versions are immutable.
- Manual edit versions always have exactly one parent version.
- Compression versions have one or more source versions or source rounds.
- Joined compression versions must have at least two sources.
- Failed compression versions can have sources and error metadata, but they cannot be active.
- Tombstoned versions cannot be active and cannot be assembled into model input.
- A conversation can have only one active model-input lineage at a time.
- Active lineage assembly must be deterministic for the same database state.
- Archive export must be reproducible from stored source events and compression records.

### Dialogue Rounds

The minimum traceable compression unit is one dialogue round:

- One user segment
- One AI segment

UI round segmentation uses the next user message as the visible boundary. Everything after a user message and before the next user message is displayed as that round's AI segment.

The AI segment includes all original events in that turn:

- Assistant messages
- Commands
- Status events
- Errors
- Parse warnings
- Technical/tool events represented in the conversation event stream

Storage should also record run lifecycle boundaries such as completed, failed, or stopped so execution provenance remains traceable even when the UI groups by user-message boundaries.

### Version Types

Each user segment or AI segment can have versions:

- Original
- Manual edit
- Default-template compression
- Custom-template compression
- System compression
- Exclusion from LLM input
- Failed compression attempt
- Tombstone

Versions do not need user-authored titles. Version history displays version number and timestamp. Supporting metadata can show operation type, template, source rounds, and whether the version came from user edit, default compression, custom compression, or system compression.

### Active Lineage

The LLM input always follows the final active lineage only. Historical versions are not selectable as LLM input.

Example:

```text
ABCDEFG -> AMCDENG -> AODENG -> APENG
```

The LLM receives only:

```text
APENG
```

Some ranges may remain uncompressed and therefore remain as original segments in the final active lineage. Multiple compressed ranges can be joined into a later combined compression version, and only the latest joined result remains active for model input.

### Rollback And Tombstone

Rollback is allowed, but rollback creates a new version branch. After rollback creates a new branch, the previously active downstream branch is deleted from the user-visible lineage rather than kept as an alternate active lineage.

Deleted downstream versions are tombstoned:

- Hidden from normal UI
- Not sent to the LLM
- Not part of the active version history
- Retained in storage for debugging, safety, and recovery from accidental destructive actions

Original source records are never tombstoned by compression operations.

## Compression Triggers

Compression has two entry paths:

- Manual compression
- Required compression when the active model input reaches the hard model-context limit

### Manual Compression

Users can manually select a continuous range of dialogue rounds for compression. Manual multi-round compression cannot select non-contiguous rounds such as 2, 5, and 9 in one operation.

Manual compression options:

1. Do not compress
2. Compress with the default context compression prompt template
3. Custom compression

`Do not compress` cancels the current manual compression operation. It does not create a new version node or mark selected rounds as reviewed. When the model limit requires compression before continuing, cancellation cannot satisfy the requirement to continue sending.

Manual compression results become active immediately. Users correct unwanted results through rollback and later edits rather than through a candidate-acceptance step.

### Custom Compression

Custom compression prompts come from the prompt template management library.

The user can:

- Choose a compression template
- Add per-compression instructions
- State what to preserve
- State what matters most
- State the intent this compression should follow

Per-compression instructions are stored as part of the compression input record. They are not shown in the normal version-history UI by default.

### System Compression

When the active model-input context reaches the hard model limit:

- The send button is disabled.
- The UI tells the user compression is required before continuing.
- A compression action near the send button appears, labeled along the lines of `交付系统完成压缩`.
- System compression executes through the compression provider, with the first implementation using the Codex CLI adapter.
- Compression runs are transient background work.
- Compression runs are not appended to normal conversation history and do not appear as user, assistant, command, or status timeline events.
- The compression run itself does not need ongoing tracking after completion.
- The compression result must be saved into compression version control.
- System-compression results become active immediately.

System compression follows Codex CLI compression behavior for choosing what to compress, but Codex Plus must record exactly which active dialogue rounds Codex compressed. Version lineage and source metadata only need to be precise at dialogue-round granularity.

Example:

```text
ABCDEFG -> AMG -> N
```

The version history must clearly show that `AMG` was the active lineage before system compression and `N` was generated by system compression from `AMG`.

### Compression Execution Flow

Manual and system compression share the same persistence flow after the source range is chosen.

Flow:

1. Resolve the selected continuous round range or the provider-selected system-compression range.
2. Capture an input snapshot from the current active lineage.
3. Save a `compression_inputs` record with template, provider, selected rounds, and optional user instruction.
4. Start compression through `CompressionExecutionProvider`.
5. Do not append compression run events to normal conversation history.
6. Collect provider output.
7. On success, create a new compression version.
8. Link the new version to the exact source rounds or source versions used.
9. Update active lineage in one transaction.
10. Refresh UI state and budget state.

Failure flow:

1. Save a failed compression version or failed attempt record.
2. Link the failure to the same source input snapshot.
3. Keep the previous active lineage unchanged.
4. Keep send disabled if the hard limit still applies.
5. Show error state in version history and relevant UI.

### Compression Concurrency

Only one compression operation should mutate a conversation's active lineage at a time.

Rules:

- A running compression for conversation A does not block normal work in conversation B.
- A running compression for conversation A should block another compression on conversation A.
- If the user edits a version while compression is running on the same source lineage, the compression result must not blindly overwrite the newer active lineage.
- The implementation should compare the active lineage revision captured at compression start with the active lineage revision at compression finish.
- If the lineage changed during compression, save the compression result as failed/stale or require retry, rather than applying it to the changed lineage.
- Stale compression attempts should be visible enough for debugging but should not become active.

### Transaction Boundaries

The following changes must be atomic:

- Creating a successful version and updating active lineage.
- Rolling back and tombstoning replaced downstream versions.
- Excluding a version from LLM input.
- Deleting an active version node and falling back to an earlier version.
- Archiving source events and compression metadata.

If any part of these operations fails, the app should leave the prior active lineage intact.

## Context Budget

The first implementation must include real model-context-limit detection. It must not rely only on character counts, event counts, or waiting for Codex CLI to fail after sending.

Budget state should be dynamically tiered by model context-window size rather than one fixed percentage for every model.

Required budget states:

- Safe
- Advisory or near-limit state
- Hard-limit state

The implementation can define more detailed states when helpful. Small-window models can warn earlier, while large-window models can delay warnings and add intermediate states.

Behavior:

- Near limit: warn that compression is recommended, but sending remains available.
- At or beyond hard limit: disable sending and require compression before continuing.

### Budget Provider Contract

`ContextBudgetProvider` should return a structured result, not just a Boolean.

Required fields:

- `modelIdentifier`
- `contextWindowTokens`
- `assembledInputTokens`
- `reservedOutputTokens`
- `usableInputTokens`
- `usageRatio`
- `budgetState`
- `measurementSource`

`budgetState` should be at least:

- `safe`
- `notice`
- `warning`
- `hardLimit`
- `unknown`

`unknown` is important. If the provider cannot get trustworthy token information, the UI should not pretend the budget is known. The first implementation should prefer conservative behavior: allow manual compression, show that the budget is unknown, and avoid disabling send unless the hard limit is known or a provider reports that the assembled context cannot be sent.

### Dynamic Threshold Guidance

The implementation should define thresholds by context-window class. Exact values belong in code and tests, but the design intent is:

- Small windows warn earlier because there is less room for follow-up output.
- Medium windows use moderate warning thresholds.
- Large windows can delay early warnings but still enter notice/warning before hard limit.
- Hard-limit state is based on usable input tokens, not raw context window, because output reserve matters.

Example classes:

- Small: below 32K tokens
- Medium: 32K to below 128K tokens
- Large: 128K tokens and above

### Model Input Assembly

The assembly layer builds the exact text sent to the LLM.

Assembly order:

1. Load conversation source events.
2. Build or load dialogue rounds.
3. Load active compression versions for each affected round or range.
4. Walk the conversation in round order.
5. For each round, choose the active lineage output:
   - excluded versions contribute nothing to model input
   - active edited versions contribute their content
   - active compression versions contribute their content
   - rounds with no active replacement contribute original user and AI segment text
6. Apply joined-compression ranges so that replaced child ranges are not emitted twice.
7. Append the new user prompt for the pending send.
8. Produce final assembled text.
9. Pass final assembled text to the budget provider before starting the run.

The model input preview uses the same assembly function. It must not have its own formatting path. If preview and send can diverge, that is a bug.

### Assembly Edge Cases

- If a joined-compression version covers rounds 3 through 7, rounds 3 through 7 are replaced by the joined version content in the assembled output.
- If round 5 inside that range is tombstoned from an old branch, it must not reappear.
- If a round is excluded from LLM input, it contributes no text but remains visible in the UI.
- If a compression failed, the previous active version remains active.
- If a manual edit creates an empty version, the empty version is valid if the user intentionally saved it. It contributes no text but remains different from exclusion because it is an active edited version, not an excluded state.
- If a provider cannot determine exact token usage, the preview is still valid as text, but budget status is `unknown`.

## Manual Editing

Manual edits target exactly one user dialogue segment or one AI dialogue segment.

Manual edits create a new version instead of mutating the previous version in place.

Editing is intended to give the user full control over compression length. For example, if an AI response is long but only one sentence matters for the user's next goal, the user can create a revised AI segment that keeps only that sentence.

The system should not block aggressive edits on the grounds that they might damage context. The user is responsible for intentional edits, and the product preserves rollback and traceability.

Editing the latest version opens a dedicated edit dialog instead of editing directly in the inspector. The edit dialog provides enough space for long text and includes a `查看差异` action to compare against the previous version. Saving does not require a diff confirmation step.

## Manual Reduction

If compression fails or the active model input remains too large, the user can manually reduce active model-input context.

Allowed reduction operations:

- Create revised shorter versions
- Mark active versions as excluded from LLM input
- Delete active version nodes to fall back to earlier versions

These operations affect active model-input lineage only. Original source records remain viewable and recoverable.

Excluded content remains visible in the main timeline, shows an `已排除模型上下文` marker, and is visually dimmed or semi-transparent to indicate it is not part of active model input.

## Failure Behavior

Failed compression attempts appear in version history.

Failed attempts:

- Do not become active model-input versions
- Show enough error detail for the user to understand that compression did not apply
- Remain available for traceability

If the conversation is blocked because the active model-input context has reached the hard model limit, a failed compression leaves sending disabled. Sending remains disabled until compression succeeds or the user manually edits/deletes enough active context to fit the model limit.

## Main Timeline UI

The main timeline defaults to displaying original dialogue text.

It must clearly mark:

- Where a versioned range starts and ends
- Whether a range has edits, compression, or both
- Whether each round is currently sent as original text, edited text, compressed text, joined compressed text, or excluded from model context

Compressed ranges use bracket-like start and end boundary markers in the main timeline rather than repeating heavy markers throughout the whole range.

Each round shows a lightweight LLM-input status marker:

- Quiet by default
- Hover shows current version type, version number, source rounds, and whether it comes from edit, compression, joined compression, or exclusion
- Click opens a lightweight popover preview for the relevant round or range
- Unchanged original rounds may show a very light `原文发送` hover summary but should not visually compete with changed rounds

Joined-compression relationships appear in the main timeline as lightweight visual hints, such as a side connector, bracket, or compact relation marker.

### Timeline State Matrix

Each round can present one primary model-input state:

- `原文发送`: source text is sent as-is.
- `已修订`: a manual edit is active.
- `已压缩`: a compression version is active.
- `拼接压缩`: a joined compression version covers this round.
- `已排除模型上下文`: the round is visible but omitted from model input.
- `压缩失败`: the latest compression attempt failed and the previous active version remains in effect.

Visual rules:

- `原文发送` should be nearly invisible until hover.
- `已修订` and `已压缩` use calm, low-saturation indicators.
- `拼接压缩` can use a connector or bracket to show relationship with neighboring rounds.
- `已排除模型上下文` uses both a marker and dimmed content.
- `压缩失败` uses a warning treatment but should not look like the active model input is broken if the previous active version is still valid.

### Selection Rules

- Single-round selection enables edit, compress, exclude, and history actions.
- Continuous multi-round selection enables compress and exclude actions.
- Non-contiguous multi-selection is not allowed for manual compression.
- Selection handles should make start and end round boundaries clear.
- When a selected range already participates in a joined compression, the UI should show that replacing it may create a new active lineage and tombstone the replaced downstream branch.

### Accessibility And Interaction Details

- Every icon-only control needs an accessibility label and tooltip.
- Status markers need accessible text equivalent to the visual state.
- Hover-only information must also be reachable by click or keyboard focus.
- Keyboard users should be able to open the popover, move to the inspector, and trigger primary actions.
- The edit dialog must support standard macOS text editing behavior.
- Relationship lines should never be the only source of meaning; labels or summaries must explain the relationship.

## Popover, Inspector, And Edit Dialog

The status-marker click opens a lightweight popover preview.

The popover provides a `查看完整历史` action.

`查看完整历史` opens a right-side inspector.

The right-side inspector owns:

- Full version history
- Edit entry points
- Rollback
- Continue-compress actions
- Detailed source-lineage display
- Joined-compression relationship display
- Model input preview entry

When the inspector selects a version, the main conversation timeline subtly highlights the corresponding original source range. The highlight should use restrained visual treatment such as a light boundary or soft background and should disappear when the inspector closes.

The expanded version history is primarily linear. Versions are arranged vertically from original text to the latest active version for fast scrolling. Joined-compression relationships are shown as auxiliary connectors or source hints rather than replacing the linear scan with a graph-first DAG view.

## Model Input Preview

The model input preview is reachable from two places:

- Near the send button, only when the current conversation has compressed, edited, or excluded model-input versions
- From the right-side inspector

The send-button-adjacent entry answers: "What will be sent if I send now?"

The top conversation toolbar should not add a separate model input preview entry unless a later design has a stronger reason.

The model input preview itself shows only the final assembled text that will be sent to the LLM.

Source rounds, version numbers, operation types, compression chain diagrams, and token/debug details belong in the right-side source/version traceability inspector, not inside the model input preview text.

If the inspector opens a model input preview, that preview still shows only final assembled model-input text. Traceability details remain in the inspector's lineage areas.

## Operation Entry Points

Compression and version operations use layered controls:

- Each user or AI segment can expose lightweight nearby controls for common actions.
- Selecting one or more segments shows a contextual action bar for batch operations.
- Less common, detailed, or destructive operations such as rollback, tombstone recovery, and advanced exclusion live in a more menu.

## Archive Behavior

Archived conversations must preserve compression data.

A conversation archive includes:

- Complete original conversation text and events
- Compression version history
- Manual edit versions
- Failed compression attempts
- Tombstoned branches needed for audit/recovery
- Source round mappings
- Joined-compression lineage
- Final active model-input chain at archive time

Archive output should make the original conversation and model-input lineage recoverable, not only export the visible chat transcript.

Archive search searches original conversation text only. Compression versions, manual edit versions, failed compression attempts, tombstones, and lineage metadata are preserved for traceability and recovery, but they do not participate in the archive search index.

### Archive Serialization

Archive export should contain two layers:

1. Human-readable transcript and summary.
2. Structured compression metadata for recovery and audit.

The human-readable archive should prioritize original text and clear status summaries. It does not need to print every tombstoned body inline.

Structured metadata should include:

- Rounds and event IDs
- Version IDs and operation types
- Active lineage at archive time
- Source relationships
- Joined-compression relationships
- Tombstone records
- Failed compression records
- Compression input records

Archive restore should be able to recover the conversation source and compression state if the app later supports restoration from archive. Even before full restore support exists, the archive format should avoid throwing away data that restoration would require.

### Archive Search Boundary

Archive search indexes only original source text. This prevents a manually shortened or compressed version from changing search semantics. Search should find what originally happened in the conversation, not every later projection over it.

## Migration Rule

Do not migrate old memory-card-backed compression snapshots.

Existing old compression snapshot data can be deleted by the user and treated as abandoned experimental data.

The complete feature reads and writes only the new dedicated compression version-control storage.

Backward compatibility with the old `MemoryRepository` compression snapshot format is not required.

## Out Of Scope

- Multi-conversation memory synthesis
- Cross-project memory sharing
- Cloud sync or remote compression storage
- Fully automatic background compression without user-visible state
- Non-contiguous manual multi-round compression
- Graph-first version history UI
- Searching archived compression versions

## Acceptance Criteria

The first complete version is acceptable only if all three categories below pass.

### Data Correctness

- Dialogue rounds preserve user segment and AI segment boundaries.
- Original records remain recoverable after edit, compression, exclusion, rollback, and archive.
- Manual edits create new versions and never mutate previous versions in place.
- Compression results become active immediately and are recorded in version lineage.
- Failed compression attempts appear in history but never become active model input.
- Rollback creates a new branch and tombstones replaced downstream branches.
- Tombstoned branches are not visible in normal history and are not sent to the LLM.
- Active lineage assembly produces the exact final text sent to the LLM.
- Old memory-card-backed compression data is not required for the new feature.

### UI Usability

- Users can select continuous dialogue ranges and run compression.
- Users can inspect per-round LLM-input status from the main timeline.
- Users can open popover previews and the right-side version inspector.
- Users can edit the latest version in a dedicated edit dialog.
- Users can view diffs on demand.
- Users can rollback versions.
- Users can exclude content from model input while keeping original text visible.
- Users can understand joined-compression relationships through lightweight timeline hints and detailed inspector lineage.
- The interface follows Apple-style macOS aesthetics and remains readable.

### Long-Context Continuity

- The app detects real context budget state before sending.
- Near-limit state warns but still permits sending.
- Hard-limit state disables sending.
- Hard-limit state offers system compression near the send button.
- System compression runs outside normal conversation history.
- System compression result is saved into compression version control and becomes active.
- After successful compression or manual reduction, the user can continue sending.
- If compression fails, sending remains disabled until the context fits.

## Test Strategy

The implementation plan must include tests at four levels.

### Core Model Tests

- Round builder groups events by user-message boundaries.
- AI segment includes assistant, command, status, error, and warning events.
- Original versions are immutable.
- Manual edit creates a child version.
- Compression creates lineage edges and source records.
- Joined compression covers multiple continuous rounds.
- Non-contiguous manual compression is rejected.
- Exclusion removes content from assembled model input without deleting source.
- Failed compression is visible in history but cannot become active.
- Rollback creates a new branch and tombstones replaced descendants.
- Tombstoned versions are excluded from active assembly.

### Assembly Tests

- No versions produces original assembled text.
- Manual edit replaces only the edited segment.
- Compression replaces the selected continuous range.
- Joined compression does not duplicate child rounds.
- Exclusion emits no text for the excluded active version.
- Empty manual edit emits empty content and is distinct from exclusion.
- Failed compression preserves the previous active lineage.
- Preview text equals send text for the same database state.

### Budget And Provider Tests

- Budget provider reports safe, notice, warning, hard-limit, and unknown states.
- Dynamic thresholds vary by context-window class.
- Hard-limit state disables send.
- Near-limit state warns without disabling send.
- Unknown budget state does not falsely claim safety or hard-limit.
- Compression provider success creates an active version.
- Compression provider failure creates a failed history entry and leaves active lineage unchanged.
- Stale compression result cannot overwrite a newer active lineage.

### UI Source Tests

- Main timeline uses original text as default display.
- Changed rounds expose LLM-input status markers.
- Excluded rounds display `已排除模型上下文` and dimmed content.
- Popover and inspector entry points exist.
- Model input preview path is separate from lineage traceability path.
- Archive search still indexes original text only.

## Risks And Guardrails

- **Risk: preview and send diverge.** Guardrail: use one assembly function for both.
- **Risk: compression overwrites user edits made during a running compression.** Guardrail: compare active lineage revision before applying compression result.
- **Risk: version history becomes graph-heavy and hard to scan.** Guardrail: keep version history linear-first and show graph relationships as auxiliary hints.
- **Risk: original source is accidentally treated as mutable.** Guardrail: original versions and conversation events are immutable.
- **Risk: archive drops version-control metadata.** Guardrail: archive human-readable transcript and structured compression metadata together.
- **Risk: future non-Codex provider breaks assumptions.** Guardrail: keep provider interfaces capability-based and keep storage/provider concerns separate.
- **Risk: UI becomes visually noisy.** Guardrail: timeline markers stay quiet by default; detailed controls live in popover, inspector, and menus.
