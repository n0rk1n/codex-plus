# Codex Plus V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved V1 Codex Plus floating workbench: project/conversation switching, Codex CLI execution, complete local persistence, archive/search/reopen, and memory-data foundations.

**Architecture:** Keep the Swift package split into `CodexPlusCore` for policies, domain models, persistence, archive/search, and execution orchestration, and `CodexPlusApp` for AppKit window behavior plus SwiftUI views. Replace the old dashboard/side-panel product flow with one V1 `WorkbenchPanelController` and one `WorkbenchView`, while reusing proven low-level pieces such as `GlassPanel`, `HotKeyController`, `ProcessCodexRunner`, `CodexEventParser`, and `LiquidGlassContainer`.

**Tech Stack:** Swift 6.2 package, macOS 26, SwiftUI, AppKit, SQLite C library, local Markdown/attachment files, executable test target `CodexPlusCoreTests`.

## Global Constraints

- V1 is a native macOS Codex enhancement shell.
- The package platform floor remains `.macOS(.v26)`.
- Codex CLI is the only V1 execution engine implementation.
- The execution engine boundary must allow future engines without changing archive or UI code.
- SQLite is the source of truth for projects, conversations, events, archive index, memory cards, memory sources, and attachments.
- Markdown archive files are readable exports, not the source of truth for rebuilding UI.
- Complete conversations must be archived and searchable; summaries alone are not enough.
- Memory card injection, automatic extraction, review board, STAR workflow, and recommendation are not V1 UI requirements.
- Memory card tables and CRUD-capable data-layer foundations must exist in V1.
- Global app data is the default storage location; project-local `.codex-plus/` directories are created only after an explicit user choice or export.
- The V1 main UI is the floating workbench from `docs/superpowers/prototypes/codex-plus-v1-main-workbench-design.png`.
- The floating workbench has no traditional titlebar.
- Clicking outside the unpinned floating workbench hides the window but never stops a running task.
- The top workbench only shows `新对话` and `已归档`; archive search lives inside the archived view.
- Archived conversations do not appear in active project cards.
- Running tasks cannot accept a new user prompt; the single composer action shows stop while running and send only after the task is terminal.
- The bottom status bar only shows global technical state: Codex CLI, SQLite, and archive index.

---

## Scope Check

The spec covers several subsystems, but they are tightly coupled into one V1 vertical product: workbench UI, execution, persistence, and archive/search. This plan keeps them in one ordered plan because each task creates a testable layer used by the next task. Do not start implementation until this plan is reviewed and accepted.

## File Structure

- `Package.swift`: add SQLite linker settings to `CodexPlusCore` if required by the local SDK.
- `Sources/CodexPlusCore/WorkbenchModels.swift`: project-card, composer, status-bar, archive/search, and workbench snapshot value types.
- `Sources/CodexPlusCore/WorkbenchProjection.swift`: pure functions that turn persisted projects/conversations into top-card and status-bar view models.
- `Sources/CodexPlusCore/WorkbenchInteractionPolicies.swift`: pure policies for composer action, outside-click dismissal, archive confirmation, and visible conversation selection.
- `Sources/CodexPlusCore/Persistence/SQLiteDatabase.swift`: minimal SQLite wrapper for opening databases, executing SQL, binding values, and reading rows.
- `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift`: schema creation and migration versioning.
- `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`: repository protocol and SQLite implementation for projects, conversations, events, archive index, memory cards, sources, and attachments.
- `Sources/CodexPlusCore/Archive/MarkdownArchiveRenderer.swift`: render a complete conversation archive to Markdown.
- `Sources/CodexPlusCore/Archive/ArchiveSearchService.swift`: build and search archive records from persisted events.
- `Sources/CodexPlusCore/Execution/ExecutionEngine.swift`: engine protocol and engine event/result types.
- `Sources/CodexPlusCore/Execution/CodexCLIEngine.swift`: adapter that wraps existing `ProcessCodexRunner`.
- `Sources/CodexPlusCore/WorkbenchStore.swift`: main actor state store that coordinates repository, engine, archive service, and UI snapshots.
- `Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift`: AppKit owner for the floating workbench panel, outside-click hiding, pin behavior, and content refresh.
- `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`: root SwiftUI view matching the approved design image.
- `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift`: top project cards.
- `Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift`: chat header, event log, and archive/search read-only state.
- `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift`: running/terminal single-action composer.
- `Sources/CodexPlusApp/Workbench/WorkbenchStatusBarView.swift`: Codex CLI, SQLite, archive-index technical status.
- `Sources/CodexPlusApp/Workbench/ArchivedConversationView.swift`: archived-search page and reopened archived conversation view.
- `Sources/CodexPlusApp/AppDelegate.swift`: create repository, engine, store, and workbench coordinator.
- `Sources/CodexPlusApp/WindowCoordinator.swift`: replace dashboard/side-panel routing with V1 workbench routing, or remove after `WorkbenchPanelController` takes over all calls.
- `Tests/CodexPlusCoreTests/WorkbenchProjectionTests.swift`: test top-card and composer policies.
- `Tests/CodexPlusCoreTests/PersistenceTests.swift`: test SQLite schema and repository round trips.
- `Tests/CodexPlusCoreTests/ArchiveTests.swift`: test Markdown rendering, archive index creation, and search.
- `Tests/CodexPlusCoreTests/ExecutionEngineTests.swift`: test `CodexCLIEngine` behavior with a fake runner.
- `Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift`: test run lifecycle, stop behavior, archive-confirm behavior, and reopen archive.
- `Tests/CodexPlusCoreTests/main.swift`: call new test functions before the final failure report.
- `docs/superpowers/manual-tests/2026-07-05-codex-plus-v1.md`: manual smoke checklist for GUI behavior.

---

### Task 1: Workbench Projection And Interaction Policies

