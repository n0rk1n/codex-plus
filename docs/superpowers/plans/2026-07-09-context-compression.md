# Context Compression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Codex Plus context compression as a first-class, version-controlled model-input projection system: the timeline keeps original records visible and recoverable, while the model receives only the final active compressed lineage.

**Architecture:** Add dedicated compression persistence, round/version/lineage models, deterministic active-lineage assembly, budget and compression-provider interfaces, a Codex CLI compression adapter, Workbench state/actions, Apple-style timeline markers and inspector UI, and archive export support. Retire the old memory-card-backed compression snapshot path instead of extending it.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, SQLite via existing `SQLiteDatabase`, existing `ExecutionEngine` / `CodexCLIEngine`, existing prompt template repository, XCTest, current Liquid Glass workbench components.

## Source Spec

- `docs/superpowers/specs/2026-07-08-context-compression-design.md`

This plan implements the approved design. If there is a conflict, the spec wins unless the implementation discovers a concrete technical impossibility and records a new decision.

## Global Constraints

- Preserve immutable original conversation events. Compression never deletes source events.
- The normal timeline defaults to original text. Compression state appears as quiet markers, boundaries, dimming, popovers, and inspector details.
- The LLM receives only the final active lineage, never old branches, failed versions, tombstoned versions, or excluded text.
- Preview and send must call the same assembly service.
- Compression runs are transient background execution and must not be appended to normal conversation history.
- Compression results, failures, input snapshots, selected prompt template, user instruction, provider name, provider model, and source rounds must be persisted.
- Manual compression selection is continuous and round-based. The minimum traceable unit is one dialogue round: one user segment plus one AI segment.
- Manual editing can edit exactly one user segment or exactly one AI segment. Empty manual edit is valid and is different from exclusion.
- Failed compression attempts are visible in version history but cannot become active.
- Rollback creates a new active branch and tombstones the replaced downstream branch for normal UI.
- Old experimental memory-card compression snapshots do not need migration. They can remain unused until deleted in a cleanup task.
- The first complete version must detect real context budget state through a provider abstraction. Do not use event count or character count as the main gate.
- Visual design must stay native macOS, calm, precise, and compatible with existing Liquid Glass workbench styling.
- Archive search indexes original conversation text only. Archive export includes original events plus compression lineage metadata.

## File Structure

Create core models and services:

- `Sources/CodexPlusCore/ContextCompression/ContextCompressionModels.swift`
- `Sources/CodexPlusCore/ContextCompression/ContextCompressionRepository.swift`
- `Sources/CodexPlusCore/ContextCompression/ConversationRoundBuilder.swift`
- `Sources/CodexPlusCore/ContextCompression/ContextCompressionAssemblerV2.swift`
- `Sources/CodexPlusCore/ContextCompression/ContextBudgetProvider.swift`
- `Sources/CodexPlusCore/ContextCompression/CodexCLIContextBudgetProvider.swift`
- `Sources/CodexPlusCore/ContextCompression/ModelContextWindowRegistry.swift`
- `Sources/CodexPlusCore/ContextCompression/ModelInputTokenCounter.swift`
- `Sources/CodexPlusCore/ContextCompression/CompressionExecutionProvider.swift`
- `Sources/CodexPlusCore/ContextCompression/ContextCompressionService.swift`
- `Sources/CodexPlusCore/ContextCompression/CodexCLICompressionExecutionProvider.swift`
- `Sources/CodexPlusCore/ContextCompression/ContextCompressionOutputCollector.swift`

Modify persistence:

- `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift`
- `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
- `Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift`

Modify prompt templates:

- `Sources/CodexPlusCore/PromptTemplates/PromptTemplateModels.swift`
- `Sources/CodexPlusCore/PromptTemplates/PromptTemplateLibrary.swift`

Modify workbench core:

- `Sources/CodexPlusCore/WorkbenchModels.swift`
- `Sources/CodexPlusCore/WorkbenchStore.swift`
- `Sources/CodexPlusCore/ConversationRunOrchestrator.swift`
- `Sources/CodexPlusCore/Archive/ConversationArchiveMarkdownRenderer.swift`
- `Sources/CodexPlusCore/Archive/ArchiveSearchService.swift`

Modify workbench UI:

- `Sources/CodexPlusApp/AppDelegate.swift`
- `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- `Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift`
- `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift`
- `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`
- `Sources/CodexPlusApp/Views/ConversationEventRow.swift`
- `Sources/CodexPlusApp/ContextCompression/CompressionRangeMarkerView.swift`
- `Sources/CodexPlusApp/ContextCompression/CompressionStatusPopover.swift`
- `Sources/CodexPlusApp/ContextCompression/CompressionHistoryInspectorView.swift`
- `Sources/CodexPlusApp/ContextCompression/CompressionEditDialog.swift`
- `Sources/CodexPlusApp/ContextCompression/CompressionRangeActionBar.swift`
- `Sources/CodexPlusApp/ContextCompression/ModelInputPreviewSheet.swift`
- `Sources/CodexPlusApp/ContextCompression/ContextBudgetBadge.swift`

Create tests:

