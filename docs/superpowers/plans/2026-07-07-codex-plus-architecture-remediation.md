# Codex Plus Architecture Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Codex Plus from a mid-migration Swift/macOS codebase into one Workbench-led architecture with clear app assembly, domain services, repository boundaries, visible errors, and standard SwiftPM tests.

**Architecture:** Make Workbench the only production conversation and execution path. Keep `CodexPlusApp` responsible for AppKit/SwiftUI window wiring, move business rules into small `CodexPlusCore` services and policies, split persistence by bounded context, and make every change pass through behavior tests instead of source-string assertions.

**Tech Stack:** Swift 6.2, SwiftPM, macOS 26, SwiftUI, AppKit, SQLite C library, existing executable-style tests migrating to SwiftPM `testTarget`.

---

## Global Constraints

- Do not change user-facing archive semantics.
- Do not redesign the UI visual style.
- Do not introduce third-party dependencies.
- Keep `CodexPlusCore` free of AppKit and SwiftUI imports.
- Keep the Workbench user flow as the production flow.
- Preserve current behavior for new conversation, follow-up, stop, archive, archive search, and reopen archive unless a task explicitly changes error visibility.
- Run `swift run CodexPlusCoreTests` after every task until `swift test` is made functional.
- After Task 1, run `swift test` after every task.
- If sandbox blocks Swift caches, rerun the same command with escalation.

## File Structure

- `Package.swift`: change the test target from executable target to SwiftPM test target.
- `Tests/CodexPlusCoreTests/TestSupport.swift`: shared `expect`, fakes, temp SQLite helpers, run-loop draining.
- `Tests/CodexPlusCoreTests/main.swift`: delete after tests are migrated, or reduce to an empty compatibility file if SwiftPM requires no runner.
- `Sources/CodexPlusCore/WorkbenchState.swift`: internal Workbench state container and user-visible error state.
- `Sources/CodexPlusCore/WorkbenchErrorState.swift`: error mapping helpers if it grows beyond one screen.
- `Sources/CodexPlusCore/CodexEventDisplayMapper.swift`: single mapping from `CodexEvent` to `ConversationDisplayEvent`.
- `Sources/CodexPlusCore/ConversationLifecycleService.swift`: conversation/project lifecycle and persistence coordination.
- `Sources/CodexPlusCore/ConversationRunOrchestrator.swift`: execution handle management around `ExecutionEngine`.
- `Sources/CodexPlusCore/ProjectSelectionPolicy.swift`: pure active project/conversation fallback rules.
- `Sources/CodexPlusCore/WorkbenchStore.swift`: reduced store that owns snapshot publication and intent routing.
- `Sources/CodexPlusCore/Persistence/ProjectRepository.swift`: project repository protocol and SQLite implementation.
- `Sources/CodexPlusCore/Persistence/ConversationRepository.swift`: conversation repository protocol and SQLite implementation.
- `Sources/CodexPlusCore/Persistence/ArchiveRepository.swift`: archive repository protocol and SQLite implementation.
- `Sources/CodexPlusCore/Persistence/MemoryRepository.swift`: memory repository protocol and SQLite implementation.
- `Sources/CodexPlusCore/Persistence/AttachmentRepository.swift`: attachment repository protocol and SQLite implementation.
- `Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift`: facade conforming to all repository protocols.
- `Sources/CodexPlusCore/Persistence/ConversationEventCodec.swift`: event persistence codec.
- `Sources/CodexPlusApp/AppDelegate.swift`: construct the new store and app assembly only.
- `Sources/CodexPlusApp/WindowCoordinator.swift`: reduce to Workbench and launcher coordination.
- `Sources/CodexPlusApp/Legacy/`: temporary location for old compact/side panel code if deletion is too large for one task.
- `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`: grouped view actions.
- `Sources/CodexPlusApp/Workbench/WorkbenchMetrics.swift`: Workbench dimensions and spacing.
- `Sources/CodexPlusApp/Workbench/WorkbenchStrings.swift`: Workbench strings.
- `Sources/CodexPlusCore/CodexCommandConfiguration.swift`: Codex command configuration.
- `Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift`: behavior tests for store intents and snapshots.
- `Tests/CodexPlusCoreTests/ConversationLifecycleServiceTests.swift`: service tests for persistence-backed state changes.
- `Tests/CodexPlusCoreTests/ConversationRunOrchestratorTests.swift`: run start/stop/event/finish tests.
- `Tests/CodexPlusCoreTests/ConversationEventCodecTests.swift`: event codec round-trip tests.
- `Tests/CodexPlusCoreTests/PersistenceTests.swift`: SQLite store round-trip and migration tests.
- `Tests/CodexPlusCoreTests/ArchitectureBoundaryTests.swift`: small import/reference boundary tests.

---

### Task 1: Standardize SwiftPM Test Entry

**Files:**
- Modify: `Package.swift`
- Create: `Tests/CodexPlusCoreTests/TestSupport.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`
- Modify: every `Tests/CodexPlusCoreTests/*Tests.swift`

- [ ] **Step 0: Verify local test framework availability**

Run:

```bash
find /Applications /Library/Developer -path '*XCTest.swiftmodule*' -o -path '*Testing.swiftmodule*'
```

Expected on a machine that can complete this task:

```text
...XCTest.swiftmodule...
```

or:

```text
...Testing.swiftmodule...
```

If neither module exists, stop this task and keep `CodexPlusCoreTests` as an executable target. On the current Command Line Tools-only machine, both `import XCTest` and `import Testing` fail with `no such module`, so `swift test` cannot be made the primary runner until a full Xcode/toolchain with a test framework module is selected.

- [ ] **Step 1: Record current baseline**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected:

```text
CodexPlusCoreTests passed: 531 assertions
```

If sandbox blocks `~/.cache/clang/ModuleCache`, rerun with escalation using the same command.

- [ ] **Step 2: Change Package.swift test target**

Replace the executable test target:

```swift
.executableTarget(
    name: "CodexPlusCoreTests",
    dependencies: ["CodexPlusCore"],
    path: "Tests/CodexPlusCoreTests"
)
```

with:

```swift
.testTarget(
    name: "CodexPlusCoreTests",
    dependencies: ["CodexPlusCore"],
    path: "Tests/CodexPlusCoreTests"
)
```

- [ ] **Step 3: Move shared test helpers out of main.swift**

Create `Tests/CodexPlusCoreTests/TestSupport.swift` with the shared support currently at the top of `main.swift`:

```swift
import Foundation
import CoreGraphics
@testable import CodexPlusCore

var failures: [String] = []
var assertionCount = 0

@MainActor
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertionCount += 1
    if !condition() {
        failures.append(message)
    }
}

@MainActor
func drainMainRunLoop() {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
}

@MainActor
func withSQLiteRepositoryTest(
    _ name: String,
    body: (URL, SQLiteCodexPlusRepository) throws -> Void
) {
    let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("codex-plus-store-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: dbURL) }

    do {
        let database = try SQLiteDatabase(path: dbURL.path)
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        try body(dbURL, repository)
    } catch {
        expect(false, "\(name) should not throw: \(error)")
    }
}
```

Move the existing fake providers and helper classes from `main.swift` into this file as-is. Keep their names stable so existing test files compile.

- [ ] **Step 4: Convert runner calls to XCTest**

Create `Tests/CodexPlusCoreTests/CodexPlusCoreTestSuite.swift`:

```swift
import XCTest

final class CodexPlusCoreTestSuite: XCTestCase {
    @MainActor
    func testAllLegacyRunnerSuites() {
        failures = []
        assertionCount = 0

        runWorkbenchLauncherFramePolicyTests()
        runWorkbenchProjectionTests()
        runExecutionEngineTests()
        runPersistenceTests()
        runArchiveTests()
        runWorkbenchStoreTests()

        if !failures.isEmpty {
            XCTFail(failures.joined(separator: "\n"))
        }

        XCTAssertGreaterThan(assertionCount, 0)
    }
}
```

If `main.swift` currently calls additional `run...Tests()` functions, add those exact calls above before `runWorkbenchStoreTests()`.

- [ ] **Step 5: Make main.swift inert**

Replace `Tests/CodexPlusCoreTests/main.swift` with:

```swift
// XCTest entry is CodexPlusCoreTestSuite.
```