**Files:**
- Create: `Sources/CodexPlusCore/WorkbenchModels.swift`
- Create: `Sources/CodexPlusCore/WorkbenchProjection.swift`
- Create: `Sources/CodexPlusCore/WorkbenchInteractionPolicies.swift`
- Create: `Tests/CodexPlusCoreTests/WorkbenchProjectionTests.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Produces: `WorkbenchProjectCard: Equatable, Identifiable, Sendable`
- Produces: `WorkbenchConversationSummary: Equatable, Identifiable, Sendable`
- Produces: `WorkbenchStatusBarState: Equatable, Sendable`
- Produces: `WorkbenchProjection.projectCards(workspaces:conversations:activeWorkspaceID:activeConversationID:) -> [WorkbenchProjectCard]`
- Produces: `WorkbenchInteractionPolicies.composerAction(for:) -> WorkbenchComposerAction`
- Produces: `WorkbenchInteractionPolicies.shouldHideForOutsideClick(isPinned:clickPoint:panelFrame:) -> Bool`
- Produces: `WorkbenchInteractionPolicies.requiresStopBeforeArchive(state:) -> Bool`

- [ ] **Step 1: Write failing projection tests**

Create `Tests/CodexPlusCoreTests/WorkbenchProjectionTests.swift`:

```swift
import Foundation
import CoreGraphics
import CodexPlusCore

@MainActor
func runWorkbenchProjectionTests() {
    let workspaceA = WorkspaceSessionGroup(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        path: "/tmp/mft-project",
        displayName: "mft-project",
        conversationIDs: [],
        lastActivityAt: Date(timeIntervalSince1970: 10)
    )
    let workspaceBID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let conversationB1ID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBB01")!
    let conversationB2ID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBB02")!
    let archivedB3ID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBB03")!
    let workspaceB = WorkspaceSessionGroup(
        id: workspaceBID,
        path: "/tmp/codex-plus",
        displayName: "codex-plus",
        conversationIDs: [conversationB1ID, conversationB2ID, archivedB3ID],
        lastActivityAt: Date(timeIntervalSince1970: 20)
    )
    let conversations = [
        ConversationSession(
            id: conversationB1ID,
            title: "重设计 Codex 软件",
            prompt: "start",
            workspacePath: "/tmp/codex-plus",
            state: .running,
            lastActivityAt: Date(timeIntervalSince1970: 40)
        ),
        ConversationSession(
            id: conversationB2ID,
            title: "整理实现计划",
            prompt: "plan",
            workspacePath: "/tmp/codex-plus",
            state: .completed,
            lastActivityAt: Date(timeIntervalSince1970: 30)
        ),
        ConversationSession(
            id: archivedB3ID,
            title: "已归档旧会话",
            prompt: "archive",
            workspacePath: "/tmp/codex-plus",
            state: .completed,
            isArchived: true,
            lastActivityAt: Date(timeIntervalSince1970: 50)
        )
    ]

    let cards = WorkbenchProjection.projectCards(
        workspaces: [workspaceA, workspaceB],
        conversations: conversations,
        activeWorkspaceID: workspaceBID,
        activeConversationID: conversationB1ID
    )

    expect(cards.count == 2, "workbench projection creates one card per workspace")
    expect(cards[0].conversationTitle == "暂无对话", "empty workspace shows no conversation")
    expect(cards[0].visibleConversationCount == 0, "empty workspace visible count is zero")
    expect(cards[1].projectName == "codex-plus", "project card keeps workspace display name")
    expect(cards[1].conversationTitle == "重设计 Codex 软件", "active conversation is displayed first")
    expect(cards[1].visibleConversationCount == 2, "archived conversations are excluded from count")
    expect(cards[1].overflowCount == 2, "multiple visible conversations produce a dropdown count")
    expect(cards[1].isActive, "active workspace card is marked active")

    expect(
        WorkbenchInteractionPolicies.composerAction(for: .running) == .stop,
        "running conversation shows stop action"
    )
    expect(
        WorkbenchInteractionPolicies.composerAction(for: .completed) == .send,
        "completed conversation shows send action"
    )
    expect(
        WorkbenchInteractionPolicies.composerAction(for: .failed) == .send,
        "failed conversation shows send action"
    )
    expect(
        WorkbenchInteractionPolicies.shouldHideForOutsideClick(
            isPinned: false,
            clickPoint: CGPoint(x: 20, y: 20),
            panelFrame: CGRect(x: 100, y: 100, width: 800, height: 500)
        ),
        "unpinned workbench hides for outside click"
    )
    expect(
        !WorkbenchInteractionPolicies.shouldHideForOutsideClick(
            isPinned: true,
            clickPoint: CGPoint(x: 20, y: 20),
            panelFrame: CGRect(x: 100, y: 100, width: 800, height: 500)
        ),
        "pinned workbench ignores outside click"
    )
    expect(
        WorkbenchInteractionPolicies.requiresStopBeforeArchive(state: .running),
        "running conversation requires stop before archive"
    )
}
```

- [ ] **Step 2: Call the failing tests**

In `Tests/CodexPlusCoreTests/main.swift`, add this call before the final `if failures.isEmpty` block:

```swift
runWorkbenchProjectionTests()
```

- [ ] **Step 3: Run test and verify failure**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: build fails with missing symbols such as `WorkbenchProjection`, `WorkbenchInteractionPolicies`, and `WorkbenchComposerAction`.

- [ ] **Step 4: Add minimal workbench models**

Create `Sources/CodexPlusCore/WorkbenchModels.swift`:

```swift
import Foundation

public enum WorkbenchComposerAction: Equatable, Sendable {
    case send
    case stop
}

public struct WorkbenchProjectCard: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var projectName: String
    public var projectPath: String
    public var conversationID: UUID?
    public var conversationTitle: String
    public var conversationState: ConversationRunState?
    public var visibleConversationCount: Int
    public var overflowCount: Int?
    public var isActive: Bool

    public init(
        id: UUID,
        projectName: String,
        projectPath: String,
        conversationID: UUID?,
        conversationTitle: String,
        conversationState: ConversationRunState?,
        visibleConversationCount: Int,
        overflowCount: Int?,
        isActive: Bool
    ) {
        self.id = id
        self.projectName = projectName
        self.projectPath = projectPath
        self.conversationID = conversationID
        self.conversationTitle = conversationTitle
        self.conversationState = conversationState
        self.visibleConversationCount = visibleConversationCount
        self.overflowCount = overflowCount
        self.isActive = isActive
    }
}