- `Tests/CodexPlusCoreXCTests/ContextCompressionModelTests.swift`
- `Tests/CodexPlusCoreXCTests/ContextCompressionPersistenceTests.swift`
- `Tests/CodexPlusCoreXCTests/ConversationRoundBuilderTests.swift`
- `Tests/CodexPlusCoreXCTests/ContextCompressionAssemblerTests.swift`
- `Tests/CodexPlusCoreXCTests/ContextBudgetProviderTests.swift`
- `Tests/CodexPlusCoreXCTests/ContextCompressionServiceTests.swift`
- `Tests/CodexPlusCoreXCTests/WorkbenchContextCompressionTests.swift`
- `Tests/CodexPlusCoreXCTests/ArchiveContextCompressionTests.swift`

## Implementation Contracts

These contracts are part of the plan. If an implementation task finds a better name, it can rename consistently, but it must preserve the same boundaries and behavior.

### Core Type Shape

`ContextCompressionModels.swift` should expose small value types. Do not hide persistence-critical state inside UI-only structs.

```swift
public enum CompressionSegmentKind: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
}

public enum CompressionVersionScopeKind: String, Codable, CaseIterable, Sendable {
    case round
    case range
    case assembled
}

public enum CompressionVersionOperation: String, Codable, CaseIterable, Sendable {
    case original
    case manualEdit = "manual_edit"
    case defaultCompression = "default_compression"
    case customCompression = "custom_compression"
    case systemCompression = "system_compression"
    case exclude
    case failedCompression = "failed_compression"
    case tombstone
}

public enum CompressionVersionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case historical
    case failed
    case tombstoned
}

public struct CompressionRound: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: UUID
    public var roundIndex: Int
    public var userEventID: UUID
    public var firstAssistantEventID: UUID?
    public var lastAssistantEventID: UUID?
    public var runState: String
    public var runStartedAt: Date?
    public var runFinishedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
}

public struct CompressionRoundEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var roundID: UUID
    public var eventID: UUID
    public var segmentKind: CompressionSegmentKind
    public var ordinal: Int
}

public struct CompressionVersion: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: UUID
    public var scopeKind: CompressionVersionScopeKind
    public var operation: CompressionVersionOperation
    public var status: CompressionVersionStatus
    public var content: String
    public var templateID: UUID?
    public var compressionInputID: UUID?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date
}
```

Required helper behavior:

```swift
extension CompressionVersion {
    public var canBecomeActive: Bool {
        status != .failed
            && status != .tombstoned
            && operation != .failedCompression
            && operation != .tombstone
    }

    public var emitsModelInput: Bool {
        canBecomeActive && operation != .exclude
    }
}
```

### Repository API Shape

`ContextCompressionRepository` should be broad enough for the service to use without touching SQL, but narrow enough that UI cannot write arbitrary partial state.

```swift
public protocol ContextCompressionRepository: Sendable {
    func loadCompressionState(conversationID: UUID) throws -> ConversationCompressionState
    func replaceCompressionRounds(_ rounds: [CompressionRound], events: [CompressionRoundEvent], conversationID: UUID) throws

    func saveCompressionVersion(_ version: CompressionVersion) throws
    func saveCompressionVersionSources(_ sources: [CompressionVersionSource]) throws
    func saveCompressionLineageEdges(_ edges: [CompressionLineageEdge]) throws
    func saveCompressionInput(_ input: CompressionInputRecord) throws
    func saveCompressionTombstones(_ tombstones: [CompressionTombstone]) throws

    func setActiveCompressionVersion(_ active: CompressionActiveVersion) throws
    func clearActiveCompressionVersion(conversationID: UUID, roundID: UUID?, rangeID: UUID?) throws
}
```

The implementation can add transactional batch methods if the first pass exposes race conditions, but the service must never require UI callers to perform multi-write transactions themselves.

### SQLite Data Rules

Use TEXT UUIDs in lowercased UUID string format, matching existing repository style.

Important table rules:

- `compression_rounds` is rebuilt from source events and should be idempotent for the same conversation event sequence.
- `compression_versions.content` stores the exact text emitted for that version. Empty string is valid.
- `compression_inputs.input_snapshot` stores the exact compression provider input, not just IDs.
- `compression_active_versions` stores the current projection choice. It is the fast path, not the source of truth.
- `compression_lineage_edges` and `compression_version_sources` are the audit path.
- `compression_tombstones` hides replaced downstream branches from normal UI but does not erase lineage records.

The schema should enforce these invariants where SQLite can do it cheaply:

```sql
CHECK (round_index >= 0)
CHECK (ordinal >= 0)
CHECK (status IN ('active', 'historical', 'failed', 'tombstoned'))
CHECK (operation IN (
    'original',
    'manual_edit',
    'default_compression',
    'custom_compression',
    'system_compression',
    'exclude',
    'failed_compression',
    'tombstone'
))
```

Transaction boundary:

```text
BEGIN IMMEDIATE
  save compression input if one exists
  save new version
  save version sources
  save lineage edges
  mark previous active versions historical when replaced
  insert tombstones for hidden downstream branch if rollback
  set active version if the new version can become active
COMMIT
```

If any step fails, the active lineage must remain exactly as it was before the operation.

### Assembly Algorithm Contract

The assembler is the most important correctness boundary. Workbench, preview, budget, system compression, archive, and send must all call it.

Pseudo-code:

```swift
func assemble(input: ContextCompressionAssemblyInput) throws -> AssembledModelInput {
    let state = input.compressionState
    let activeRangeReplacements = state.activeVersions.filter(\.coversRange)
    let coveredRoundIDs = Set(activeRangeReplacements.flatMap(\.sourceRoundIDs))
    var components: [AssembledModelInputComponent] = []

    for round in state.rounds.sorted(by: \.roundIndex) {
        if coveredRoundIDs.contains(round.id) {
            if let replacement = activeRangeReplacements.first(where: { $0.startsAt(round.id) }) {
                components.append(.version(replacement.versionID, replacement.content))
            }
            continue
        }

        if let active = state.activeVersion(for: round.id) {
            if active.operation == .exclude {
                components.append(.excluded(round.id))
            } else {
                components.append(.version(active.id, active.content))
            }
            continue
        }

        components.append(.sourceRound(round.id, input.originalText(for: round)))
    }

    if let pendingPrompt = input.pendingUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
       !pendingPrompt.isEmpty {
        components.append(.pendingUserPrompt(pendingPrompt))
    }

    return AssembledModelInput(components: components)
}
```

Required assembly outcomes:

- Original-only conversation emits original user and assistant text in round order.
- Manual edit emits edited content instead of the edited segment.
- Exclusion emits no text for that round but keeps an `.excluded` component for traceability.
- Joined compression emits once at the first covered round and suppresses later covered rounds.
- Failed and tombstoned versions are ignored.
- The same input state always produces byte-identical output text.

### Budget Gate Contract

`ContextBudgetProvider` must provide evidence, not guesses.

```swift
public protocol ContextBudgetProvider: Sendable {
    func measure(_ request: ContextBudgetRequest) async -> ContextBudgetSnapshot
}

public struct ContextBudgetRequest: Equatable, Sendable {
    public var modelName: String?
    public var assembledInput: String
    public var reservedOutputTokens: Int
    public var workingDirectoryURL: URL
}
```

Policy:

- `.hardLimit` blocks send.
- `.warning` and `.notice` do not block send.
- `.unknown` does not block send by itself, but the UI must say the budget is unknown.
- If the provider has explicit evidence that assembled input exceeds usable input tokens, it must return `.hardLimit`.
- System compression uses the same assembled input that triggered `.hardLimit`; it must not silently choose a different source set.

### Compression Execution Contract

`CompressionExecutionProvider` is replaceable. The first implementation uses current Codex CLI through `ExecutionEngine`; future replacement should implement the same protocol.

```swift
public protocol CompressionExecutionProvider: Sendable {
    func startCompression(
        request: CompressionExecutionRequest,
        onFinish: @escaping @Sendable (CompressionExecutionResult) -> Void
    ) -> (any ExecutionHandle)?
}
```

Provider output rules:

- Success requires non-empty output.
- Only final compression text becomes `CompressionVersion.content`.
- Provider events, intermediate logs, and command output are not appended to `ConversationSession.events`.
- Failure creates a failed compression version with source mappings and error text.
- Cancellation creates a failed compression version only if the provider returned enough metadata to explain the attempt; otherwise it should leave active lineage unchanged and surface a UI error.

### Workbench State Contract

`WorkbenchSnapshot` should expose enough state for SwiftUI to render without querying repositories.

```swift
public struct WorkbenchContextCompressionState: Equatable, Sendable {
    public var rounds: [CompressionRoundPresentation]
    public var selectedRange: CompressionRoundRangeSelection?
    public var inspector: CompressionInspectorState?
    public var budget: ContextBudgetSnapshot?
    public var sendBlockReason: String?
    public var canRunSystemCompression: Bool
    public var activeOperation: CompressionOperationState?
    public var modelInputPreview: String?
}
```

Store action rules:

- UI can request an action; store/service decide whether it is valid.
- Store refreshes compression state after every successful action.
- Store refreshes budget after assembly changes and before send.
- Send button reads `snapshot.canSubmitPrompt` plus `compression.sendBlockReason`.
- System compression button appears only when `sendBlockReason == "需要压缩后继续"` and the conversation is not running.

### UI Contract

The main timeline is source-first:

- Original source text remains the default visual object.
- Active compression status is shown as a boundary/marker overlay.
- Excluded source text is dimmed and marked `已排除模型上下文`.
- Failed compression does not dim source text; it shows `压缩失败` in history/marker.
- Joined compression shows relationship hints with adjacent covered blocks.
- Full history lives in the right inspector.
- Model input preview shows only final assembled text.

Interaction entry points:

- Segment marker click: quick popover.
- `查看完整历史`: opens inspector.
- Round/range selection: shows contextual action bar.
- Inspector actions: edit, continue compression, rollback, exclude, restore original, preview.
- Composer hard limit: shows disabled send reason plus `交付系统完成压缩`.

### Archive Contract

Archive output should have stable sections:

```markdown
## Conversation

<existing original transcript rendering>

## Context Compression

### Active Model Input At Archive Time

<assembled text>

### Rounds

<round source mappings>

### Versions

<linear history, failed attempts, tombstones, provider metadata>

### Lineage

<parent-child and joined source relationships>
```

Archive search uses original transcript text only. Do not index compressed output as the primary searchable body.

## Phasing And Commit Strategy

Commit after each task or tightly coupled task pair:

- Task 1: `feat: add context compression models`
- Task 2-3: `feat: persist context compression state`
- Task 4-6: `feat: assemble active context compression lineage`
- Task 7-9: `feat: add context compression providers and service`
- Task 10: `feat: wire context compression into workbench state`
- Task 11-15: split into UI commits by visible surface
- Task 16: `feat: archive context compression lineage`
- Task 17-18: `chore: retire legacy compression snapshots`