- [ ] **Step 6: Verify swift test**

Run:

```bash
swift test
```

Expected:

```text
Test Suite 'CodexPlusCoreTestSuite' passed
```

The full output may include build lines. The command must exit 0.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Tests/CodexPlusCoreTests
git commit -m "test: run core tests through swift test"
```

---

### Task 2: Introduce Workbench State, Error State, And Event Mapper

**Files:**
- Create: `Sources/CodexPlusCore/WorkbenchState.swift`
- Create: `Sources/CodexPlusCore/CodexEventDisplayMapper.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchModels.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchStore.swift`
- Modify: `Sources/CodexPlusCore/ConversationCoordinator.swift`
- Create: `Tests/CodexPlusCoreTests/WorkbenchStateTests.swift`
- Create: `Tests/CodexPlusCoreTests/CodexEventDisplayMapperTests.swift`
- Modify: `Tests/CodexPlusCoreTests/CodexPlusCoreTestSuite.swift`

- [ ] **Step 1: Write failing mapper tests**

Create `Tests/CodexPlusCoreTests/CodexEventDisplayMapperTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class CodexEventDisplayMapperTests: XCTestCase {
    func testMapsCodexEventsToDisplayEvents() {
        XCTAssertEqual(
            CodexEventDisplayMapper.displayEvent(from: .threadStarted("thread-1")).displayText,
            "Thread started: thread-1"
        )
        XCTAssertEqual(
            CodexEventDisplayMapper.displayEvent(from: .turnStarted).displayText,
            "Turn started"
        )
        XCTAssertEqual(
            CodexEventDisplayMapper.displayEvent(from: .turnCompleted).displayText,
            "Turn completed"
        )

        if case let .assistantMessage(_, text) = CodexEventDisplayMapper.displayEvent(from: .agentMessage("hello")) {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("agent message should map to assistant message")
        }

        if case let .command(_, executionID, command, status) = CodexEventDisplayMapper.displayEvent(
            from: .command(id: "cmd-1", command: "ls", status: .completed)
        ) {
            XCTAssertEqual(executionID, "cmd-1")
            XCTAssertEqual(command, "ls")
            XCTAssertEqual(status, .completed)
        } else {
            XCTFail("command should map to command display event")
        }
    }
}

private extension ConversationDisplayEvent {
    var displayText: String {
        switch self {
        case let .userPrompt(_, text), let .status(_, text), let .assistantMessage(_, text), let .error(_, text), let .parseWarning(_, text):
            return text
        case let .command(_, _, command, _):
            return command
        }
    }
}
```

- [ ] **Step 2: Write failing error-state tests**

Create `Tests/CodexPlusCoreTests/WorkbenchStateTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class WorkbenchStateTests: XCTestCase {
    func testWorkbenchErrorStateFactoryKeepsUserVisibleMessage() {
        let error = WorkbenchErrorState(
            title: "无法保存对话",
            message: "SQLite write failed",
            recoverySuggestion: "请检查磁盘空间后重试。"
        )

        XCTAssertFalse(error.id.uuidString.isEmpty)
        XCTAssertEqual(error.title, "无法保存对话")
        XCTAssertEqual(error.message, "SQLite write failed")
        XCTAssertEqual(error.recoverySuggestion, "请检查磁盘空间后重试。")
    }

    func testWorkbenchStateEmptyInitialState() {
        let state = WorkbenchState.empty

        XCTAssertTrue(state.workspaces.isEmpty)
        XCTAssertTrue(state.conversations.isEmpty)
        XCTAssertNil(state.activeWorkspaceID)
        XCTAssertNil(state.activeConversationID)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isShowingArchiveSearch)
    }
}
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test
```

Expected: compile failure mentioning missing `CodexEventDisplayMapper`, `WorkbenchState`, and `WorkbenchErrorState`.

- [ ] **Step 4: Add WorkbenchState and WorkbenchErrorState**

Create `Sources/CodexPlusCore/WorkbenchState.swift`:

```swift
import Foundation

public struct WorkbenchErrorState: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var message: String
    public var recoverySuggestion: String?

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        recoverySuggestion: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

public struct WorkbenchState: Equatable, Sendable {
    public var workspaces: [WorkspaceSessionGroup]
    public var conversations: [ConversationSession]
    public var activeWorkspaceID: UUID?
    public var activeConversationID: UUID?
    public var archiveSearchResults: [ConversationArchiveRecord]
    public var openedArchiveConversation: ConversationSession?
    public var isShowingArchiveSearch: Bool
    public var pendingArchiveConfirmationConversationID: UUID?
    public var isPinned: Bool
    public var error: WorkbenchErrorState?

    public static var empty: WorkbenchState {
        WorkbenchState()
    }

    public init(
        workspaces: [WorkspaceSessionGroup] = [],
        conversations: [ConversationSession] = [],
        activeWorkspaceID: UUID? = nil,
        activeConversationID: UUID? = nil,
        archiveSearchResults: [ConversationArchiveRecord] = [],
        openedArchiveConversation: ConversationSession? = nil,
        isShowingArchiveSearch: Bool = false,
        pendingArchiveConfirmationConversationID: UUID? = nil,
        isPinned: Bool = false,
        error: WorkbenchErrorState? = nil
    ) {
        self.workspaces = workspaces
        self.conversations = conversations
        self.activeWorkspaceID = activeWorkspaceID
        self.activeConversationID = activeConversationID
        self.archiveSearchResults = archiveSearchResults
        self.openedArchiveConversation = openedArchiveConversation
        self.isShowingArchiveSearch = isShowingArchiveSearch
        self.pendingArchiveConfirmationConversationID = pendingArchiveConfirmationConversationID
        self.isPinned = isPinned
        self.error = error
    }
}
```

- [ ] **Step 5: Add mapper**

Create `Sources/CodexPlusCore/CodexEventDisplayMapper.swift`:

```swift
import Foundation

public enum CodexEventDisplayMapper {
    public static func displayEvent(from event: CodexEvent) -> ConversationDisplayEvent {
        switch event {
        case let .threadStarted(threadID):
            return .status(id: UUID(), text: "Thread started: \(threadID)")
        case .turnStarted:
            return .status(id: UUID(), text: "Turn started")
        case .turnCompleted:
            return .status(id: UUID(), text: "Turn completed")
        case let .turnFailed(message):
            return .error(id: UUID(), text: message)
        case let .agentMessage(text):
            return .assistantMessage(id: UUID(), text: text)
        case let .command(id, command, status):
            return .command(id: UUID(), executionID: id, command: command, status: status)
        case let .error(text):
            return .error(id: UUID(), text: text)
        case let .raw(text):
            return .status(id: UUID(), text: text)
        case let .parseWarning(text):
            return .parseWarning(id: UUID(), text: text)
        }
    }
}
```

- [ ] **Step 6: Add error to WorkbenchSnapshot**

In `Sources/CodexPlusCore/WorkbenchModels.swift`, add `error` to `WorkbenchSnapshot`:

```swift
public struct WorkbenchSnapshot: Equatable, Sendable {
    public var projectCards: [WorkbenchProjectCard]
    public var activeConversation: ConversationSession?
    public var composerAction: WorkbenchComposerAction
    public var statusBar: WorkbenchStatusBarState
    public var canSubmitPrompt: Bool
    public var canStartNewConversation: Bool
    public var archiveSearchResults: [ConversationArchiveRecord]
    public var isPinned: Bool
    public var pendingArchiveConfirmationConversationID: UUID?
    public var isShowingArchiveSearch: Bool
    public var openedArchiveConversation: ConversationSession?
    public var error: WorkbenchErrorState?
}
```

Update its initializer to include `error: WorkbenchErrorState? = nil`.

- [ ] **Step 7: Replace duplicate display mappings**

In `WorkbenchStore`, replace calls to `Self.displayEvent(from:)` with:

```swift
CodexEventDisplayMapper.displayEvent(from: event)
```

Remove the private `displayEvent(from:)` function from `WorkbenchStore`.

In `ConversationCoordinator`, replace its private mapper implementation body with:

```swift
CodexEventDisplayMapper.displayEvent(from: event)
```

Keep the wrapper only if existing tests require the private function to remain unreachable. Prefer deleting the duplicate function if compile succeeds.

- [ ] **Step 8: Thread snapshot error through refreshSnapshot**

In `WorkbenchStore.refreshSnapshot()`, pass:

```swift
error: snapshot.error
```

until Task 4 replaces snapshot-derived state with `WorkbenchState`.

- [ ] **Step 9: Verify tests**

Run:

```bash
swift test
```

Expected: command exits 0.

- [ ] **Step 10: Commit**

```bash
git add Sources/CodexPlusCore Tests/CodexPlusCoreTests
git commit -m "refactor: centralize workbench state and event mapping"
```

---

### Task 3: Cut App Assembly Over To Workbench-Only Mainline

**Files:**
- Modify: `Sources/CodexPlusApp/AppDelegate.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`
- Option A Delete: `Sources/CodexPlusCore/ConversationCoordinator.swift`, `Sources/CodexPlusCore/CodexRunController.swift`, old side/compact app controllers when unused
- Option B Move: old files into `Sources/CodexPlusApp/Legacy/` and `Sources/CodexPlusCore/Legacy/`
- Create: `Tests/CodexPlusCoreTests/ArchitectureBoundaryTests.swift`

- [ ] **Step 1: Write architecture boundary tests**

Create `Tests/CodexPlusCoreTests/ArchitectureBoundaryTests.swift`:

```swift
import XCTest
import Foundation