public struct WorkbenchStatusBarState: Equatable, Sendable {
    public var codexCLIAvailable: Bool
    public var sqliteConnected: Bool
    public var archiveIndexState: String

    public init(codexCLIAvailable: Bool, sqliteConnected: Bool, archiveIndexState: String) {
        self.codexCLIAvailable = codexCLIAvailable
        self.sqliteConnected = sqliteConnected
        self.archiveIndexState = archiveIndexState
    }
}
```

- [ ] **Step 5: Add projection logic**

Create `Sources/CodexPlusCore/WorkbenchProjection.swift`:

```swift
import Foundation

public enum WorkbenchProjection {
    public static func projectCards(
        workspaces: [WorkspaceSessionGroup],
        conversations: [ConversationSession],
        activeWorkspaceID: UUID?,
        activeConversationID: UUID?
    ) -> [WorkbenchProjectCard] {
        workspaces.map { workspace in
            let visible = workspace.conversationIDs.compactMap { id in
                conversations.first { $0.id == id && !$0.isArchived }
            }
            let selected = visible.first { $0.id == activeConversationID } ?? visible.first
            let count = visible.count

            return WorkbenchProjectCard(
                id: workspace.id,
                projectName: workspace.displayName,
                projectPath: workspace.path,
                conversationID: selected?.id,
                conversationTitle: selected?.title ?? "暂无对话",
                conversationState: selected?.state,
                visibleConversationCount: count,
                overflowCount: count > 1 ? count : nil,
                isActive: workspace.id == activeWorkspaceID
            )
        }
    }
}
```

- [ ] **Step 6: Add interaction policies**

Create `Sources/CodexPlusCore/WorkbenchInteractionPolicies.swift`:

```swift
import CoreGraphics

public enum WorkbenchInteractionPolicies {
    public static func composerAction(for state: ConversationRunState?) -> WorkbenchComposerAction {
        state == .running ? .stop : .send
    }

    public static func shouldHideForOutsideClick(
        isPinned: Bool,
        clickPoint: CGPoint,
        panelFrame: CGRect
    ) -> Bool {
        !isPinned && !panelFrame.contains(clickPoint)
    }

    public static func requiresStopBeforeArchive(state: ConversationRunState) -> Bool {
        state == .running
    }
}
```

- [ ] **Step 7: Run tests**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: all tests pass, including `workbench projection`.

- [ ] **Step 8: Commit**

```bash
git add Sources/CodexPlusCore/WorkbenchModels.swift Sources/CodexPlusCore/WorkbenchProjection.swift Sources/CodexPlusCore/WorkbenchInteractionPolicies.swift Tests/CodexPlusCoreTests/WorkbenchProjectionTests.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: add workbench projection policies"
```

---

### Task 2: SQLite Schema And Repository Foundation

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CodexPlusCore/Persistence/SQLiteDatabase.swift`
- Create: `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift`
- Create: `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
- Create: `Tests/CodexPlusCoreTests/PersistenceTests.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Consumes: `ConversationSession`, `WorkspaceSessionGroup`, `ConversationDisplayEvent`
- Produces: `SQLiteDatabase(path:) throws`
- Produces: `CodexPlusSchema.migrate(_:) throws`
- Produces: `CodexPlusRepository` protocol
- Produces: `SQLiteCodexPlusRepository`

- [ ] **Step 1: Write failing persistence tests**

Create `Tests/CodexPlusCoreTests/PersistenceTests.swift`:

```swift
import Foundation
import CodexPlusCore

@MainActor
func runPersistenceTests() {
    let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-plus-\(UUID().uuidString).sqlite")

    do {
        let database = try SQLiteDatabase(path: dbURL.path)
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)

        let project = WorkspaceSessionGroup(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            path: "/tmp/codex-plus",
            displayName: "codex-plus",
            lastActivityAt: Date(timeIntervalSince1970: 10)
        )
        let conversation = ConversationSession(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "重设计 Codex 软件",
            prompt: "start",
            workspacePath: project.path,
            state: .completed,
            createdAt: Date(timeIntervalSince1970: 20),
            lastActivityAt: Date(timeIntervalSince1970: 30),
            events: [
                .userPrompt(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, text: "start"),
                .assistantMessage(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, text: "done")
            ]
        )

        try repository.saveProject(project)
        try repository.saveConversation(conversation, projectID: project.id)

        let loadedProjects = try repository.loadProjects()
        let loadedConversations = try repository.loadConversations()

        expect(loadedProjects == [project], "repository loads saved project")
        expect(loadedConversations.count == 1, "repository loads one saved conversation")
        expect(loadedConversations[0].id == conversation.id, "repository preserves conversation id")
        expect(loadedConversations[0].events.count == 2, "repository preserves conversation events")
    } catch {
        expect(false, "persistence test should not throw: \(error)")
    }

    try? FileManager.default.removeItem(at: dbURL)
}
```

- [ ] **Step 2: Call the failing tests**

Add this call in `Tests/CodexPlusCoreTests/main.swift` before the final result block:

```swift
runPersistenceTests()
```

- [ ] **Step 3: Run test and verify failure**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: build fails because `SQLiteDatabase`, `CodexPlusSchema`, and `SQLiteCodexPlusRepository` do not exist.

- [ ] **Step 4: Link SQLite**

If `import SQLite3` fails during implementation, modify `Package.swift` target `CodexPlusCore` to include:

```swift
        .target(
            name: "CodexPlusCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
```

Keep `CodexPlusApp` dependencies and AppKit/IOKit/Carbon linker settings unchanged.

- [ ] **Step 5: Implement schema exactly once**

Create `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift` with tables:

```swift
public enum CodexPlusSchema {
    public static let version = 1

    public static func migrate(_ database: SQLiteDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS projects (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            last_activity_at REAL NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            prompt TEXT NOT NULL,
            workspace_path TEXT NOT NULL,
            state TEXT NOT NULL,
            permission_mode TEXT NOT NULL,
            is_pinned INTEGER NOT NULL,
            is_explicitly_kept INTEGER NOT NULL,
            is_archived INTEGER NOT NULL,
            created_at REAL NOT NULL,
            last_activity_at REAL NOT NULL,
            archived_at REAL,
            archive_markdown_path TEXT,
            FOREIGN KEY(project_id) REFERENCES projects(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS conversation_events (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            kind TEXT NOT NULL,
            display_text TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            raw_payload_json TEXT,
            created_at REAL NOT NULL,
            searchable_text TEXT NOT NULL,
            FOREIGN KEY(conversation_id) REFERENCES conversations(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS archive_index (
            id TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            searchable_text TEXT NOT NULL,
            command_text TEXT NOT NULL,
            error_text TEXT NOT NULL,
            project_path TEXT NOT NULL,
            archived_at REAL NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS memory_cards (
            id TEXT PRIMARY KEY,
            scope TEXT NOT NULL,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            summary TEXT NOT NULL,
            body TEXT NOT NULL,
            content_shape TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            source_metadata_json TEXT NOT NULL
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS memory_sources (
            id TEXT PRIMARY KEY,
            memory_card_id TEXT NOT NULL,
            source_kind TEXT NOT NULL,
            source_id TEXT NOT NULL,
            source_path TEXT,
            created_at REAL NOT NULL,
            FOREIGN KEY(memory_card_id) REFERENCES memory_cards(id)
        );
        """)
        try database.execute("""
        CREATE TABLE IF NOT EXISTS attachments (
            id TEXT PRIMARY KEY,
            owner_kind TEXT NOT NULL,
            owner_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            original_file_path TEXT,
            content_type TEXT NOT NULL,
            byte_count INTEGER NOT NULL,
            checksum TEXT NOT NULL,
            is_snapshot INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
        """)
    }
}
```

- [ ] **Step 6: Implement database wrapper and repository**

Create `SQLiteDatabase` with these public methods:

```swift
public final class SQLiteDatabase: @unchecked Sendable {
    public init(path: String) throws
    public func execute(_ sql: String) throws
    public func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [[String: SQLiteValue]]
}

public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}
```

Create `CodexPlusRepository` with these public methods:

```swift
public protocol CodexPlusRepository: Sendable {
    func saveProject(_ project: WorkspaceSessionGroup) throws
    func loadProjects() throws -> [WorkspaceSessionGroup]
    func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws
    func loadConversations() throws -> [ConversationSession]
}
```

Implement `SQLiteCodexPlusRepository` using deterministic event encoding:

```swift
public final class SQLiteCodexPlusRepository: CodexPlusRepository {
    public init(database: SQLiteDatabase)
    public func saveProject(_ project: WorkspaceSessionGroup) throws
    public func loadProjects() throws -> [WorkspaceSessionGroup]
    public func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws
    public func loadConversations() throws -> [ConversationSession]
}
```

- [ ] **Step 7: Run tests**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: all tests pass and the temporary SQLite file is removed.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/CodexPlusCore/Persistence Tests/CodexPlusCoreTests/PersistenceTests.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: add sqlite persistence foundation"
```

---

### Task 3: Archive Rendering, Indexing, And Search

**Files:**
- Create: `Sources/CodexPlusCore/Archive/MarkdownArchiveRenderer.swift`
- Create: `Sources/CodexPlusCore/Archive/ArchiveSearchService.swift`
- Modify: `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
- Create: `Tests/CodexPlusCoreTests/ArchiveTests.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Consumes: persisted conversations and events from Task 2.
- Produces: `MarkdownArchiveRenderer.render(conversation:projectName:) -> String`
- Produces: `ArchiveSearchService.archive(conversation:project:) throws -> ConversationArchiveRecord`
- Produces: `ArchiveSearchService.search(_:) throws -> [ConversationArchiveRecord]`
- Extends repository with archive-index save/search/load methods.

- [ ] **Step 1: Write failing archive tests**

Create `Tests/CodexPlusCoreTests/ArchiveTests.swift`:

```swift
import Foundation
import CodexPlusCore

@MainActor
func runArchiveTests() {
    let conversationID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    let conversation = ConversationSession(
        id: conversationID,
        title: "Git 提交 & 推送",
        prompt: "commit",
        workspacePath: "/tmp/codex-plus",
        state: .completed,
        createdAt: Date(timeIntervalSince1970: 100),
        lastActivityAt: Date(timeIntervalSince1970: 120),
        events: [
            .userPrompt(id: UUID(), text: "提交所有设计文档"),
            .command(id: UUID(), executionID: "cmd-1", command: "git status --short", status: .completed),
            .assistantMessage(id: UUID(), text: "已经提交。")
        ]
    )

    let markdown = MarkdownArchiveRenderer.render(conversation: conversation, projectName: "codex-plus")
    expect(markdown.contains("# Git 提交 & 推送"), "archive markdown contains title")
    expect(markdown.contains("项目：codex-plus"), "archive markdown contains project")
    expect(markdown.contains("git status --short"), "archive markdown contains command")
    expect(markdown.contains("已经提交。"), "archive markdown contains assistant message")

    let record = ArchiveSearchService.indexRecord(
        conversation: conversation,
        projectID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
        projectName: "codex-plus",
        archivedAt: Date(timeIntervalSince1970: 130)
    )
    expect(record.searchableText.contains("提交所有设计文档"), "archive index includes user text")
    expect(record.commandText.contains("git status --short"), "archive index includes command text")
    expect(record.title == "Git 提交 & 推送", "archive index preserves title")
}
```

- [ ] **Step 2: Call failing tests**

Add this call in `Tests/CodexPlusCoreTests/main.swift`:

```swift
runArchiveTests()
```

- [ ] **Step 3: Run test and verify failure**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: build fails because `MarkdownArchiveRenderer` and `ArchiveSearchService` do not exist.

- [ ] **Step 4: Implement archive models and renderer**

Add archive record model to `Sources/CodexPlusCore/Archive/ArchiveSearchService.swift`:

```swift
public struct ConversationArchiveRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var conversationID: UUID
    public var projectID: UUID
    public var title: String
    public var searchableText: String
    public var commandText: String
    public var errorText: String
    public var projectPath: String
    public var archivedAt: Date
}
```

Implement Markdown sections in this order:

```markdown
# <conversation title>