Do not batch the whole implementation into one commit. This feature is too central and too risky for a monolithic diff.

## Implementation Tasks

### Task 1: Add Core Compression Models

**Files:**
- Create: `Sources/CodexPlusCore/ContextCompression/ContextCompressionModels.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/ContextCompressionModelTests.swift`

**Purpose:** Establish stable Swift types before persistence, assembly, and UI are built.

- [ ] Add model tests for operation/status decoding, active/non-active rules, and empty manual edit behavior.
- [ ] Create `CompressionRound`, `CompressionRoundEvent`, `CompressionSegmentKind`, `CompressionVersion`, `CompressionVersionOperation`, `CompressionVersionStatus`, `CompressionVersionSource`, `CompressionLineageEdge`, `CompressionActiveVersion`, `CompressionInputRecord`, `CompressionTombstone`, and `AssembledModelInput`.
- [ ] Add computed helpers:
  - `CompressionVersion.canBecomeActive`
  - `CompressionVersion.isReplacement`
  - `CompressionVersion.isVisibleInNormalHistory`
  - `CompressionVersionOperation.requiresInputRecord`
- [ ] Represent manual edit empty content as an empty `String`; represent exclusion as operation `.exclude`.
- [ ] Run `swift test --filter ContextCompressionModelTests`.

Expected result:

```text
Test Suite 'ContextCompressionModelTests' passed
```

### Task 2: Add SQLite Schema Version 4

**Files:**
- Modify: `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/ContextCompressionPersistenceTests.swift`

**Purpose:** Add dedicated tables without relying on memory cards.

- [ ] Write a schema test that migrates an empty database and verifies `PRAGMA user_version` is `4`.
- [ ] Write table-existence tests for:
  - `compression_rounds`
  - `compression_round_events`
  - `compression_versions`
  - `compression_version_sources`
  - `compression_lineage_edges`
  - `compression_active_versions`
  - `compression_inputs`
  - `compression_tombstones`
- [ ] Bump `CodexPlusSchema.version` from `3` to `4`.
- [ ] Add `CREATE TABLE IF NOT EXISTS` statements with foreign keys to `conversations`, `conversation_events`, and compression tables.
- [ ] Add uniqueness constraints:
  - `(conversation_id, round_index)` for rounds
  - `(round_id, event_id)` for round events
  - `(conversation_id, round_id)` for active round versions where applicable
  - `(parent_version_id, child_version_id, edge_kind)` for lineage edges
- [ ] Add indexes for conversation load and source lookup:
  - `compression_rounds(conversation_id, round_index)`
  - `compression_round_events(round_id, ordinal)`
  - `compression_versions(conversation_id, created_at)`
  - `compression_active_versions(conversation_id)`
  - `compression_version_sources(version_id, ordinal)`
- [ ] Run `swift test --filter ContextCompressionPersistenceTests`.

Expected result:

```text
Test Suite 'ContextCompressionPersistenceTests' passed
```

### Task 3: Add Repository Contract And SQLite Persistence

**Files:**
- Create: `Sources/CodexPlusCore/ContextCompression/ContextCompressionRepository.swift`
- Modify: `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
- Modify: `Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift`
- Extend tests: `Tests/CodexPlusCoreXCTests/ContextCompressionPersistenceTests.swift`

**Purpose:** Make compression state loadable independently from conversation events.

- [ ] Add `ContextCompressionRepository` protocol with round, version, source, lineage, active selection, input, and tombstone methods.
- [ ] Update `CodexPlusRepository` to conform to `ContextCompressionRepository`.
- [ ] Add default throwing implementations to the repository extension, matching the pattern used for prompt templates.
- [ ] Implement SQLite methods in `SQLiteCodexPlusRepository`. Keep helper functions local to `CodexPlusRepository.swift` if they need existing private row parsers.
- [ ] Forward all new calls through `SQLiteCodexPlusStore`.
- [ ] Write round-trip tests for:
  - saving and loading rounds with events
  - saving original and manual edit versions
  - saving compression input snapshots
  - setting and replacing active versions
  - tombstoning a branch
  - failed version persistence
- [ ] Run `swift test --filter ContextCompressionPersistenceTests`.

Expected result:

```text
Test Suite 'ContextCompressionPersistenceTests' passed
```

### Task 4: Build Dialogue Rounds From Conversation Events

**Files:**
- Create: `Sources/CodexPlusCore/ContextCompression/ConversationRoundBuilder.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/ConversationRoundBuilderTests.swift`

**Purpose:** Convert stored events into stable round boundaries.

- [ ] Write tests for a simple `user -> assistant` conversation.
- [ ] Write tests for multiple assistant/tool/status/error events after one user prompt.
- [ ] Write tests for a user prompt with no AI output after a failed or interrupted run.
- [ ] Write tests proving the next user prompt starts the next round.
- [ ] Implement `ConversationRoundBuilder.buildRounds(conversation:)`.
- [ ] Use user prompt events as round starts.
- [ ] Put all following non-user events into the AI bucket until the next user prompt.
- [ ] Include technical events in the AI bucket because the user approved tracking AI-side run lifecycle details.
- [ ] Return deterministic `roundIndex` values based on timeline order.
- [ ] Run `swift test --filter ConversationRoundBuilderTests`.

Expected result:

```text
Test Suite 'ConversationRoundBuilderTests' passed
```

### Task 5: Persist And Refresh Rounds On Conversation Save

**Files:**
- Modify: `Sources/CodexPlusCore/WorkbenchStore.swift`
- Modify: `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
- Extend tests: `Tests/CodexPlusCoreXCTests/WorkbenchContextCompressionTests.swift`