final class ArchitectureBoundaryTests: XCTestCase {
    func testCoreSourcesDoNotImportAppFrameworks() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let coreURL = root.appendingPathComponent("Sources/CodexPlusCore", isDirectory: true)
        let files = try swiftFiles(under: coreURL)

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("import SwiftUI"), "\(file.path) must not import SwiftUI")
            XCTAssertFalse(text.contains("import AppKit"), "\(file.path) must not import AppKit")
        }
    }

    func testWindowCoordinatorDoesNotReferenceLegacyConversationRuntime() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let file = root.appendingPathComponent("Sources/CodexPlusApp/WindowCoordinator.swift")
        let text = try String(contentsOf: file, encoding: .utf8)

        XCTAssertFalse(text.contains("ConversationCoordinator"))
        XCTAssertFalse(text.contains("CodexRunController"))
        XCTAssertFalse(text.contains("showSidePanel"))
        XCTAssertFalse(text.contains("showCompactPanel"))
        XCTAssertFalse(text.contains("startCodexRun"))
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var result: [URL] = []
        for case let url as URL in enumerator ?? [] where url.pathExtension == "swift" {
            result.append(url)
        }
        return result
    }
}
```

- [ ] **Step 2: Run tests and verify boundary fails**

Run:

```bash
swift test
```

Expected: `testWindowCoordinatorDoesNotReferenceLegacyConversationRuntime` fails because `WindowCoordinator` still references legacy runtime.

- [ ] **Step 3: Simplify AppDelegate dependencies**

In `Sources/CodexPlusApp/AppDelegate.swift`, remove properties:

```swift
private let conversationCoordinator: ConversationCoordinator
private let codexRunner: ProcessCodexRunner
```

Make initialization construct only Workbench dependencies:

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowCoordinator: WindowCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let store = try makeWorkbenchStore()
            self.windowCoordinator = WindowCoordinator(
                batteryProvider: IOKitBatteryStatusProvider(),
                workbenchStore: store
            )
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
        }
    }
}
```

Keep the existing `makeWorkbenchStore()` body, but make it return a store backed by `CodexCLIEngine(runner: ProcessCodexRunner())`.

- [ ] **Step 4: Reduce WindowCoordinator to Workbench wiring**

Replace `Sources/CodexPlusApp/WindowCoordinator.swift` with a version that only wires Workbench and launcher:

```swift
import AppKit
import CodexPlusCore

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let workbenchStore: WorkbenchStore
    private let batteryMonitor: BatteryStatusMonitor
    private let codexUsageMonitor: CodexUsageMonitor
    private let dailyTokenUsageMonitor: DailyTokenUsageMonitor
    private let panelFactory = PanelFactory()
    private let screenProvider = ActiveScreenProvider()

    private lazy var workbenchPanelController = WorkbenchPanelController(
        panelFactory: panelFactory,
        screenProvider: screenProvider,
        store: workbenchStore,
        codexUsageMonitor: codexUsageMonitor,
        panelDelegate: self,
        onShow: { [weak self] in
            self?.workbenchLauncherPanelController.hide()
        },
        onHide: { [weak self] in
            self?.workbenchLauncherPanelController.show()
        }
    )

    private lazy var workbenchLauncherPanelController = WorkbenchLauncherPanelController(
        screenProvider: screenProvider,
        panelDelegate: self,
        onOpenWorkbench: { [weak self] in
            self?.showWorkbenchFromLauncher()
        }
    )

    init(
        batteryProvider: any BatteryStatusProviding,
        workbenchStore: WorkbenchStore
    ) {
        self.workbenchStore = workbenchStore
        self.batteryMonitor = BatteryStatusMonitor(provider: batteryProvider)
        self.codexUsageMonitor = CodexUsageMonitor(provider: LocalCodexUsageProvider())
        self.dailyTokenUsageMonitor = DailyTokenUsageMonitor(provider: LocalDailyTokenUsageProvider())

        super.init()
        codexUsageMonitor.start()
        dailyTokenUsageMonitor.start()
        workbenchLauncherPanelController.show()
    }

    func handleGlobalShortcut() {
        workbenchPanelController.toggle()
    }

    private func showWorkbenchFromLauncher() {
        workbenchLauncherPanelController.hide()
        workbenchPanelController.show()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? GlassPanel else {
            return
        }

        if workbenchPanelController.recordMove(of: panel) {
            return
        }

        if workbenchLauncherPanelController.recordMove(of: panel) {
            return
        }
    }
}
```

- [ ] **Step 5: Remove now-unused imports and references**

Run:

```bash
rg -n "ConversationCoordinator|CodexRunController|showSidePanel|showCompactPanel|startCodexRun" Sources/CodexPlusApp Sources/CodexPlusCore
```

Expected after cleanup: no matches in non-legacy files.

If `ConversationCoordinator` and `CodexRunController` are still referenced only by tests, move tests to legacy or delete the old test group in the same commit.

- [ ] **Step 6: Verify tests**

Run:

```bash
swift test
```