项目：<project name>
工作目录：<workspace path>
状态：<state raw value>

## 事件

### 用户
...
### 命令
...
### Codex
...
```

- [ ] **Step 5: Extend repository**

Add repository methods:

```swift
func saveArchiveRecord(_ record: ConversationArchiveRecord) throws
func searchArchiveRecords(query: String) throws -> [ConversationArchiveRecord]
func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws
```

Search implementation uses SQLite `LIKE` over `title`, `searchable_text`, `command_text`, `error_text`, and `project_path` with escaped `%` and `_`.

- [ ] **Step 6: Run tests**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusCore/Archive Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift Tests/CodexPlusCoreTests/ArchiveTests.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: add archive rendering and search"
```

---

### Task 4: Execution Engine Boundary

**Files:**
- Create: `Sources/CodexPlusCore/Execution/ExecutionEngine.swift`
- Create: `Sources/CodexPlusCore/Execution/CodexCLIEngine.swift`
- Create: `Tests/CodexPlusCoreTests/ExecutionEngineTests.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Consumes: existing `ProcessCodexRunner`, `CodexRunResult`, `CodexEvent`, `PermissionMode`.
- Produces: `ExecutionEngine` protocol.
- Produces: `CodexCLIEngine`.
- Produces: test fake engine support for Task 5.

- [ ] **Step 1: Write failing engine tests**

Create `Tests/CodexPlusCoreTests/ExecutionEngineTests.swift`:

```swift
import Foundation
import CodexPlusCore

@MainActor
func runExecutionEngineTests() {
    let sessionID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    let fake = FakeExecutionEngine()
    let request = ExecutionRequest(
        prompt: "who are you",
        permissionMode: .semiAutomatic,
        sessionID: sessionID,
        workingDirectoryURL: URL(fileURLWithPath: "/tmp", isDirectory: true)
    )

    let handle = fake.start(
        request: request,
        onEvent: { event in
            expect(event == .status("fake event"), "fake engine forwards event")
        },
        onFinish: { result in
            expect(result.succeeded, "fake engine forwards success")
        }
    )

    expect(fake.requests == [request], "fake engine captures request")
    handle.stop()
    expect(fake.stopCount == 1, "fake handle records stop")
}

private final class FakeExecutionHandle: ExecutionHandle, @unchecked Sendable {
    var stopCount = 0
    func stop() { stopCount += 1 }
}

private final class FakeExecutionEngine: ExecutionEngine, @unchecked Sendable {
    var requests: [ExecutionRequest] = []
    var stopCount = 0

    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        requests.append(request)
        onEvent(.status("fake event"))
        onFinish(CodexRunResult(exitCode: 0, stderr: ""))
        let handle = FakeExecutionHandle()
        return EngineStopProxy(handle: handle) { [weak self] in self?.stopCount += 1 }
    }
}
```

- [ ] **Step 2: Call failing tests**

Add:

```swift
runExecutionEngineTests()
```

to `Tests/CodexPlusCoreTests/main.swift`.

- [ ] **Step 3: Run test and verify failure**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: build fails because `ExecutionEngine`, `ExecutionRequest`, `ExecutionHandle`, and `EngineStopProxy` do not exist.

- [ ] **Step 4: Implement engine protocol**

Create `Sources/CodexPlusCore/Execution/ExecutionEngine.swift`:

```swift
import Foundation

public struct ExecutionRequest: Equatable, Sendable {
    public var prompt: String
    public var permissionMode: PermissionMode
    public var sessionID: UUID
    public var workingDirectoryURL: URL
}

public protocol ExecutionHandle: Sendable {
    func stop()
}

public protocol ExecutionEngine: Sendable {
    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle
}

public final class EngineStopProxy: ExecutionHandle, @unchecked Sendable {
    private let handle: ExecutionHandle
    private let onStop: @Sendable () -> Void

    public init(handle: ExecutionHandle, onStop: @escaping @Sendable () -> Void) {
        self.handle = handle
        self.onStop = onStop
    }

    public func stop() {
        onStop()
        handle.stop()
    }
}
```

- [ ] **Step 5: Implement Codex CLI adapter**

Create `Sources/CodexPlusCore/Execution/CodexCLIEngine.swift`:

```swift
import Foundation

public struct CodexCLIEngine: ExecutionEngine {
    private let runner: ProcessCodexRunner

    public init(runner: ProcessCodexRunner = ProcessCodexRunner()) {
        self.runner = runner
    }

    public func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        runner.run(
            prompt: request.prompt,
            permissionMode: request.permissionMode,
            workingDirectoryURL: request.workingDirectoryURL,
            onEvent: onEvent,
            onFinish: onFinish
        )
    }
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusCore/Execution Tests/CodexPlusCoreTests/ExecutionEngineTests.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: add execution engine boundary"
```

---

### Task 5: Workbench Store And Run Lifecycle

**Files:**
- Create: `Sources/CodexPlusCore/WorkbenchStore.swift`
- Create: `Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Consumes: repository from Task 2, archive service from Task 3, engine from Task 4.
- Produces: `@MainActor final class WorkbenchStore: ObservableObject`
- Produces: `WorkbenchStore.snapshot`
- Produces: methods `startConversation`, `sendFollowUp`, `stopActiveRun`, `archiveConversation`, `confirmStopAndArchive`, `searchArchives`, `openArchive`