**Purpose:** Ensure every conversation has round records before compression actions appear.

- [ ] Add a repository method that upserts round definitions for a conversation from `ConversationRoundBuilder`.
- [ ] Call the sync method after conversation creation, follow-up user prompts, assistant event appends, run completion, and restored archived conversation load where applicable.
- [ ] Avoid creating duplicate rounds when `saveConversation` runs repeatedly.
- [ ] Add tests that create a conversation, append a follow-up, and verify two persisted rounds.
- [ ] Add tests that a failed run still leaves a round with an empty AI bucket.
- [ ] Run `swift test --filter WorkbenchContextCompressionTests`.

Expected result:

```text
Test Suite 'WorkbenchContextCompressionTests' passed
```

### Task 6: Replace Snapshot Assembler With Active-Lineage Assembly

**Files:**
- Create: `Sources/CodexPlusCore/ContextCompression/ContextCompressionAssemblerV2.swift`
- Keep temporarily: `Sources/CodexPlusCore/ConversationContextCompressionAssembler.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/ContextCompressionAssemblerTests.swift`

**Purpose:** Compute the exact model input sent to LLM from source events plus active compression versions.

- [ ] Write assembly tests for original-only conversation.
- [ ] Write tests for one manual edit replacing one user segment.
- [ ] Write tests for one AI segment shortened to one sentence.
- [ ] Write tests for exclusion emitting no text but preserving source metadata.
- [ ] Write tests for joined compression replacing multiple adjacent rounds.
- [ ] Write tests for `ABCDEFG -> AMCDENG -> AODENG -> APENG` and verify only `APENG` appears in assembled text.
- [ ] Write tests that failed and tombstoned versions are ignored.
- [ ] Implement an assembler input struct containing source conversation, rounds, versions, sources, active versions, and optional pending user prompt.
- [ ] Implement deterministic round-order traversal.
- [ ] Emit original user and AI text when a round has no active replacement.
- [ ] Emit active replacement content when a round or range has an active replacement.
- [ ] Suppress all source rounds covered by an active joined compression range.
- [ ] Append the pending user prompt at the end for budget checks and actual send.
- [ ] Return both `text` and `components` so the UI can trace which source rounds produced each assembled block.
- [ ] Run `swift test --filter ContextCompressionAssemblerTests`.

Expected result:

```text
Test Suite 'ContextCompressionAssemblerTests' passed
```

### Task 7: Add Budget Provider Abstraction

**Files:**
- Create: `Sources/CodexPlusCore/ContextCompression/ContextBudgetProvider.swift`
- Create: `Sources/CodexPlusCore/ContextCompression/CodexCLIContextBudgetProvider.swift`
- Create: `Sources/CodexPlusCore/ContextCompression/ModelContextWindowRegistry.swift`
- Create: `Sources/CodexPlusCore/ContextCompression/ModelInputTokenCounter.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/ContextBudgetProviderTests.swift`

**Purpose:** Gate send behavior using real provider-supplied context information through a replaceable interface.

- [ ] Define `ContextBudgetProvider` with an async or callback-based measurement method.
- [ ] Define `ContextBudgetSnapshot` with:
  - `modelName`
  - `contextWindowTokens`
  - `assembledInputTokens`
  - `reservedOutputTokens`
  - `usableInputTokens`
  - `usageRatio`
  - `state`
  - `measurementSource`
  - `measuredAt`
- [ ] Define states: `.safe`, `.notice`, `.warning`, `.hardLimit`, `.unknown`.
- [ ] Add a `ContextBudgetPolicy` that maps context-window class to dynamic thresholds.
- [ ] Add `ModelContextWindowRegistry` with explicit model profiles returned from the active Codex CLI/model configuration path.
- [ ] Add `ModelInputTokenCounter` as a replaceable token-counting interface.
- [ ] Implement `CodexCLIContextBudgetProvider` so the first provider reads the active model identity, resolves the model context window, counts assembled input tokens through the token counter, and reports a structured `measurementSource`.
- [ ] Do not mark `.unknown` as `.safe`. Unknown budget should allow normal send only when no hard-limit evidence exists, and the UI must label it as unknown.
- [ ] Do not use character count or event count as the primary budget signal.
- [ ] Add unit tests for small, medium, large, and unknown windows.
- [ ] Add tests that a future replacement provider can satisfy `ContextBudgetProvider` without changing `WorkbenchStore`.
- [ ] Run `swift test --filter ContextBudgetProviderTests`.

Expected result:

```text
Test Suite 'ContextBudgetProviderTests' passed
```

### Task 8: Add Compression Execution Provider And Codex CLI Adapter

**Files:**
- Create: `Sources/CodexPlusCore/ContextCompression/CompressionExecutionProvider.swift`
- Create: `Sources/CodexPlusCore/ContextCompression/CodexCLICompressionExecutionProvider.swift`
- Create: `Sources/CodexPlusCore/ContextCompression/ContextCompressionOutputCollector.swift`
- Modify: `Sources/CodexPlusCore/PromptTemplates/PromptTemplateModels.swift`
- Modify: `Sources/CodexPlusCore/PromptTemplates/PromptTemplateLibrary.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/ContextCompressionServiceTests.swift`