Expected: command exits 0.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "refactor: route app assembly through workbench only"
```

---

### Task 4: Extract Conversation Lifecycle And Project Selection

**Files:**
- Create: `Sources/CodexPlusCore/ProjectSelectionPolicy.swift`
- Create: `Sources/CodexPlusCore/ConversationLifecycleService.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchStore.swift`
- Create: `Tests/CodexPlusCoreTests/ProjectSelectionPolicyTests.swift`
- Create: `Tests/CodexPlusCoreTests/ConversationLifecycleServiceTests.swift`

- [ ] **Step 1: Write project selection policy tests**

Create `Tests/CodexPlusCoreTests/ProjectSelectionPolicyTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class ProjectSelectionPolicyTests: XCTestCase {
    func testFallbackSelectsFirstVisibleConversationInWorkspace() {
        let workspaceID = UUID()
        let visibleID = UUID()
        let archivedID = UUID()
        let workspace = WorkspaceSessionGroup(
            id: workspaceID,
            path: "/tmp/project",
            displayName: "project",
            conversationIDs: [archivedID, visibleID],
            lastActivityAt: Date(timeIntervalSince1970: 20)
        )
        let conversations = [
            ConversationSession(id: archivedID, title: "archived", prompt: "", workspacePath: "/tmp/project", isArchived: true),
            ConversationSession(id: visibleID, title: "visible", prompt: "", workspacePath: "/tmp/project")
        ]

        let selected = ProjectSelectionPolicy.firstVisibleConversationID(
            in: workspaceID,
            workspaces: [workspace],
            conversations: conversations
        )

        XCTAssertEqual(selected, visibleID)
    }

    func testClearingActiveConversationFallsBackInsideActiveWorkspace() {
        let workspaceID = UUID()
        let removedID = UUID()
        let nextID = UUID()
        var state = WorkbenchState.empty
        state.workspaces = [
            WorkspaceSessionGroup(
                id: workspaceID,
                path: "/tmp/project",
                displayName: "project",
                conversationIDs: [removedID, nextID],
                lastActivityAt: Date()
            )
        ]
        state.conversations = [
            ConversationSession(id: removedID, title: "removed", prompt: "", workspacePath: "/tmp/project", isArchived: true),
            ConversationSession(id: nextID, title: "next", prompt: "", workspacePath: "/tmp/project")
        ]
        state.activeWorkspaceID = workspaceID
        state.activeConversationID = removedID

        let updated = ProjectSelectionPolicy.repairActiveSelection(in: state)

        XCTAssertEqual(updated.activeWorkspaceID, workspaceID)
        XCTAssertEqual(updated.activeConversationID, nextID)
    }
}
```

- [ ] **Step 2: Write lifecycle service tests**

Create `Tests/CodexPlusCoreTests/ConversationLifecycleServiceTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class ConversationLifecycleServiceTests: XCTestCase {
    @MainActor
    func testCreateConversationPersistsProjectAndConversation() throws {
        let repository = MemoryLifecycleRepository()
        let service = ConversationLifecycleService(
            projectRepository: repository,
            conversationRepository: repository,
            titleGenerator: ConversationTitleGenerator(randomSuffixes: [1234])
        )

        let state = try service.createConversation(
            prompt: "build it",
            workspacePath: "/tmp/codex-plus",
            in: .empty
        )

        XCTAssertEqual(state.workspaces.count, 1)
        XCTAssertEqual(state.conversations.count, 1)
        XCTAssertEqual(state.activeConversationID, state.conversations.first?.id)
        XCTAssertEqual(repository.savedProjects.count, 1)
        XCTAssertEqual(repository.savedConversations.count, 1)
        XCTAssertEqual(state.conversations.first?.state, .running)
    }

    @MainActor
    func testSaveFailureDoesNotMutateState() {
        let repository = MemoryLifecycleRepository()
        repository.failSavingConversations = true
        let service = ConversationLifecycleService(
            projectRepository: repository,
            conversationRepository: repository,
            titleGenerator: ConversationTitleGenerator(randomSuffixes: [1234])
        )

        XCTAssertThrowsError(
            try service.createConversation(prompt: "build it", workspacePath: "/tmp/codex-plus", in: .empty)
        )
    }
}

private final class MemoryLifecycleRepository: ProjectRepository, ConversationRepository, @unchecked Sendable {
    var projects: [WorkspaceSessionGroup] = []
    var conversations: [ConversationSession] = []
    var savedProjects: [WorkspaceSessionGroup] = []
    var savedConversations: [ConversationSession] = []
    var failSavingConversations = false

    func saveProject(_ project: WorkspaceSessionGroup) throws {
        savedProjects.append(project)
        projects.removeAll { $0.id == project.id }
        projects.append(project)
    }

    func loadProjects() throws -> [WorkspaceSessionGroup] {
        projects
    }

    func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws {
        if failSavingConversations {
            throw WorkbenchDomainError.persistenceFailed("save conversation failed")
        }
        savedConversations.append(conversation)
        conversations.removeAll { $0.id == conversation.id }
        conversations.append(conversation)
    }

    func loadConversations() throws -> [ConversationSession] {
        conversations
    }

    func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isArchived = true
    }
}
```

- [ ] **Step 3: Add repository protocol files needed by service**

Create temporary protocol files if Task 6 has not yet split persistence:

```swift
public protocol ProjectRepository: Sendable {
    func saveProject(_ project: WorkspaceSessionGroup) throws
    func loadProjects() throws -> [WorkspaceSessionGroup]
}

public protocol ConversationRepository: Sendable {
    func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws
    func loadConversations() throws -> [ConversationSession]
    func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws
}
```

Make `CodexPlusRepository` inherit both protocols for compatibility:

```swift
public protocol CodexPlusRepository: ProjectRepository, ConversationRepository, Sendable {
    // existing archive, memory, and attachment methods remain here until Task 6.
}
```

- [ ] **Step 4: Implement ProjectSelectionPolicy**

Create `Sources/CodexPlusCore/ProjectSelectionPolicy.swift`:

```swift
import Foundation

public enum ProjectSelectionPolicy {
    public static func firstVisibleConversationID(
        in workspaceID: UUID,
        workspaces: [WorkspaceSessionGroup],
        conversations: [ConversationSession]
    ) -> UUID? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return nil
        }

        return workspace.conversationIDs.first { id in
            conversations.contains { $0.id == id && !$0.isArchived }
        }
    }

    public static func repairActiveSelection(in state: WorkbenchState) -> WorkbenchState {
        var updated = state

        if let activeConversationID = updated.activeConversationID,
           updated.conversations.contains(where: { $0.id == activeConversationID && !$0.isArchived }) {
            return updated
        }

        if let activeWorkspaceID = updated.activeWorkspaceID {
            updated.activeConversationID = firstVisibleConversationID(
                in: activeWorkspaceID,
                workspaces: updated.workspaces,
                conversations: updated.conversations
            )
            return updated
        }

        if let workspace = updated.workspaces.max(by: { $0.lastActivityAt < $1.lastActivityAt }) {
            updated.activeWorkspaceID = workspace.id
            updated.activeConversationID = firstVisibleConversationID(
                in: workspace.id,
                workspaces: updated.workspaces,
                conversations: updated.conversations
            )
        }

        return updated
    }
}
```

- [ ] **Step 5: Implement WorkbenchDomainError and ConversationLifecycleService**

Create `Sources/CodexPlusCore/ConversationLifecycleService.swift`:

```swift
import Foundation

public enum WorkbenchDomainError: Error, Equatable, CustomStringConvertible {
    case persistenceFailed(String)
    case conversationNotFound(UUID)
    case workspaceNotFound(String)

    public var description: String {
        switch self {
        case let .persistenceFailed(message):
            return message
        case let .conversationNotFound(id):
            return "Conversation not found: \(id)"
        case let .workspaceNotFound(path):
            return "Workspace not found: \(path)"
        }
    }
}

public final class ConversationLifecycleService: @unchecked Sendable {
    private let projectRepository: ProjectRepository
    private let conversationRepository: ConversationRepository
    private var titleGenerator: ConversationTitleGenerator

    public init(
        projectRepository: ProjectRepository,
        conversationRepository: ConversationRepository,
        titleGenerator: ConversationTitleGenerator = ConversationTitleGenerator()
    ) {
        self.projectRepository = projectRepository
        self.conversationRepository = conversationRepository
        self.titleGenerator = titleGenerator
    }

    public func loadInitialState() throws -> WorkbenchState {
        let workspaces = try projectRepository.loadProjects()
        let conversations = try conversationRepository.loadConversations()
        var state = WorkbenchState(workspaces: workspaces, conversations: conversations)
        state = ProjectSelectionPolicy.repairActiveSelection(in: state)
        return state
    }

    public func createConversation(
        prompt: String,
        workspacePath: String,
        in state: WorkbenchState
    ) throws -> WorkbenchState {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return state
        }

        let normalizedPath = ConversationWorkspacePolicy.normalizedPath(workspacePath)
        let now = Date()
        var next = state
        let workspace: WorkspaceSessionGroup

        if let existing = next.workspaces.first(where: { $0.path == normalizedPath }) {
            workspace = existing
        } else {
            workspace = WorkspaceSessionGroup(
                path: normalizedPath,
                displayName: ConversationWorkspacePolicy.displayName(for: normalizedPath),
                conversationIDs: [],
                lastActivityAt: now
            )
        }

        let session = ConversationSession(
            title: titleGenerator.nextTitle(existingTitles: next.conversations.map(\.title)),
            prompt: trimmedPrompt,
            workspacePath: normalizedPath,
            state: .running,
            permissionMode: .semiAutomatic,
            createdAt: now,
            lastActivityAt: now,
            events: [.userPrompt(id: UUID(), text: trimmedPrompt)]
        )

        var updatedWorkspace = workspace
        updatedWorkspace.conversationIDs.append(session.id)
        updatedWorkspace.lastActivityAt = now

        do {
            try projectRepository.saveProject(updatedWorkspace)
            try conversationRepository.saveConversation(session, projectID: updatedWorkspace.id)
        } catch {
            throw WorkbenchDomainError.persistenceFailed(String(describing: error))
        }