- [ ] **Step 1: Write failing store tests**

Create `Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift`:

```swift
import Foundation
import CodexPlusCore

@MainActor
func runWorkbenchStoreTests() {
    let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-plus-store-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: dbURL) }

    do {
        let database = try SQLiteDatabase(path: dbURL.path)
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(repository: repository, engine: engine)

        store.createProject(path: "/tmp/codex-plus", displayName: "codex-plus")
        store.startConversation(prompt: "start", workspacePath: "/tmp/codex-plus")

        expect(store.snapshot.activeConversation?.state == .running, "store marks new conversation running")
        expect(engine.requests.count == 1, "store starts engine")
        expect(store.snapshot.projectCards.count == 1, "store produces project cards")
        expect(store.snapshot.projectCards[0].conversationTitle != "暂无对话", "store card shows active conversation")
        expect(store.snapshot.composerAction == .stop, "store shows stop while running")

        store.sendFollowUp("second")
        let lastEvent = store.snapshot.activeConversation?.events.last
        if case let .some(.error(_, text)) = lastEvent {
            expect(text == "任务运行中，当前不能发送新的消息。", "store rejects follow-up while running")
        } else {
            expect(false, "store appends an error when follow-up is sent while running")
        }

        store.stopActiveRun()
        expect(store.snapshot.activeConversation?.state == .stopped, "store marks stopped")
        expect(engine.stopCount == 1, "store stops active engine handle")
        expect(store.snapshot.composerAction == .send, "store shows send after stop")
    } catch {
        expect(false, "workbench store test should not throw: \(error)")
    }
}

private final class ManualExecutionHandle: ExecutionHandle, @unchecked Sendable {
    private let onStop: @Sendable () -> Void

    init(onStop: @escaping @Sendable () -> Void) {
        self.onStop = onStop
    }

    func stop() {
        onStop()
    }
}

private final class ManualExecutionEngine: ExecutionEngine, @unchecked Sendable {
    var requests: [ExecutionRequest] = []
    var stopCount = 0

    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        requests.append(request)
        onEvent(.status("Codex CLI 已启动"))
        return ManualExecutionHandle { [weak self] in self?.stopCount += 1 }
    }
}
```

- [ ] **Step 2: Call failing tests**

Add:

```swift
runWorkbenchStoreTests()
```

to `Tests/CodexPlusCoreTests/main.swift`.

- [ ] **Step 3: Run test and verify failure**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: build fails because `WorkbenchStore` does not exist.

- [ ] **Step 4: Implement `WorkbenchSnapshot`**

Add to `WorkbenchModels.swift`:

```swift
public struct WorkbenchSnapshot: Equatable, Sendable {
    public var projectCards: [WorkbenchProjectCard]
    public var activeConversation: ConversationSession?
    public var composerAction: WorkbenchComposerAction
    public var statusBar: WorkbenchStatusBarState
    public var archiveSearchResults: [ConversationArchiveRecord]
    public var isPinned: Bool
    public var pendingArchiveConfirmationConversationID: UUID?
    public var isShowingArchiveSearch: Bool
    public var openedArchiveConversation: ConversationSession?
}
```

- [ ] **Step 5: Implement store behavior**

Create `Sources/CodexPlusCore/WorkbenchStore.swift` with:

```swift
@MainActor
public final class WorkbenchStore: ObservableObject {
    @Published public private(set) var snapshot: WorkbenchSnapshot

    public init(repository: CodexPlusRepository, engine: ExecutionEngine)
    public func createProject(path: String, displayName: String)
    public func beginNewConversationDraft()
    public func selectProject(_ id: UUID)
    public func selectConversation(_ id: UUID)
    public func startConversation(prompt: String, workspacePath: String)
    public func sendFollowUp(_ prompt: String)
    public func stopActiveRun()
    public func archiveConversation(_ id: UUID) -> ArchiveRequestResult
    public func confirmStopAndArchive(_ id: UUID)
    public func cancelArchiveConfirmation()
    public func confirmPendingStopAndArchive()
    public func searchArchives(_ query: String)
    public func openArchive(_ archiveID: UUID)
    public func showArchiveSearch()
    public func togglePin()
}
```

`ArchiveRequestResult` must be:

```swift
public enum ArchiveRequestResult: Equatable, Sendable {
    case archived
    case needsStopConfirmation(UUID)
    case notFound
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusCore/WorkbenchStore.swift Sources/CodexPlusCore/WorkbenchModels.swift Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: add workbench state store"
```

---

### Task 6: Floating Workbench Panel Controller

**Files:**
- Create: `Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift`
- Modify: `Sources/CodexPlusApp/AppDelegate.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`
- Test: `Tests/CodexPlusCoreTests/WorkbenchProjectionTests.swift`

**Interfaces:**
- Consumes: `WorkbenchStore`
- Consumes: `WorkbenchInteractionPolicies.shouldHideForOutsideClick`
- Produces: one floating `GlassPanel` sized from the design image.

- [ ] **Step 1: Add outside-click policy coverage**

Extend `runWorkbenchProjectionTests()` with:

```swift
expect(
    !WorkbenchInteractionPolicies.shouldHideForOutsideClick(
        isPinned: false,
        clickPoint: CGPoint(x: 200, y: 200),
        panelFrame: CGRect(x: 100, y: 100, width: 800, height: 500)
    ),
    "unpinned workbench stays visible for inside click"
)
```

- [ ] **Step 2: Run test**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: pass, proving the panel controller can rely on the pure policy.

- [ ] **Step 3: Implement controller**

Create `Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift`:

```swift
import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class WorkbenchPanelController {
    private let panelFactory: PanelFactory
    private let screenProvider: ActiveScreenProvider
    private let store: WorkbenchStore
    private weak var panelDelegate: NSWindowDelegate?
    private var panel: GlassPanel?
    private let dismissMonitors = EventMonitorStore()

    init(
        panelFactory: PanelFactory,
        screenProvider: ActiveScreenProvider,
        store: WorkbenchStore,
        panelDelegate: NSWindowDelegate?
    ) {
        self.panelFactory = panelFactory
        self.screenProvider = screenProvider
        self.store = store
        self.panelDelegate = panelDelegate
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let screen = screenProvider.activeScreen() else { return }
        let frame = Self.defaultFrame(in: screen.visibleFrame)
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(rootView: WorkbenchView(store: store))
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installDismissMonitorsIfNeeded()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    static func defaultFrame(in visibleFrame: NSRect) -> NSRect {
        let width = min(CGFloat(1240), visibleFrame.width - 96)
        let height = min(CGFloat(720), visibleFrame.height - 96)
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
```

Add local and global mouse-down dismissal monitors through `EventMonitorStore`. Each monitor reads `store.snapshot.isPinned`, `NSEvent.mouseLocation`, and `panel.frame`, then calls `hide()` only when `WorkbenchInteractionPolicies.shouldHideForOutsideClick(...)` returns `true`.

- [ ] **Step 4: Wire app launch**

Modify `AppDelegate` so it creates:

```swift
let database = try SQLiteDatabase(path: ApplicationSupportPaths.databasePath())
try CodexPlusSchema.migrate(database)
let repository = SQLiteCodexPlusRepository(database: database)
let engine = CodexCLIEngine()
let store = WorkbenchStore(repository: repository, engine: engine)
```

If initialization throws, show a critical `NSAlert` and terminate.

- [ ] **Step 5: Route hotkey to workbench**

Modify `WindowCoordinator` so `handleGlobalShortcut()` calls `workbenchPanelController.toggle()` and no longer chooses between compact dashboard and side panel.

- [ ] **Step 6: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift Sources/CodexPlusApp/AppDelegate.swift Sources/CodexPlusApp/WindowCoordinator.swift Tests/CodexPlusCoreTests/WorkbenchProjectionTests.swift
git commit -m "feat: add floating workbench panel"
```

---

### Task 7: SwiftUI Workbench Main Interface

**Files:**
- Create: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Create: `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift`
- Create: `Sources/CodexPlusApp/Workbench/WorkbenchConversationView.swift`
- Create: `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift`
- Create: `Sources/CodexPlusApp/Workbench/WorkbenchStatusBarView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift`

**Interfaces:**
- Consumes: `WorkbenchStore.snapshot`
- Produces: SwiftUI UI matching `docs/superpowers/prototypes/codex-plus-v1-main-workbench-design.png`

- [ ] **Step 1: Build before UI work**

Run:

```bash
swift build
```

Expected: build succeeds before adding the SwiftUI files.

- [ ] **Step 2: Implement root view**

Create `WorkbenchView`:

```swift
import CodexPlusCore
import SwiftUI

struct WorkbenchView: View {
    @ObservedObject var store: WorkbenchStore

    var body: some View {
        LiquidGlassScene(padding: 0) {
            VStack(spacing: 0) {
                TopProjectStripView(
                    cards: store.snapshot.projectCards,
                    onNewConversation: { store.beginNewConversationDraft() },
                    onOpenArchive: { store.showArchiveSearch() },
                    onSelectProject: { store.selectProject($0) },
                    onSelectConversation: { store.selectConversation($0) }
                )
                WorkbenchConversationView(snapshot: store.snapshot)
                WorkbenchComposerView(
                    snapshot: store.snapshot,
                    onSend: { store.sendFollowUp($0) },
                    onStop: { store.stopActiveRun() }
                )
                WorkbenchStatusBarView(state: store.snapshot.statusBar)
            }
        }
    }
}
```

Use the Task 5 store methods directly; no SwiftUI view should mutate repository or engine objects outside `WorkbenchStore`.

- [ ] **Step 3: Implement top project cards**

`TopProjectStripView` must render:

```swift
Text("项目：")
Text(card.projectName)
Text("对话：")
Text(card.conversationTitle)
```

Use SF Symbols in implementation:

```swift
Image(systemName: "folder")
Image(systemName: "text.bubble")
```

Show overflow button only when `card.overflowCount != nil`.

- [ ] **Step 4: Implement composer**

`WorkbenchComposerView` must choose button from policy:

```swift
switch snapshot.composerAction {
case .stop:
    Button(action: onStop) { Image(systemName: "stop.fill") }
case .send:
    Button(action: { onSend(prompt) }) { Image(systemName: "arrow.up") }
}
```

Disable text entry while `.stop` is shown.

- [ ] **Step 5: Implement status bar**

`WorkbenchStatusBarView` shows exactly three items:

```swift
Codex CLI 可用
SQLite 已连接
归档索引 待更新
```

Do not show pin state or background-task state.

- [ ] **Step 6: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 7: Manual visual check**

Run:

```bash
swift run CodexPlusApp
```

Expected:

- Hotkey opens one centered floating workbench.
- Window has no traditional titlebar.
- Top cards distinguish 项目 and 对话.
- Running conversation shows stop button only.
- Bottom status bar has exactly three technical statuses.

- [ ] **Step 8: Commit**

```bash
git add Sources/CodexPlusApp/Workbench
git commit -m "feat: build workbench interface"
```

---

### Task 8: Archive Confirmation, Archived Search Page, And Reopen

**Files:**
- Create: `Sources/CodexPlusApp/Workbench/ArchivedConversationView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchStore.swift`
- Test: `Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift`

**Interfaces:**
- Consumes: `WorkbenchStore.archiveConversation`, `searchArchives`, and `openArchive`.
- Produces: visible archived-search state from the `已归档` button.
- Produces: stop-before-archive confirmation for running conversations.

- [ ] **Step 1: Add store tests**

Extend `runWorkbenchStoreTests()`:

```swift
let runningID = store.snapshot.activeConversation!.id
expect(
    store.archiveConversation(runningID) == .needsStopConfirmation(runningID),
    "running conversation asks for stop confirmation before archive"
)
store.confirmStopAndArchive(runningID)
expect(store.snapshot.projectCards[0].conversationTitle == "暂无对话", "archived conversation disappears from active cards")
store.searchArchives("start")
expect(!store.snapshot.archiveSearchResults.isEmpty, "archived conversation is searchable")
```

- [ ] **Step 2: Run failing test**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: failure until archive state and search state are fully wired.

- [ ] **Step 3: Wire archive confirmation state**

Use the `WorkbenchSnapshot` fields introduced in Task 5:

```swift
public var pendingArchiveConfirmationConversationID: UUID?
public var isShowingArchiveSearch: Bool
public var openedArchiveConversation: ConversationSession?
```

Set `pendingArchiveConfirmationConversationID` when archiving a running task.

- [ ] **Step 4: Implement `ArchivedConversationView`**

Create a SwiftUI view with:

```swift
TextField("搜索已归档对话", text: $query)
List(results) { record in
    Button(record.title) { onOpen(record.id) }
}
```

Do not show active conversations in this view.

- [ ] **Step 5: Add confirmation alert**

In `WorkbenchView`, attach:

```swift
.alert("终止任务后归档？", isPresented: pendingArchiveBinding) {
    Button("取消", role: .cancel) { store.cancelArchiveConfirmation() }
    Button("停止并归档", role: .destructive) { store.confirmPendingStopAndArchive() }
} message: {
    Text("这个对话仍在运行。归档前需要先停止当前 Codex 任务；停止后会保存完整事件流，并将对话标记为已归档。")
}
```

- [ ] **Step 6: Run tests and build**

Run:

```bash
swift run CodexPlusCoreTests
swift build
```

Expected: tests and build pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusApp/Workbench Sources/CodexPlusCore/WorkbenchStore.swift Sources/CodexPlusCore/WorkbenchModels.swift Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift
git commit -m "feat: add archived conversation workflow"
```