**Purpose:** Run compression without coupling business logic to the current CLI implementation.

- [ ] Add a `PromptTemplateType.contextCompression` case if the existing type does not already expose it under a stable name.
- [ ] Ensure built-in compression template is present and can be selected as the default compression template.
- [ ] Define request/response structs:
  - `CompressionExecutionRequest`
  - `CompressionExecutionResult`
  - `CompressionExecutionFailure`
- [ ] Include source assembled text, selected template, optional user instruction, provider metadata, and working directory in the request.
- [ ] Implement `CodexCLICompressionExecutionProvider` using `ExecutionEngine.start`, following `PromptOptimizationService` collector style.
- [ ] Collect only `.agentMessage` text as compression output.
- [ ] Do not append compression run events to `ConversationSession.events`.
- [ ] Return failure with stderr or a localized empty-output message.
- [ ] Add fake provider tests for success, failure, empty output, and stored input metadata.
- [ ] Run `swift test --filter ContextCompressionServiceTests`.

Expected result:

```text
Test Suite 'ContextCompressionServiceTests' passed
```

### Task 9: Add Context Compression Service

**Files:**
- Create: `Sources/CodexPlusCore/ContextCompression/ContextCompressionService.swift`
- Extend tests: `Tests/CodexPlusCoreXCTests/ContextCompressionServiceTests.swift`

**Purpose:** Centralize user operations so Workbench UI does not manipulate lineage directly.

- [ ] Implement `createManualEdit(conversationID:roundID:segmentKind:content:)`.
- [ ] Implement `excludeRound(conversationID:roundID:)`.
- [ ] Implement `restoreOriginal(conversationID:roundID:)`.
- [ ] Implement `compressRange(conversationID:roundIDs:mode:templateID:userInstruction:)`.
- [ ] Implement `systemCompress(conversationID:assembledInput:budgetSnapshot:)`.
- [ ] Implement `rollback(toVersionID:)` as a new active branch plus tombstones for replaced downstream branch.
- [ ] Implement `continueCompress(versionID:mode:templateID:userInstruction:)`.
- [ ] Validate manual range continuity and reject non-contiguous ranges.
- [ ] Persist failed compression versions with error details and no active selection.
- [ ] Persist successful compression input records before activating the result.
- [ ] Activate successful results atomically with version/source/lineage writes.
- [ ] Add tests covering every operation and failure invariant.
- [ ] Run `swift test --filter ContextCompressionServiceTests`.

Expected result:

```text
Test Suite 'ContextCompressionServiceTests' passed
```

### Task 10: Wire Workbench Store State And Actions

**Files:**
- Modify: `Sources/CodexPlusCore/WorkbenchModels.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchStore.swift`
- Modify: `Sources/CodexPlusCore/ConversationRunOrchestrator.swift`
- Modify: `Sources/CodexPlusApp/AppDelegate.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/WorkbenchContextCompressionTests.swift`

**Purpose:** Make compression state part of the main workbench snapshot.

- [ ] Add `WorkbenchContextCompressionState` containing rounds, visible markers, selected round/range, inspector state, budget snapshot, send-block reason, active operation state, and assembled preview.
- [ ] Add `compression` to `WorkbenchSnapshot`.
- [ ] Initialize `ContextCompressionService`, `ContextBudgetProvider`, and `CompressionExecutionProvider` in `AppDelegate.makeRuntime()`.
- [ ] Inject compression dependencies into `WorkbenchStore`.
- [ ] Load compression state in `refreshSnapshot()` for the active conversation.
- [ ] Add store actions for selecting a range, opening history, saving manual edit, excluding, restoring original, compressing, continuing compression, rollback, opening model input preview, and closing inspector/sheets.
- [ ] Before `sendFollowUp`, assemble model input with the pending prompt and measure budget.
- [ ] If budget state is `.hardLimit`, keep send disabled and set reason to `需要压缩后继续`.
- [ ] Add a system compression action that uses the same assembled model input and stores the result as a normal compression version.
- [ ] Start normal Codex runs with assembled active-lineage text, not just raw prompt, when the conversation has compression state.
- [ ] Add tests that send is blocked at hard limit and re-enabled after successful system compression.
- [ ] Run `swift test --filter WorkbenchContextCompressionTests`.

Expected result:

```text
Test Suite 'WorkbenchContextCompressionTests' passed
```

### Task 11: Update Timeline Presentation Models

**Files:**
- Modify: `Sources/CodexPlusCore/ConversationTimelineBuilder.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift`
- Modify: `Sources/CodexPlusApp/Views/ConversationEventRow.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/ContextCompressionAssemblerTests.swift`

**Purpose:** Keep original records visible while showing active model-input status.

- [ ] Add compression-aware timeline presentation structs:
  - `ConversationRoundPresentation`
  - `CompressionBoundaryPresentation`
  - `CompressionStatusPresentation`
  - `CompressionJoinedRelationshipPresentation`