        next.workspaces.removeAll { $0.id == updatedWorkspace.id }
        next.workspaces.append(updatedWorkspace)
        next.conversations.append(session)
        next.activeWorkspaceID = updatedWorkspace.id
        next.activeConversationID = session.id
        next.isShowingArchiveSearch = false
        next.openedArchiveConversation = nil
        return next
    }
}
```

- [ ] **Step 6: Refactor WorkbenchStore to use lifecycle for createConversation**

Add to `WorkbenchStore` initializer:

```swift
private let lifecycle: ConversationLifecycleService
```

Initialize:

```swift
self.lifecycle = ConversationLifecycleService(
    projectRepository: repository,
    conversationRepository: repository
)
```

Change `startConversation(prompt:workspacePath:)` to call:

```swift
do {
    let nextState = try lifecycle.createConversation(
        prompt: prompt,
        workspacePath: workspacePath,
        in: currentStateFromStore()
    )
    apply(nextState)
    if let conversation = snapshot.activeConversation {
        startEngineRun(for: conversation.id, prompt: conversation.prompt)
    }
} catch {
    setError(title: "无法创建对话", error: error)
}
```

Implement `currentStateFromStore()` and `apply(_:)` as transition helpers. Keep old fields temporarily until Task 5 moves all mutable state into `WorkbenchState`.

- [ ] **Step 7: Verify tests**

Run:

```bash
swift test
```

Expected: command exits 0.

- [ ] **Step 8: Commit**

```bash
git add Sources/CodexPlusCore Tests/CodexPlusCoreTests
git commit -m "refactor: extract conversation lifecycle policy"
```

---

### Task 5: Extract Run Orchestrator And Visible Error Flow

**Files:**
- Create: `Sources/CodexPlusCore/ConversationRunOrchestrator.swift`
- Modify: `Sources/CodexPlusCore/WorkbenchStore.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchStatusBarView.swift`
- Create: `Tests/CodexPlusCoreTests/ConversationRunOrchestratorTests.swift`
- Modify: `Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift`

- [ ] **Step 1: Write run orchestrator tests**

Create `Tests/CodexPlusCoreTests/ConversationRunOrchestratorTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class ConversationRunOrchestratorTests: XCTestCase {
    @MainActor
    func testStartStoresHandleAndForwardsEvents() {
        let engine = ManualRunEngine()
        let orchestrator = ConversationRunOrchestrator(engine: engine)
        let conversationID = UUID()
        let conversation = ConversationSession(
            id: conversationID,
            title: "Run",
            prompt: "prompt",
            workspacePath: "/tmp/project",
            state: .running
        )
        var events: [ConversationDisplayEvent] = []
        var finishes: [CodexRunResult] = []

        XCTAssertNoThrow(try orchestrator.start(
            conversation: conversation,
            prompt: "prompt",
            onEvent: { events.append($0) },
            onFinish: { finishes.append($0) }
        ))

        XCTAssertTrue(orchestrator.isRunning(conversationID: conversationID))
        engine.emit(.agentMessage("hello"), for: conversationID)
        engine.finish(CodexRunResult(exitCode: 0, stderr: ""), for: conversationID)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(finishes, [CodexRunResult(exitCode: 0, stderr: "")])
        XCTAssertFalse(orchestrator.isRunning(conversationID: conversationID))
    }

    @MainActor
    func testStopCallsUnderlyingHandle() throws {
        let engine = ManualRunEngine()
        let orchestrator = ConversationRunOrchestrator(engine: engine)
        let conversationID = UUID()
        let conversation = ConversationSession(
            id: conversationID,
            title: "Run",
            prompt: "prompt",
            workspacePath: "/tmp/project",
            state: .running
        )

        try orchestrator.start(conversation: conversation, prompt: "prompt", onEvent: { _ in }, onFinish: { _ in })

        XCTAssertTrue(orchestrator.stop(conversationID: conversationID))
        XCTAssertEqual(engine.stopCount, 1)
    }
}

private final class ManualRunEngine: ExecutionEngine, @unchecked Sendable {
    final class Handle: ExecutionHandle, @unchecked Sendable {
        let onStop: () -> Void
        init(onStop: @escaping () -> Void) { self.onStop = onStop }
        func stop() { onStop() }
    }

    var callbacks: [UUID: (event: (CodexEvent) -> Void, finish: (CodexRunResult) -> Void)] = [:]
    var stopCount = 0

    func start(
        request: ExecutionRequest,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> ExecutionHandle {
        callbacks[request.sessionID] = (onEvent, onFinish)
        return Handle { [weak self] in self?.stopCount += 1 }
    }

    func emit(_ event: CodexEvent, for id: UUID) {
        callbacks[id]?.event(event)
    }

    func finish(_ result: CodexRunResult, for id: UUID) {
        callbacks[id]?.finish(result)
    }
}
```

- [ ] **Step 2: Implement ConversationRunOrchestrator**

Create `Sources/CodexPlusCore/ConversationRunOrchestrator.swift`:

```swift
import Foundation

@MainActor
public final class ConversationRunOrchestrator {
    private let engine: ExecutionEngine
    private var activeHandles: [UUID: ExecutionHandle] = [:]

    public init(engine: ExecutionEngine) {
        self.engine = engine
    }

    public func start(
        conversation: ConversationSession,
        prompt: String,
        onEvent: @escaping (ConversationDisplayEvent) -> Void,
        onFinish: @escaping (CodexRunResult) -> Void
    ) throws {
        guard activeHandles[conversation.id] == nil else {
            throw WorkbenchDomainError.persistenceFailed("Conversation is already running.")
        }

        let request = ExecutionRequest(
            prompt: prompt,
            permissionMode: conversation.permissionMode,
            sessionID: conversation.id,
            workingDirectoryURL: URL(fileURLWithPath: conversation.workspacePath, isDirectory: true)
        )

        let handle = engine.start(
            request: request,
            onEvent: { event in
                Task { @MainActor in
                    onEvent(CodexEventDisplayMapper.displayEvent(from: event))
                }
            },
            onFinish: { [weak self] result in
                Task { @MainActor in
                    self?.activeHandles[conversation.id] = nil
                    onFinish(result)
                }
            }
        )

        activeHandles[conversation.id] = handle
    }

    public func stop(conversationID: UUID) -> Bool {
        guard let handle = activeHandles.removeValue(forKey: conversationID) else {
            return false
        }

        handle.stop()
        return true
    }