---

### Task 9: Application Support Paths, Manual Test Script, And Final Verification

**Files:**
- Create: `Sources/CodexPlusCore/ApplicationSupportPaths.swift`
- Create: `docs/superpowers/manual-tests/2026-07-05-codex-plus-v1.md`
- Modify: `Sources/CodexPlusApp/AppDelegate.swift`
- Modify: `docs/superpowers/specs/2026-07-05-codex-plus-v1-redesign-design.md` only if implementation intentionally changes an approved design rule.

**Interfaces:**
- Produces: `ApplicationSupportPaths.databasePath(bundleIdentifier:fileManager:) -> String`
- Produces: manual smoke checklist for the V1 workbench.

- [ ] **Step 1: Write path tests**

Add to `PersistenceTests.swift`:

```swift
let path = ApplicationSupportPaths.databasePath(
    bundleIdentifier: "com.example.CodexPlusTests",
    homeDirectoryPath: "/Users/test"
)
expect(
    path == "/Users/test/Library/Application Support/com.example.CodexPlusTests/CodexPlus.sqlite",
    "application support database path is deterministic"
)
```

- [ ] **Step 2: Implement paths**

Create:

```swift
public enum ApplicationSupportPaths {
    public static func databasePath(
        bundleIdentifier: String = "com.oriki.CodexPlus",
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        NSString(string: homeDirectoryPath)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("CodexPlus.sqlite")
    }
}
```

`AppDelegate` must create the parent directory before opening SQLite.

- [ ] **Step 3: Add manual smoke checklist**

Create `docs/superpowers/manual-tests/2026-07-05-codex-plus-v1.md`:

```markdown
# Codex Plus V1 Manual Smoke Test

Date: 2026-07-05

- [ ] Build with `swift build`.
- [ ] Run with `swift run CodexPlusApp`.
- [ ] Press the global hotkey and confirm the floating workbench opens.
- [ ] Confirm the workbench has no traditional titlebar.
- [ ] Confirm outside click hides the unpinned workbench without stopping a running task.
- [ ] Confirm the pin button prevents outside-click hiding.
- [ ] Start a task in a selected project.
- [ ] Confirm top cards show `项目：` and `对话：`.
- [ ] Confirm archived conversations do not appear in active cards.
- [ ] Confirm running task shows only the stop button.
- [ ] Confirm terminal task shows the send button.
- [ ] Archive a completed task.
- [ ] Search from `已归档` and reopen the full conversation.
- [ ] Confirm app restart reloads projects, conversations, events, archive index, and memory schema.
```

- [ ] **Step 4: Run automated verification**

Run:

```bash
swift run CodexPlusCoreTests
swift build
```

Expected: both commands pass.

- [ ] **Step 5: Run manual smoke**

Run:

```bash
swift run CodexPlusApp
```

Expected: every checklist item in `docs/superpowers/manual-tests/2026-07-05-codex-plus-v1.md` can be checked.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexPlusCore/ApplicationSupportPaths.swift Sources/CodexPlusApp/AppDelegate.swift Tests/CodexPlusCoreTests/PersistenceTests.swift docs/superpowers/manual-tests/2026-07-05-codex-plus-v1.md
git commit -m "test: add v1 persistence smoke checks"
```

---

## Self-Review

Spec coverage:

- Project/workdir selection: Task 5 and Task 7.
- Codex CLI execution: Task 4 and Task 5.
- Complete event display: Task 7.
- Stop while running: Task 1, Task 5, Task 7.
- Running task cannot send: Task 1, Task 5, Task 7.
- Archive full conversation: Task 3 and Task 8.
- Search archived conversations: Task 3 and Task 8.
- Reopen archived conversation: Task 8.
- Local SQLite persistence: Task 2 and Task 9.
- Memory-card data foundation: Task 2 schema.
- Liquid glass floating workbench: Task 6 and Task 7.
- Top project cards and archived filtering: Task 1 and Task 7.

Placeholder scan:

- This plan intentionally avoids open placeholders and names exact files, functions, commands, and expected outcomes.

Type consistency:

- `WorkbenchProjectCard`, `WorkbenchComposerAction`, `WorkbenchSnapshot`, `ExecutionRequest`, `ConversationArchiveRecord`, and `WorkbenchStore` are introduced before later tasks consume them.