- [ ] Change timeline builder input from old snapshot list to new compression presentation state.
- [ ] Preserve original event rows as the default visible rows.
- [ ] Add start and end boundary markers for edited, compressed, joined, failed, and excluded ranges.
- [ ] Add status labels: `原文发送`, `已修订`, `已压缩`, `拼接压缩`, `已排除模型上下文`, `压缩失败`.
- [ ] Dim excluded source rows without removing them.
- [ ] Highlight source rows when the inspector selects a version.
- [ ] Keep the old `ConversationContextCompressionAssembler` and `ConversationCompressionSnapshotRow` unused until a cleanup task removes them after feature verification.
- [ ] Run `swift test --filter ContextCompressionAssemblerTests`.

Expected result:

```text
Test Suite 'ContextCompressionAssemblerTests' passed
```

### Task 12: Add Timeline Marker, Popover, And Inspector UI

**Files:**
- Create: `Sources/CodexPlusApp/ContextCompression/CompressionRangeMarkerView.swift`
- Create: `Sources/CodexPlusApp/ContextCompression/CompressionStatusPopover.swift`
- Create: `Sources/CodexPlusApp/ContextCompression/CompressionHistoryInspectorView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`

**Purpose:** Give users direct, visual, recoverable control over each compression version.

- [ ] Add a compact boundary marker view with native materials, subtle hairline borders, and quiet status text.
- [ ] Add a popover from status marker click/hover summary. Include source range, active version type, latest operation, and `查看完整历史`.
- [ ] Add a right inspector with linear-first version history.
- [ ] In the inspector, show source rounds, active version, failed attempts, tombstoned branch note, compression input summary, provider metadata, and joined relationships.
- [ ] Add contextual actions for edit, compress, continue compression, exclude, restore original, rollback, and model input preview.
- [ ] Add joined-compression relationship hints when the selected block is related to adjacent blocks.
- [ ] Use graphical connectors in the inspector, not a graph-first canvas.
- [ ] Keep nested cards out of the inspector. Use full-height panes, grouped rows, and native controls.
- [ ] Verify text does not overlap at narrow panel widths.
- [ ] Build with `swift build`.

Expected result:

```text
Build complete!
```

### Task 13: Add Manual Edit And Range Compression Controls

**Files:**
- Create: `Sources/CodexPlusApp/ContextCompression/CompressionEditDialog.swift`
- Create: `Sources/CodexPlusApp/ContextCompression/CompressionRangeActionBar.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`

**Purpose:** Let users intentionally reduce context with exact control.

- [ ] Add range selection that snaps to complete dialogue rounds.
- [ ] Reject non-contiguous ranges in the store and do not expose non-contiguous selection in UI.
- [ ] Add a contextual action bar for selected ranges.
- [ ] Add actions: `不压缩`, `默认压缩`, `自定义压缩`.
- [ ] For custom compression, load compression prompt templates, allow template selection, and allow one-time user instruction.
- [ ] Store the one-time instruction only in `compression_inputs`, not normal conversation history.
- [ ] Add edit dialog for one user segment or one AI segment.
- [ ] In edit dialog, allow empty content and save as a manual edit version.
- [ ] Add optional diff button only if it can be implemented without blocking the first complete flow.
- [ ] Build with `swift build`.

Expected result:

```text
Build complete!
```

### Task 14: Add Composer Budget Gate And System Compression

**Files:**
- Create: `Sources/CodexPlusApp/ContextCompression/ContextBudgetBadge.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchModels.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchStore.swift`

**Purpose:** Make hard context limits actionable.

- [ ] Add a budget badge near the send control.
- [ ] Show safe/notice/warning states without blocking send.
- [ ] Disable send at hard limit.
- [ ] Display `需要压缩后继续` as the disabled-send reason.
- [ ] Show `交付系统完成压缩` next to the send button at hard limit.
- [ ] Wire the system compression button to `WorkbenchStore.systemCompressActiveConversation()`.
- [ ] After system compression succeeds, refresh active lineage, budget state, and timeline markers.
- [ ] If system compression fails, keep send disabled and show the failed attempt in history.
- [ ] Build with `swift build`.

Expected result:

```text
Build complete!
```

### Task 15: Add Model Input Preview

**Files:**
- Create: `Sources/CodexPlusApp/ContextCompression/ModelInputPreviewSheet.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchStore.swift`

**Purpose:** Let users inspect exactly what will be sent to the model.

- [ ] Add a sheet showing only the final assembled model-input text.
- [ ] Do not show lineage graph, source mapping, or version metadata in this preview. Those stay in the inspector.
- [ ] Add copy button and close button.
- [ ] Ensure preview text is produced by the same assembler path used before send.
- [ ] Add a test that preview text equals send text for the same pending prompt.
- [ ] Run `swift test --filter WorkbenchContextCompressionTests`.

Expected result:

```text
Test Suite 'WorkbenchContextCompressionTests' passed
```

### Task 16: Update Archive Export And Search Rules

**Files:**
- Modify: `Sources/CodexPlusCore/Archive/ConversationArchiveMarkdownRenderer.swift`
- Modify: `Sources/CodexPlusCore/Archive/ArchiveSearchService.swift`
- Create tests: `Tests/CodexPlusCoreXCTests/ArchiveContextCompressionTests.swift`

**Purpose:** Preserve compression traceability in archives while keeping search source-based.