    public func isRunning(conversationID: UUID) -> Bool {
        activeHandles[conversationID] != nil
    }
}
```

- [ ] **Step 3: Add store error helpers**

In `WorkbenchStore`, add:

```swift
public func clearError() {
    snapshot.error = nil
    refreshSnapshot()
}

private func setError(title: String, message: String, recoverySuggestion: String? = nil) {
    snapshot.error = WorkbenchErrorState(
        title: title,
        message: message,
        recoverySuggestion: recoverySuggestion
    )
    refreshSnapshot()
}

private func setError(title: String, error: Error, recoverySuggestion: String? = nil) {
    setError(
        title: title,
        message: String(describing: error),
        recoverySuggestion: recoverySuggestion
    )
}
```

Replace silent `return` paths in `submitPrompt()`, `saveProject()`, `saveConversation()`, and `searchArchives(_:)` with `setError(...)` calls.

- [ ] **Step 4: Wire WorkbenchStore through orchestrator**

Replace `activeHandles` and direct `engine.start` handling with:

```swift
private let runOrchestrator: ConversationRunOrchestrator
```

Initialize:

```swift
self.runOrchestrator = ConversationRunOrchestrator(engine: engine)
```

Update `startEngineRun(for:prompt:)`:

```swift
private func startEngineRun(for conversationID: UUID, prompt: String) {
    guard let conversation = conversations.first(where: { $0.id == conversationID }) else {
        return
    }

    do {
        try runOrchestrator.start(
            conversation: conversation,
            prompt: prompt,
            onEvent: { [weak self] event in
                self?.appendEvent(event, to: conversationID)
            },
            onFinish: { [weak self] result in
                self?.finishRun(for: conversationID, result: result)
            }
        )
    } catch {
        setError(title: "无法启动 Codex", error: error)
    }
}
```

Update `stopRun(for:)` so persistence succeeds before process stop:

```swift
guard persistUpdatedConversation(conversationID, mutation: { session in
    session.state = .stopped
}) else {
    setError(title: "无法停止任务", message: "对话状态保存失败，任务仍在运行。")
    return false
}

_ = runOrchestrator.stop(conversationID: conversationID)
refreshSnapshot()
return true
```

- [ ] **Step 5: Show error in Workbench UI**

In `WorkbenchView`, insert an error banner above the conversation area:

```swift
if let error = store.snapshot.error {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
        VStack(alignment: .leading, spacing: 2) {
            Text(error.title)
                .font(.caption.weight(.semibold))
            Text(error.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        Spacer(minLength: 8)
        Button(action: { store.clearError() }) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭错误提示")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}
```

- [ ] **Step 6: Verify tests**

Run:

```bash
swift test
```

Expected: command exits 0.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusCore Sources/CodexPlusApp/Workbench Tests/CodexPlusCoreTests
git commit -m "refactor: extract run orchestration and expose workbench errors"
```

---

### Task 6: Split Repository And Event Codec

**Files:**
- Create: `Sources/CodexPlusCore/Persistence/ProjectRepository.swift`
- Create: `Sources/CodexPlusCore/Persistence/ConversationRepository.swift`
- Create: `Sources/CodexPlusCore/Persistence/ArchiveRepository.swift`
- Create: `Sources/CodexPlusCore/Persistence/MemoryRepository.swift`
- Create: `Sources/CodexPlusCore/Persistence/AttachmentRepository.swift`
- Create: `Sources/CodexPlusCore/Persistence/ConversationEventCodec.swift`
- Create: `Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift`
- Modify: `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
- Modify: `Tests/CodexPlusCoreTests/PersistenceTests.swift`
- Create: `Tests/CodexPlusCoreTests/ConversationEventCodecTests.swift`

- [ ] **Step 1: Write event codec tests**

Create `Tests/CodexPlusCoreTests/ConversationEventCodecTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class ConversationEventCodecTests: XCTestCase {
    func testRoundTripsSupportedEvents() throws {
        let events: [ConversationDisplayEvent] = [
            .userPrompt(id: UUID(), text: "hello"),
            .status(id: UUID(), text: "running"),
            .assistantMessage(id: UUID(), text: "done"),
            .command(id: UUID(), executionID: "exec-1", command: "ls", status: .completed),
            .error(id: UUID(), text: "failed"),
            .parseWarning(id: UUID(), text: "bad json")
        ]

        for (index, event) in events.enumerated() {
            let encoded = try ConversationEventCodec.encode(event, ordinal: index, fallbackDate: Date(timeIntervalSince1970: 1))
            let decoded = try ConversationEventCodec.decode(kind: encoded.kind, payloadJSON: encoded.payloadJSON)
            XCTAssertEqual(decoded, event)
            XCTAssertEqual(encoded.ordinal, index)
            XCTAssertFalse(encoded.searchableText.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Create repository protocols**

Move protocol declarations from Task 4 into separate files and remove duplicated temporary declarations.

`ProjectRepository.swift`:

```swift
import Foundation

public protocol ProjectRepository: Sendable {
    func saveProject(_ project: WorkspaceSessionGroup) throws
    func loadProjects() throws -> [WorkspaceSessionGroup]
}
```

Repeat the exact protocol shapes from the design document for conversation, archive, memory, and attachment repositories.

- [ ] **Step 3: Implement ConversationEventCodec**

Create `ConversationEventCodec.swift` with `PersistedConversationEvent` and `Codable` payloads:

```swift
import Foundation

public struct PersistedConversationEvent: Equatable, Sendable {
    public var id: String
    public var ordinal: Int
    public var kind: String
    public var displayText: String
    public var payloadJSON: String
    public var rawPayloadJSON: String?
    public var createdAt: Date
    public var searchableText: String
}

public enum ConversationEventCodec {
    public static func encode(
        _ event: ConversationDisplayEvent,
        ordinal: Int,
        fallbackDate: Date
    ) throws -> PersistedConversationEvent {
        let createdAt = fallbackDate.addingTimeInterval(Double(ordinal) / 1000.0)

        switch event {
        case let .userPrompt(id, text):
            return try record(id: id, ordinal: ordinal, kind: "user_prompt", text: text, payload: TextPayload(id: id, text: text), createdAt: createdAt)
        case let .status(id, text):
            return try record(id: id, ordinal: ordinal, kind: "status", text: text, payload: TextPayload(id: id, text: text), createdAt: createdAt)
        case let .assistantMessage(id, text):
            return try record(id: id, ordinal: ordinal, kind: "assistant_message", text: text, payload: TextPayload(id: id, text: text), createdAt: createdAt)
        case let .command(id, executionID, command, status):
            return try record(id: id, ordinal: ordinal, kind: "command", text: command, payload: CommandPayload(id: id, executionID: executionID, command: command, status: status), createdAt: createdAt)
        case let .error(id, text):
            return try record(id: id, ordinal: ordinal, kind: "error", text: text, payload: TextPayload(id: id, text: text), createdAt: createdAt)
        case let .parseWarning(id, text):
            return try record(id: id, ordinal: ordinal, kind: "parse_warning", text: text, payload: TextPayload(id: id, text: text), createdAt: createdAt)
        }
    }

    public static func decode(kind: String, payloadJSON: String) throws -> ConversationDisplayEvent {
        let data = Data(payloadJSON.utf8)
        let decoder = JSONDecoder()

        switch kind {
        case "user_prompt":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .userPrompt(id: payload.id, text: payload.text)
        case "status":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .status(id: payload.id, text: payload.text)
        case "assistant_message":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .assistantMessage(id: payload.id, text: payload.text)
        case "command":
            let payload = try decoder.decode(CommandPayload.self, from: data)
            return .command(id: payload.id, executionID: payload.executionID, command: payload.command, status: payload.status)
        case "error":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .error(id: payload.id, text: payload.text)
        case "parse_warning":
            let payload = try decoder.decode(TextPayload.self, from: data)
            return .parseWarning(id: payload.id, text: payload.text)
        default:
            throw RepositoryError.invalidEventKind(kind)
        }
    }

    private static func record<Payload: Encodable>(
        id: UUID,
        ordinal: Int,
        kind: String,
        text: String,
        payload: Payload,
        createdAt: Date
    ) throws -> PersistedConversationEvent {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return PersistedConversationEvent(
            id: id.uuidString.lowercased(),
            ordinal: ordinal,
            kind: kind,
            displayText: text,
            payloadJSON: String(decoding: data, as: UTF8.self),
            rawPayloadJSON: nil,
            createdAt: createdAt,
            searchableText: text
        )
    }
}

private struct TextPayload: Codable {
    var id: UUID
    var text: String
}

private struct CommandPayload: Codable {
    var id: UUID
    var executionID: String?
    var command: String
    var status: CodexCommandStatus

    enum CodingKeys: String, CodingKey {
        case id
        case executionID = "execution_id"
        case command
        case status
    }
}
```

If `RepositoryError` is private in the old repository file, move only the cases needed by codec into a new internal error enum named `ConversationEventCodecError`.

- [ ] **Step 4: Replace repository inline codec**

In `SQLiteCodexPlusRepository.saveConversation`, replace `EncodedConversationEvent(...)` with:

```swift
let record = try ConversationEventCodec.encode(event, ordinal: ordinal, fallbackDate: conversation.createdAt)
```

In `loadConversations`, replace `DecodedConversationEvent(row:).event` with:

```swift
try ConversationEventCodec.decode(
    kind: try text(for: "kind", in: row),
    payloadJSON: try text(for: "payload_json", in: row)
)
```

Delete old `EncodedConversationEvent` and `DecodedConversationEvent`.

- [ ] **Step 5: Introduce SQLiteCodexPlusStore facade**

Create `SQLiteCodexPlusStore.swift`:

```swift
import Foundation

public final class SQLiteCodexPlusStore: ProjectRepository, ConversationRepository, ArchiveRepository, MemoryRepository, AttachmentRepository, @unchecked Sendable {
    private let repository: SQLiteCodexPlusRepository

    public init(database: SQLiteDatabase) {
        self.repository = SQLiteCodexPlusRepository(database: database)
    }

    public func saveProject(_ project: WorkspaceSessionGroup) throws { try repository.saveProject(project) }
    public func loadProjects() throws -> [WorkspaceSessionGroup] { try repository.loadProjects() }
    public func saveConversation(_ conversation: ConversationSession, projectID: UUID) throws { try repository.saveConversation(conversation, projectID: projectID) }
    public func loadConversations() throws -> [ConversationSession] { try repository.loadConversations() }
    public func markConversationArchived(_ id: UUID, archiveMarkdownPath: String, archivedAt: Date) throws { try repository.markConversationArchived(id, archiveMarkdownPath: archiveMarkdownPath, archivedAt: archivedAt) }
    public func saveArchiveRecord(_ record: ConversationArchiveRecord) throws { try repository.saveArchiveRecord(record) }
    public func searchArchiveRecords(query: String) throws -> [ConversationArchiveRecord] { try repository.searchArchiveRecords(query: query) }
    public func archiveConversation(record: ConversationArchiveRecord, archiveMarkdownPath: String, archivedAt: Date) throws { try repository.archiveConversation(record: record, archiveMarkdownPath: archiveMarkdownPath, archivedAt: archivedAt) }
    public func saveMemoryCard(_ card: MemoryCard) throws { try repository.saveMemoryCard(card) }
    public func loadMemoryCards(scope: String?) throws -> [MemoryCard] { try repository.loadMemoryCards(scope: scope) }
    public func deleteMemoryCard(_ id: UUID) throws { try repository.deleteMemoryCard(id) }
    public func saveMemorySource(_ source: MemorySource) throws { try repository.saveMemorySource(source) }
    public func loadMemorySources(memoryCardID: UUID) throws -> [MemorySource] { try repository.loadMemorySources(memoryCardID: memoryCardID) }
    public func deleteMemorySource(_ id: UUID) throws { try repository.deleteMemorySource(id) }
    public func saveAttachment(_ attachment: CodexPlusAttachment) throws { try repository.saveAttachment(attachment) }
    public func loadAttachments(ownerKind: String, ownerID: UUID?) throws -> [CodexPlusAttachment] { try repository.loadAttachments(ownerKind: ownerKind, ownerID: ownerID) }
    public func deleteAttachment(_ id: UUID) throws { try repository.deleteAttachment(id) }
}
```

This facade keeps the task small. Split SQL into smaller store files in a follow-up commit inside this same task if tests remain green after the facade.

- [ ] **Step 6: Verify tests**

Run:

```bash
swift test
```

Expected: command exits 0.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusCore/Persistence Tests/CodexPlusCoreTests
git commit -m "refactor: split persistence protocols and event codec"
```

---

### Task 7: Replace Brittle Source-String Tests With Behavior Tests

**Files:**
- Modify: `Tests/CodexPlusCoreTests/main.swift` if still present
- Modify: `Tests/CodexPlusCoreTests/WorkbenchProjectionTests.swift`
- Modify: `Tests/CodexPlusCoreTests/WorkbenchStoreTests.swift`
- Modify: `Tests/CodexPlusCoreTests/ArchitectureBoundaryTests.swift`

- [ ] **Step 1: Find source-string assertions**

Run:

```bash
rg -n "String\\(contentsOf|text\\.contains|contains\\(" Tests/CodexPlusCoreTests
```

Expected: shows existing brittle tests.

- [ ] **Step 2: Classify each source-string assertion**

For each match, put it into one of these buckets:

```text
KEEP_BOUNDARY: target import/reference boundary that cannot be tested through public behavior
REPLACE_BEHAVIOR: product behavior, policy output, snapshot state, persistence round trip
DELETE_DUPLICATE: already covered by a behavior test
```

Store the classification as comments in the test file next to the block being changed, then remove those comments before committing.

- [ ] **Step 3: Replace Workbench source checks with snapshot tests**

For checks that assert Workbench UI/store wiring, add tests in `WorkbenchStoreTests.swift`:

```swift
@MainActor
func testWorkbenchSnapshotExposesRunningComposerState() {
    withSQLiteRepositoryTest("running composer state") { _, repository in
        let engine = ManualExecutionEngine()
        let store = WorkbenchStore(repository: repository, engine: engine)

        store.startConversation(prompt: "start", workspacePath: "/tmp/codex-plus")

        expect(store.snapshot.activeConversation?.state == .running, "snapshot exposes running conversation")
        expect(store.snapshot.composerAction == .stop, "running snapshot uses stop composer action")
        expect(!store.snapshot.canStartNewConversation, "running snapshot disables new conversation")
    }
}
```

Add this function to the active XCTest runner if the file still uses function suites.

- [ ] **Step 4: Keep only boundary source checks**

In `ArchitectureBoundaryTests`, keep only:

```swift
XCTAssertFalse(text.contains("import SwiftUI"))
XCTAssertFalse(text.contains("import AppKit"))
XCTAssertFalse(text.contains("ConversationCoordinator"))
XCTAssertFalse(text.contains("CodexRunController"))
```

Delete source checks about specific private method names, SwiftUI modifiers, literal colors, exact button labels, and exact file existence unless they protect a target boundary.

- [ ] **Step 5: Verify no broad source-string tests remain**

Run:

```bash
rg -n "String\\(contentsOf|text\\.contains" Tests/CodexPlusCoreTests
```

Expected: only `ArchitectureBoundaryTests.swift` matches.

- [ ] **Step 6: Verify tests**

Run:

```bash
swift test
```

Expected: command exits 0.

- [ ] **Step 7: Commit**

```bash
git add Tests/CodexPlusCoreTests
git commit -m "test: replace brittle source checks with behavior coverage"
```

---

### Task 8: Group Workbench Actions, Metrics, Strings, And Command Configuration

**Files:**
- Create: `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`
- Create: `Sources/CodexPlusApp/Workbench/WorkbenchMetrics.swift`
- Create: `Sources/CodexPlusApp/Workbench/WorkbenchStrings.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchComposerView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift`
- Modify: `Sources/CodexPlusCore/CodexCommandBuilder.swift`
- Create: `Sources/CodexPlusCore/CodexCommandConfiguration.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift` or XCTest suite

- [ ] **Step 1: Write command configuration test**

Add to command builder tests:

```swift
func testCodexCommandBuilderUsesDefaultConfiguration() {
    XCTAssertEqual(
        CodexCommandBuilder.arguments(prompt: "List files", permissionMode: .semiAutomatic),
        ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only", "--", "List files"]
    )
    XCTAssertEqual(
        CodexCommandBuilder.arguments(prompt: "List files", permissionMode: .fullAccess),
        ["exec", "--json", "--skip-git-repo-check", "--sandbox", "danger-full-access", "--", "List files"]
    )
}

func testCodexCommandBuilderAcceptsCustomConfiguration() {
    let configuration = CodexCommandConfiguration(
        skipGitRepoCheck: false,
        sandboxByPermissionMode: [.semiAutomatic: "workspace-write", .fullAccess: "danger-full-access"],
        extraArguments: ["--model", "gpt-5-codex"]
    )

    XCTAssertEqual(
        CodexCommandBuilder.arguments(prompt: "Run", permissionMode: .semiAutomatic, configuration: configuration),
        ["exec", "--json", "--model", "gpt-5-codex", "--sandbox", "workspace-write", "--", "Run"]
    )
}
```

- [ ] **Step 2: Add CodexCommandConfiguration**

Create `Sources/CodexPlusCore/CodexCommandConfiguration.swift`:

```swift
import Foundation

public struct CodexCommandConfiguration: Equatable, Sendable {
    public var skipGitRepoCheck: Bool
    public var sandboxByPermissionMode: [PermissionMode: String]
    public var extraArguments: [String]

    public static let `default` = CodexCommandConfiguration(
        skipGitRepoCheck: true,
        sandboxByPermissionMode: [
            .semiAutomatic: "read-only",
            .fullAccess: "danger-full-access"
        ],
        extraArguments: []
    )

    public init(
        skipGitRepoCheck: Bool,
        sandboxByPermissionMode: [PermissionMode: String],
        extraArguments: [String]
    ) {
        self.skipGitRepoCheck = skipGitRepoCheck
        self.sandboxByPermissionMode = sandboxByPermissionMode
        self.extraArguments = extraArguments
    }
}
```

Update `CodexCommandBuilder.arguments`:

```swift
public static func arguments(
    prompt: String,
    permissionMode: PermissionMode,
    configuration: CodexCommandConfiguration = .default
) -> [String] {
    var arguments = ["exec", "--json"]
    if configuration.skipGitRepoCheck {
        arguments.append("--skip-git-repo-check")
    }
    arguments.append(contentsOf: configuration.extraArguments)
    arguments.append("--sandbox")
    arguments.append(configuration.sandboxByPermissionMode[permissionMode] ?? sandboxValue(for: permissionMode))
    arguments.append("--")
    arguments.append(prompt)
    return arguments
}
```

- [ ] **Step 3: Add Workbench action groups**

Create `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`:

```swift
import Foundation

struct WorkbenchActions {
    var projectStrip: ProjectStripActions
    var conversation: ConversationActions
    var composer: ComposerActions
    var archive: ArchiveActions
}

struct ProjectStripActions {
    let newConversation: () -> Void
    let returnToConversation: () -> Void
    let openArchive: () -> Void
    let togglePin: () -> Void
    let selectProject: (UUID) -> Void
    let selectConversation: (UUID) -> Void
}

struct ConversationActions {
    let archiveConversation: (UUID) -> Void
}

struct ComposerActions {
    let send: (String) -> Void
    let pickWorkspace: () -> Void
    let clearWorkspace: () -> Void
    let stop: () -> Void
}

struct ArchiveActions {
    let search: (String) -> Void
    let open: (UUID) -> Void
}
```

- [ ] **Step 4: Add metrics and strings**

Create `WorkbenchMetrics.swift`:

```swift
import Foundation

enum WorkbenchMetrics {
    static let scenePadding = 18.0
    static let verticalSpacing = 6.0
    static let conversationCornerRadius = 24.0
    static let composerCornerRadius = 22.0
    static let errorCornerRadius = 12.0
    static let composerControlHeight = 30.0
}
```

Create `WorkbenchStrings.swift`:

```swift
enum WorkbenchStrings {
    static let newConversation = "新对话"
    static let archived = "已归档"
    static let emptyConversationTitle = "暂无活动对话"
    static let emptyConversationSubtitle = "新对话"
    static let chooseWorkspace = "选择工作目录"
    static let clearWorkspace = "清除工作目录"
    static let continueInput = "继续输入"
    static let closeError = "关闭错误提示"
}
```

- [ ] **Step 5: Refactor WorkbenchView to pass grouped actions**

In `WorkbenchView`, create:

```swift
private var actions: WorkbenchActions {
    WorkbenchActions(
        projectStrip: ProjectStripActions(
            newConversation: { store.beginNewConversationDraft() },
            returnToConversation: { store.returnToConversationPage() },
            openArchive: { store.showArchiveSearch() },
            togglePin: { store.togglePin() },
            selectProject: { store.selectProject($0) },
            selectConversation: { store.selectConversation($0) }
        ),
        conversation: ConversationActions(
            archiveConversation: { _ = store.archiveConversation($0) }
        ),
        composer: ComposerActions(
            send: { store.submitPrompt($0) },
            pickWorkspace: pickWorkspace,
            clearWorkspace: { store.clearDraftWorkspaceSelection() },
            stop: { store.stopActiveRun() }
        ),
        archive: ArchiveActions(
            search: { store.searchArchives($0) },
            open: { store.openArchive($0) }
        )
    )
}
```

Update child views to receive the action subset they need. Keep public behavior unchanged.

- [ ] **Step 6: Replace scattered literals**

Replace Workbench literals with `WorkbenchMetrics` and `WorkbenchStrings` only in Workbench files touched by this task. Do not modify legacy compact/side panel UI.

- [ ] **Step 7: Verify tests**

Run:

```bash
swift test
```

Expected: command exits 0.

- [ ] **Step 8: Commit**

```bash
git add Sources/CodexPlusApp/Workbench Sources/CodexPlusCore Tests/CodexPlusCoreTests
git commit -m "refactor: group workbench actions and configuration"
```

---

### Task 9: Final Cleanup And Verification

**Files:**
- Modify: files touched by cleanup only
- Modify: `docs/superpowers/manual-tests/2026-07-07-codex-plus-architecture-remediation.md`

- [ ] **Step 1: Search for legacy mainline references**

Run:

```bash
rg -n "ConversationCoordinator|CodexRunController|Legacy|showSidePanel|showCompactPanel|startCodexRun" Sources
```

Expected:

- No matches for old names in production mainline.
- If `Legacy` matches exist, they are under `Sources/**/Legacy/` and not referenced from `AppDelegate.swift` or `WindowCoordinator.swift`.

- [ ] **Step 2: Check file sizes**

Run:

```bash
wc -l Sources/CodexPlusCore/WorkbenchStore.swift Sources/CodexPlusApp/WindowCoordinator.swift Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift
```

Expected targets:

```text
WorkbenchStore.swift: about 200-300 lines
WindowCoordinator.swift: about 120-180 lines
CodexPlusRepository.swift: substantially smaller than original 984 lines, or reduced to compatibility facade
```

If a file misses the target by a small margin, leave it if responsibilities are clear. If a file remains near the original size and still has mixed responsibilities, split before finishing.

- [ ] **Step 3: Add manual test checklist**

Create `docs/superpowers/manual-tests/2026-07-07-codex-plus-architecture-remediation.md`:

```markdown
# Codex Plus Architecture Remediation Manual Test

Date: 2026-07-07

## Checklist

- [ ] Launch app and verify launcher appears.
- [ ] Click launcher and verify Workbench opens.
- [ ] Press global shortcut and verify Workbench toggles.
- [ ] Start a new conversation with no selected workspace and verify a generated workspace is used.
- [ ] Start a new conversation with selected workspace and verify Codex runs in that directory.
- [ ] While running, verify composer shows stop.
- [ ] Stop a running task and verify conversation becomes stopped.
- [ ] Complete a task and verify follow-up is enabled.
- [ ] Archive a completed conversation and verify it disappears from active cards.
- [ ] Search archives and reopen archived conversation read-only.
- [ ] Trigger a persistence or workspace error if practical and verify an error banner appears.
```

- [ ] **Step 4: Run full automated verification**

Run:

```bash
swift test
```

Expected: command exits 0.

Run:

```bash
swift build
```

Expected: command exits 0.

- [ ] **Step 5: Review git diff**

Run:

```bash
git diff --stat
git diff -- Package.swift Sources Tests docs/superpowers/manual-tests
```

Expected:

- No accidental edits to `archives/`.
- No unrelated formatting churn outside touched files.
- No debug prints.
- No debug markers or incomplete-work markers.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests docs/superpowers/manual-tests
git commit -m "refactor: complete architecture remediation"
```

---

## Execution Notes

- Prefer one commit per task.
- Keep each commit buildable.
- If a task grows too large, split it only along the boundaries already named in this plan.
- Do not begin Task 6 repository SQL file splitting until Tasks 1-5 are green.
- Do not start async execution redesign until the Workbench-only mainline and error flow are green.

## Self-Review

Spec coverage:

- P0 two execution chains: Task 3 removes mainline legacy references.
- P0 `WorkbenchStore` overgrowth: Tasks 4 and 5 extract lifecycle, selection, and run orchestration.
- P1 repository overwidth: Task 6 splits protocols and codec.
- P1 invisible errors: Tasks 2 and 5 add error state and UI display.
- P1 non-standard tests: Task 1 converts to `swift test`; Task 7 removes brittle source tests.
- P1 App coordinator overgrowth: Task 3 reduces `WindowCoordinator`.
- P2 naming drift: Task 3 isolates or deletes legacy names; Task 8 adds mainline action/config names.
- P2 GCD/lock risk: Task 5 removes `CodexRunController` from mainline; async redesign is intentionally deferred until after mainline cleanup.
- P2 long UI action lists: Task 8 introduces grouped actions.
- P3 strings/metrics/config: Task 8 centralizes Workbench strings, metrics, and Codex command config.

Placeholder scan:

- This plan contains no incomplete-work markers or unspecified implementation slots.
- Every task has files, concrete commands, expected results, and commit command.

Type consistency:

- `WorkbenchErrorState`, `WorkbenchState`, `CodexEventDisplayMapper`, `ConversationLifecycleService`, `ProjectSelectionPolicy`, and `ConversationRunOrchestrator` are introduced before dependent tasks use them.
- Repository protocol names used by lifecycle tests match Task 6 final protocol names.