- [ ] Extend archive rendering input to include compression records for the conversation.
- [ ] Export original conversation events as today.
- [ ] Add a compression section with active chain, version history, failed attempts, tombstones, source mappings, joined relationships, provider metadata, and final active assembled text at archive time.
- [ ] Keep archive search `searchable_text` based on original source conversation text only.
- [ ] Add tests that archived markdown contains compression metadata.
- [ ] Add tests that archive search finds original source text and does not rely on compressed text.
- [ ] Run `swift test --filter ArchiveContextCompressionTests`.

Expected result:

```text
Test Suite 'ArchiveContextCompressionTests' passed
```

### Task 17: Remove Or Fence Old Experimental Snapshot Path

**Files:**
- Modify or delete after verification:
  - `Sources/CodexPlusCore/ContextCompressionPersistence.swift`
  - `Sources/CodexPlusCore/ConversationContextCompressionAssembler.swift`
  - old snapshot-specific cases in `Sources/CodexPlusCore/ConversationTimelineBuilder.swift`
  - old snapshot row in `Sources/CodexPlusApp/Views/ConversationEventRow.swift`

**Purpose:** Prevent two incompatible compression models from coexisting.

- [ ] Search all references with `rg -n "ConversationContextCompression|CompressionSnapshot|compressionSnapshots" Sources Tests`.
- [ ] If no runtime path uses old snapshot types, delete old files and old timeline cases.
- [ ] If a test still needs old behavior, rewrite it against the new round/version model.
- [ ] Confirm memory-card repository methods are no longer used for context compression.
- [ ] Keep generic memory-card features intact.
- [ ] Run `swift test`.

Expected result:

```text
Test Suite 'All tests' passed
```

### Task 18: End-To-End Verification And Manual QA

**Files:**
- Create: `docs/superpowers/manual-tests/2026-07-09-context-compression.md`
- Update any changed source files from previous tasks.

**Purpose:** Verify the feature behaves correctly in the actual macOS UI.

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Launch the app manually or through the existing local workflow.
- [ ] Create a conversation with at least four user/AI rounds.
- [ ] Manually edit one AI segment down to one sentence.
- [ ] Compress two adjacent rounds with the default template.
- [ ] Compress the result again to create a joined lineage.
- [ ] Exclude one round and verify it is dimmed and marked `已排除模型上下文`.
- [ ] Open the inspector and verify full version history, input record, provider metadata, rollback, and joined relationship hints.
- [ ] Open model input preview and verify it shows only assembled text.
- [ ] Force or simulate hard budget state and verify send is disabled with `需要压缩后继续`.
- [ ] Run system compression and verify `交付系统完成压缩` creates a version-controlled result.
- [ ] Archive the conversation and verify original events plus compression metadata are present.
- [ ] Record QA results in the manual test file.

Expected result:

```text
swift test passed
swift build passed
manual test notes saved
```

## Integration Notes

- `AppDelegate.makeRuntime()` currently creates `SQLiteCodexPlusRepository` and `CodexCLIEngine`. Add compression services there so all runtime paths share the same repository and execution engine.
- `PromptOptimizationService` is the reference pattern for transient Codex CLI work that collects `.agentMessage` output without adding events to the normal timeline.
- `WorkbenchComposerView` currently drives send disabled state from `snapshot.canSubmitPrompt`. Extend the snapshot with a send-block reason and a system-compression action instead of adding local UI-only logic.
- `ConversationTimelineBuilder` already has an old compression snapshot path. Treat it as a compatibility clue, not the final design.
- `SQLiteCodexPlusStore` forwards repository calls. Any new repository protocol methods must be forwarded there as well.
- Because the existing schema uses idempotent table creation, version 4 should continue to create all current tables and then set `PRAGMA user_version = 4`.

## Risks And Guardrails

- **Risk:** Model input preview and send diverge.
  - **Guardrail:** A single assembler method returns text for both paths; Workbench tests compare preview and send input.
- **Risk:** Joined compression duplicates or drops rounds.
  - **Guardrail:** Assembler tests cover adjacent ranges and APENG-style lineage.
- **Risk:** Failed compression accidentally becomes active.
  - **Guardrail:** `CompressionVersion.canBecomeActive` and service activation tests reject failed/tombstoned versions.
- **Risk:** UI hides original source text too aggressively.
  - **Guardrail:** Timeline presentation keeps original rows visible by default; excluded rows are dimmed, not removed.
- **Risk:** Future Codex CLI replacement forces a rewrite.
  - **Guardrail:** Workbench and service depend on `CompressionExecutionProvider` and `ContextBudgetProvider`, not `CodexCLIEngine`.
- **Risk:** Archive search changes user expectations.
  - **Guardrail:** Search indexes original text only; compressed lineage is exported but not primary search content.

## Final Verification

Run these commands before marking the implementation complete:

```bash
swift test
swift build
rg -n "ConversationContextCompression|CompressionSnapshot|compressionSnapshots" Sources Tests
```

Expected final state:

```text
swift test passed
swift build passed
no old snapshot runtime references remain, unless explicitly documented as compatibility-only
```

Plan complete and saved to `docs/superpowers/plans/2026-07-09-context-compression.md`.

Two execution options:

1. Subagent-Driven Execution: use parallel workers for persistence/core, provider/service, and UI tasks, then integrate in Workbench.
2. Inline Execution: implement sequentially in this session with checkpoints after each major layer.

Recommended: Subagent-Driven Execution, because persistence/core, service/provider, and UI can be developed with limited overlap once Task 1 to Task 3 define the shared contracts.
