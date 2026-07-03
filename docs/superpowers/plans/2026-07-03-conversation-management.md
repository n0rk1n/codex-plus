# Conversation Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two-level workspace/conversation tab management with parallel Codex runs, optional workspace selection, default workspace creation, archive actions, and draggable ordering.

**Architecture:** Keep workspace grouping, tab selection, ordering, title generation, and archive fallback in `CodexPlusCore` so behavior is testable without AppKit. Keep filesystem directory picking/creation, process start/stop, confirmation alerts, and panel animation in `CodexPlusApp`. Change the runner layer from one active run to a per-conversation run registry.

**Tech Stack:** Swift 6 package, SwiftUI, AppKit, Combine, `Process`, existing executable test target `CodexPlusCoreTests`.

## Global Constraints

- Default workspace parent is exactly `~/Documents/Codex Plus Workspace`.
- Default workspace child directory format is exactly `YYYY-MM-DD-random`, for example `2026-07-03-4821`.
- Conversation titles use `对话_1234`-style random names.
- Directory selection is optional before the first prompt.
- After the first prompt is sent, the conversation workspace is fixed.
- Workspace tabs and conversation tabs are both draggable.
- Conversation tabs archive instead of close.
- The archive icon appears on the left side of each conversation tab.
- Multiple conversations can run in parallel.
- Do not build the archive manager UI.
- Do not persist history across app launches.
- Do not add Codex Desktop Local/Worktree/Cloud mode selection.
- Do not add worktree creation.
- Do not add smart conversation titles.
- Do not add cross-workspace conversation drag and drop.
- Do not add conversation search.
- Do not add new package dependencies.

---

## File Structure

- Modify `Sources/CodexPlusCore/ConversationModels.swift`
  - Add workspace, draft, snapshot, archive result, and title/default-directory policy models.
  - Extend `ConversationSession` with title, workspace path, timestamps, and archive state.

- Modify `Sources/CodexPlusCore/ConversationCoordinator.swift`
  - Replace single-active-conversation storage with workspace groups, conversations, draft state, active workspace ID, and active conversation ID.
  - Keep compatibility accessors such as `activeConversation` and existing event mutation methods.

- Modify `Sources/CodexPlusCore/ProcessCodexRunner.swift`
  - Add an optional `workingDirectoryURL` parameter to `run`.
  - Set `Process.currentDirectoryURL` when provided.

- Modify `Sources/CodexPlusCore/CodexRunController.swift`
  - Replace the single active handle with a dictionary keyed by conversation ID.
  - Add `isRunning(sessionID:)` while preserving aggregate `isRunning`.

- Modify `Sources/CodexPlusApp/PermissionPrompter.swift`
  - Rename the running-close confirmation text to archive language or add a new archive confirmation method.

- Modify `Sources/CodexPlusApp/WindowCoordinator.swift`
  - Wire draft creation, workspace selection, default workspace directory creation, archive confirmation, multi-run start/stop, tab selection, and compact return animation.

- Modify `Sources/CodexPlusApp/Views/ConversationPanelHostView.swift`
  - Change the model to publish a coordinator snapshot instead of one `ConversationSession`.
  - Add closures for workspace selection, conversation selection, new draft, archive, reorder, and workspace picking.

- Modify `Sources/CodexPlusApp/Views/ConversationView.swift`
  - Split the old single header into a two-level tab header plus current conversation controls.
  - Render draft state when no active conversation is selected.

- Create `Sources/CodexPlusApp/Views/ConversationTabHeaderView.swift`
  - Own the workspace tab row and conversation tab row UI.

- Create `Sources/CodexPlusApp/Views/ConversationDraftView.swift`
  - Own the directory picker button and first-prompt composer.

- Modify `Tests/CodexPlusCoreTests/main.swift`
  - Add core tests for default workspace naming, workspace grouping, title generation, ordering, archive fallback, event isolation, and parallel run registry behavior.

---

### Task 1: Core Models And Naming Policy

**Files:**
- Modify: `Sources/CodexPlusCore/ConversationModels.swift`
- Test: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Produces:
  - `WorkspaceSessionGroup`
  - `ConversationDraft`
  - `ConversationCoordinatorSnapshot`
  - `ConversationArchiveResult`
  - `ConversationWorkspacePolicy`
  - `ConversationTitleGenerator`
  - Extended `ConversationSession`
- Consumes: existing `ConversationRunState`, `PermissionMode`, and `ConversationDisplayEvent`

- [ ] **Step 1: Write failing model and naming tests**

Add these tests after the existing conversation run state assertions in `Tests/CodexPlusCoreTests/main.swift`:

```swift
let fixedDateComponents = DateComponents(
    calendar: Calendar(identifier: .gregorian),
    timeZone: TimeZone(secondsFromGMT: 0),
    year: 2026,
    month: 7,
    day: 3
)
let fixedDate = fixedDateComponents.date!
expect(
    ConversationWorkspacePolicy.defaultParentPath(homeDirectoryPath: "/Users/oriki") ==
        "/Users/oriki/Documents/Codex Plus Workspace",
    "default workspace parent uses corrected Codex Plus Workspace path"
)
expect(
    ConversationWorkspacePolicy.defaultDirectoryName(
        date: fixedDate,
        randomSuffix: 4821,
        calendar: Calendar(identifier: .gregorian)
    ) == "2026-07-03-4821",
    "default workspace child uses date and random suffix"
)
expect(
    ConversationWorkspacePolicy.defaultWorkspacePath(
        homeDirectoryPath: "/Users/oriki",
        date: fixedDate,
        randomSuffix: 4821,
        calendar: Calendar(identifier: .gregorian)
    ) == "/Users/oriki/Documents/Codex Plus Workspace/2026-07-03-4821",
    "default workspace path joins parent and child"
)
expect(
    ConversationWorkspacePolicy.displayName(for: "/Users/oriki/Documents/codex-plus") == "codex-plus",
    "workspace display name uses last path component"
)
expect(
    ConversationWorkspacePolicy.normalizedPath("/Users/oriki/Documents/codex-plus/") ==
        "/Users/oriki/Documents/codex-plus",
    "workspace path normalization removes trailing slash"
)

var titleGenerator = ConversationTitleGenerator(randomSuffixes: [4821, 4821, 9130])
let firstTitle = titleGenerator.nextTitle(existingTitles: [])
let secondTitle = titleGenerator.nextTitle(existingTitles: [firstTitle])
expect(firstTitle == "对话_4821", "conversation title uses random suffix")
expect(secondTitle == "对话_9130", "conversation title retries on collision")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run CodexPlusCoreTests`

Expected: FAIL because `ConversationWorkspacePolicy` and `ConversationTitleGenerator` are not defined.

- [ ] **Step 3: Extend `ConversationModels.swift`**

Add these types below `ConversationSession` in `Sources/CodexPlusCore/ConversationModels.swift`, and extend `ConversationSession` with the listed fields:

```swift
public struct ConversationSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var prompt: String
    public var workspacePath: String
    public var state: ConversationRunState
    public var permissionMode: PermissionMode
    public var isPinned: Bool
    public var isExplicitlyKept: Bool
    public var isArchived: Bool
    public var createdAt: Date
    public var lastActivityAt: Date
    public var events: [ConversationDisplayEvent]

    public init(
        id: UUID = UUID(),
        title: String = "对话_0000",
        prompt: String,
        workspacePath: String = ".",
        state: ConversationRunState = .idle,
        permissionMode: PermissionMode = .semiAutomatic,
        isPinned: Bool = false,
        isExplicitlyKept: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        events: [ConversationDisplayEvent] = []
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.workspacePath = workspacePath
        self.state = state
        self.permissionMode = permissionMode
        self.isPinned = isPinned
        self.isExplicitlyKept = isExplicitlyKept
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.events = events
    }
}

public struct WorkspaceSessionGroup: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var path: String
    public var displayName: String
    public var conversationIDs: [UUID]
    public var lastActivityAt: Date

    public init(
        id: UUID = UUID(),
        path: String,
        displayName: String,
        conversationIDs: [UUID] = [],
        lastActivityAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.conversationIDs = conversationIDs
        self.lastActivityAt = lastActivityAt
    }
}

public struct ConversationDraft: Equatable, Sendable {
    public var selectedWorkspacePath: String?
    public var errorMessage: String?

    public init(selectedWorkspacePath: String? = nil, errorMessage: String? = nil) {
        self.selectedWorkspacePath = selectedWorkspacePath
        self.errorMessage = errorMessage
    }
}

public struct ConversationCoordinatorSnapshot: Equatable, Sendable {
    public var workspaces: [WorkspaceSessionGroup]
    public var conversations: [ConversationSession]
    public var activeWorkspaceID: UUID?
    public var activeConversationID: UUID?
    public var draft: ConversationDraft?

    public init(
        workspaces: [WorkspaceSessionGroup],
        conversations: [ConversationSession],
        activeWorkspaceID: UUID?,
        activeConversationID: UUID?,
        draft: ConversationDraft?
    ) {
        self.workspaces = workspaces
        self.conversations = conversations
        self.activeWorkspaceID = activeWorkspaceID
        self.activeConversationID = activeConversationID
        self.draft = draft
    }

    public var activeConversation: ConversationSession? {
        guard let activeConversationID else {
            return nil
        }

        return conversations.first { $0.id == activeConversationID && !$0.isArchived }
    }
}

public struct ConversationArchiveResult: Equatable, Sendable {
    public var archivedConversationID: UUID
    public var activeWorkspaceID: UUID?
    public var activeConversationID: UUID?

    public init(archivedConversationID: UUID, activeWorkspaceID: UUID?, activeConversationID: UUID?) {
        self.archivedConversationID = archivedConversationID
        self.activeWorkspaceID = activeWorkspaceID
        self.activeConversationID = activeConversationID
    }
}

public enum ConversationWorkspacePolicy {
    public static let defaultParentDirectoryName = "Codex Plus Workspace"

    public static func defaultParentPath(homeDirectoryPath: String) -> String {
        NSString(string: homeDirectoryPath)
            .appendingPathComponent("Documents")
            .appendingPathComponent(defaultParentDirectoryName)
    }

    public static func defaultDirectoryName(
        date: Date,
        randomSuffix: Int,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        var calendar = calendar
        calendar.timeZone = calendar.timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d-%04d", year, month, day, randomSuffix)
    }

    public static func defaultWorkspacePath(
        homeDirectoryPath: String,
        date: Date,
        randomSuffix: Int,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        NSString(string: defaultParentPath(homeDirectoryPath: homeDirectoryPath))
            .appendingPathComponent(defaultDirectoryName(date: date, randomSuffix: randomSuffix, calendar: calendar))
    }

    public static func normalizedPath(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        return NSString(string: expanded).standardizingPath
    }

    public static func displayName(for path: String) -> String {
        let name = URL(fileURLWithPath: normalizedPath(path)).lastPathComponent
        return name.isEmpty ? normalizedPath(path) : name
    }
}

public struct ConversationTitleGenerator: Sendable {
    private var randomSuffixes: [Int]

    public init(randomSuffixes: [Int] = []) {
        self.randomSuffixes = randomSuffixes
    }

    public mutating func nextTitle(existingTitles: [String]) -> String {
        let existing = Set(existingTitles)

        while true {
            let suffix = nextSuffix()
            let title = "对话_\(String(format: "%04d", suffix))"
            if !existing.contains(title) {
                return title
            }
        }
    }

    private mutating func nextSuffix() -> Int {
        if !randomSuffixes.isEmpty {
            return randomSuffixes.removeFirst()
        }

        return Int.random(in: 1000...9999)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run CodexPlusCoreTests`

Expected: PASS for the new model tests. Existing tests may fail where they assert exact `ConversationSession` equality only if initializer call sites need timestamp values; fix those call sites by passing fixed `createdAt` and `lastActivityAt`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexPlusCore/ConversationModels.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat(core): add conversation tab models"
```

---

### Task 2: Conversation Coordinator Workspace State

**Files:**
- Modify: `Sources/CodexPlusCore/ConversationCoordinator.swift`
- Test: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Consumes:
  - `WorkspaceSessionGroup`
  - `ConversationDraft`
  - `ConversationCoordinatorSnapshot`
  - `ConversationArchiveResult`
  - `ConversationWorkspacePolicy.normalizedPath(_:)`
  - `ConversationWorkspacePolicy.displayName(for:)`
  - `ConversationTitleGenerator.nextTitle(existingTitles:)`
- Produces:
  - `snapshot: ConversationCoordinatorSnapshot`
  - `activeConversation: ConversationSession?`
  - `visibleConversations(in:) -> [ConversationSession]`
  - `beginDraft(selectedWorkspacePath:)`
  - `setDraftWorkspacePath(_:)`
  - `startConversation(prompt:workspacePath:now:)`
  - `selectWorkspace(_:)`
  - `selectConversation(_:)`
  - `archiveConversation(_:now:) -> ConversationArchiveResult?`
  - `reorderWorkspace(_:to:)`
  - `reorderConversation(_:to:)`

- [ ] **Step 1: Write failing coordinator tests**

Replace the existing single-conversation coordinator tests from `let emptyConversationCoordinator = ConversationCoordinator()` through the command display event test with this block:

```swift
let emptyConversationCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [1111]))
expect(
    emptyConversationCoordinator.shortcutDecision() == .openFreshEntry,
    "shortcut opens fresh when no active conversation"
)
expect(emptyConversationCoordinator.snapshot.workspaces.isEmpty, "empty coordinator has no workspaces")

let workspaceMergeCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [1111, 2222]))
let mergeDate = Date(timeIntervalSince1970: 100)
let firstMergedConversation = workspaceMergeCoordinator.startConversation(
    prompt: "first",
    workspacePath: "/Users/oriki/project/",
    now: mergeDate
)
let secondMergedConversation = workspaceMergeCoordinator.startConversation(
    prompt: "second",
    workspacePath: "/Users/oriki/project",
    now: mergeDate.addingTimeInterval(10)
)
expect(workspaceMergeCoordinator.snapshot.workspaces.count == 1, "same normalized path merges into one workspace")
expect(
    workspaceMergeCoordinator.snapshot.workspaces.first?.conversationIDs ==
        [firstMergedConversation.id, secondMergedConversation.id],
    "merged workspace preserves conversation order"
)
expect(firstMergedConversation.title == "对话_1111", "first generated conversation title")
expect(secondMergedConversation.title == "对话_2222", "second generated conversation title")

let separateWorkspaceCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [3333, 4444]))
let leftWorkspaceConversation = separateWorkspaceCoordinator.startConversation(
    prompt: "left",
    workspacePath: "/tmp/left",
    now: Date(timeIntervalSince1970: 100)
)
let rightWorkspaceConversation = separateWorkspaceCoordinator.startConversation(
    prompt: "right",
    workspacePath: "/tmp/right",
    now: Date(timeIntervalSince1970: 200)
)
expect(separateWorkspaceCoordinator.snapshot.workspaces.count == 2, "different paths create different workspaces")
separateWorkspaceCoordinator.selectWorkspace(separateWorkspaceCoordinator.snapshot.workspaces.first!.id)
expect(
    separateWorkspaceCoordinator.activeConversation?.id == leftWorkspaceConversation.id,
    "selecting workspace selects its first visible conversation"
)
separateWorkspaceCoordinator.selectConversation(rightWorkspaceConversation.id)
expect(
    separateWorkspaceCoordinator.activeConversation?.id == rightWorkspaceConversation.id,
    "selecting conversation switches active conversation"
)

let reorderCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [1001, 1002, 1003]))
let reorderFirst = reorderCoordinator.startConversation(prompt: "one", workspacePath: "/tmp/reorder", now: Date(timeIntervalSince1970: 1))
let reorderSecond = reorderCoordinator.startConversation(prompt: "two", workspacePath: "/tmp/reorder", now: Date(timeIntervalSince1970: 2))
let reorderThird = reorderCoordinator.startConversation(prompt: "three", workspacePath: "/tmp/reorder", now: Date(timeIntervalSince1970: 3))
reorderCoordinator.reorderConversation(reorderThird.id, to: 0)
expect(
    reorderCoordinator.snapshot.workspaces.first?.conversationIDs ==
        [reorderThird.id, reorderFirst.id, reorderSecond.id],
    "conversation reorder moves within workspace"
)

let archiveCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [9001, 9002, 9003]))
let archiveLeft = archiveCoordinator.startConversation(prompt: "left", workspacePath: "/tmp/archive", now: Date(timeIntervalSince1970: 10))
let archiveMiddle = archiveCoordinator.startConversation(prompt: "middle", workspacePath: "/tmp/archive", now: Date(timeIntervalSince1970: 20))
let archiveRight = archiveCoordinator.startConversation(prompt: "right", workspacePath: "/tmp/archive", now: Date(timeIntervalSince1970: 30))
archiveCoordinator.appendCodexEvent(.agentMessage("new left activity"), to: archiveLeft.id, now: Date(timeIntervalSince1970: 40))
archiveCoordinator.selectConversation(archiveMiddle.id)
let archiveResult = archiveCoordinator.archiveConversation(archiveMiddle.id, now: Date(timeIntervalSince1970: 50))
expect(archiveResult?.activeConversationID == archiveLeft.id, "archive selects newest neighbor by activity")
expect(archiveCoordinator.activeConversation?.id == archiveLeft.id, "coordinator active conversation follows archive result")
expect(
    archiveCoordinator.visibleConversations(in: archiveCoordinator.snapshot.workspaces.first!.id).map(\.id) ==
        [archiveLeft.id, archiveRight.id],
    "archived conversation disappears from visible tabs"
)

let allArchivedCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [7001]))
let onlyConversation = allArchivedCoordinator.startConversation(prompt: "only", workspacePath: "/tmp/only")
let onlyArchiveResult = allArchivedCoordinator.archiveConversation(onlyConversation.id)
expect(onlyArchiveResult?.activeConversationID == nil, "archiving last conversation clears active conversation")
expect(allArchivedCoordinator.snapshot.workspaces.isEmpty, "archiving last conversation removes workspace tab")
expect(allArchivedCoordinator.activeConversation == nil, "no active conversation remains after last archive")

let isolatedEventsCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [8001, 8002]))
let isolatedFirst = isolatedEventsCoordinator.startConversation(prompt: "one", workspacePath: "/tmp/events")
let isolatedSecond = isolatedEventsCoordinator.startConversation(prompt: "two", workspacePath: "/tmp/events")
isolatedEventsCoordinator.appendCodexEvent(.agentMessage("first only"), to: isolatedFirst.id)
let firstEvents = isolatedEventsCoordinator.conversation(with: isolatedFirst.id)?.events ?? []
let secondEvents = isolatedEventsCoordinator.conversation(with: isolatedSecond.id)?.events ?? []
expect(firstEvents.count == 2, "first conversation receives appended event")
expect(secondEvents.count == 1, "second conversation does not receive first event")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run CodexPlusCoreTests`

Expected: FAIL because `ConversationCoordinator` does not accept a title generator and does not expose workspace/tab methods.

- [ ] **Step 3: Replace coordinator storage and initializer**

In `Sources/CodexPlusCore/ConversationCoordinator.swift`, replace the current stored properties and initializer with:

```swift
@Published public private(set) var workspaces: [WorkspaceSessionGroup] = []
@Published public private(set) var conversations: [ConversationSession] = []
@Published public private(set) var activeWorkspaceID: UUID?
@Published public private(set) var activeConversationID: UUID?
@Published public private(set) var draft: ConversationDraft?
@Published public private(set) var preferredSide: SideAttachment = .right

private var titleGenerator: ConversationTitleGenerator

public init(titleGenerator: ConversationTitleGenerator = ConversationTitleGenerator()) {
    self.titleGenerator = titleGenerator
}

public var snapshot: ConversationCoordinatorSnapshot {
    ConversationCoordinatorSnapshot(
        workspaces: workspaces,
        conversations: conversations,
        activeWorkspaceID: activeWorkspaceID,
        activeConversationID: activeConversationID,
        draft: draft
    )
}

public var activeConversation: ConversationSession? {
    guard let activeConversationID else {
        return nil
    }

    return conversations.first { $0.id == activeConversationID && !$0.isArchived }
}

public func conversation(with id: UUID) -> ConversationSession? {
    conversations.first { $0.id == id }
}
```

- [ ] **Step 4: Add draft and selection methods**

Add these methods near `shortcutDecision()`:

```swift
public func beginDraft(selectedWorkspacePath: String? = nil) {
    draft = ConversationDraft(
        selectedWorkspacePath: selectedWorkspacePath.map(ConversationWorkspacePolicy.normalizedPath)
    )
    activeConversationID = nil
}

public func setDraftWorkspacePath(_ path: String?) {
    draft = ConversationDraft(
        selectedWorkspacePath: path.map(ConversationWorkspacePolicy.normalizedPath),
        errorMessage: nil
    )
}

public func setDraftError(_ message: String) {
    var nextDraft = draft ?? ConversationDraft()
    nextDraft.errorMessage = message
    draft = nextDraft
}

public func selectWorkspace(_ id: UUID) {
    guard let workspace = workspaces.first(where: { $0.id == id }) else {
        return
    }

    activeWorkspaceID = workspace.id
    activeConversationID = visibleConversations(in: workspace.id).first?.id
    draft = nil
}

public func selectConversation(_ id: UUID) {
    guard let conversation = conversations.first(where: { $0.id == id && !$0.isArchived }),
          let workspace = workspaces.first(where: { $0.path == conversation.workspacePath })
    else {
        return
    }

    activeWorkspaceID = workspace.id
    activeConversationID = conversation.id
    draft = nil
}

public func visibleConversations(in workspaceID: UUID) -> [ConversationSession] {
    guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
        return []
    }

    return workspace.conversationIDs.compactMap { id in
        conversations.first { $0.id == id && !$0.isArchived }
    }
}
```

- [ ] **Step 5: Replace `startConversation`**

Replace the existing `startConversation(prompt:)` with:

```swift
@discardableResult
public func startConversation(
    prompt: String,
    workspacePath: String = ".",
    now: Date = Date()
) -> ConversationSession {
    let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedPath = ConversationWorkspacePolicy.normalizedPath(workspacePath)
    let title = titleGenerator.nextTitle(existingTitles: conversations.map(\.title))
    let session = ConversationSession(
        title: title,
        prompt: trimmedPrompt,
        workspacePath: normalizedPath,
        state: .idle,
        permissionMode: .semiAutomatic,
        createdAt: now,
        lastActivityAt: now,
        events: [
            .userPrompt(id: UUID(), text: trimmedPrompt)
        ]
    )

    conversations.append(session)
    attachConversation(session.id, toWorkspacePath: normalizedPath, now: now)
    activeConversationID = session.id
    draft = nil
    return session
}
```

Add this helper:

```swift
private func attachConversation(_ conversationID: UUID, toWorkspacePath path: String, now: Date) {
    if let workspaceIndex = workspaces.firstIndex(where: { $0.path == path }) {
        workspaces[workspaceIndex].conversationIDs.append(conversationID)
        workspaces[workspaceIndex].lastActivityAt = now
        activeWorkspaceID = workspaces[workspaceIndex].id
        return
    }

    let workspace = WorkspaceSessionGroup(
        path: path,
        displayName: ConversationWorkspacePolicy.displayName(for: path),
        conversationIDs: [conversationID],
        lastActivityAt: now
    )
    workspaces.append(workspace)
    activeWorkspaceID = workspace.id
}
```

- [ ] **Step 6: Update mutation methods for arrays**

Replace `updateActiveConversation` with:

```swift
private func updateConversation(
    _ id: UUID,
    now: Date = Date(),
    _ update: (inout ConversationSession) -> Void
) {
    guard let index = conversations.firstIndex(where: { $0.id == id }) else {
        return
    }

    update(&conversations[index])
    conversations[index].lastActivityAt = now
    touchWorkspace(for: conversations[index], now: now)
}

private func touchWorkspace(for conversation: ConversationSession, now: Date) {
    guard let workspaceIndex = workspaces.firstIndex(where: { $0.path == conversation.workspacePath }) else {
        return
    }

    workspaces[workspaceIndex].lastActivityAt = now
}
```

Change each existing mutation call from `updateActiveConversation(id)` to `updateConversation(id)`. Add `now: Date = Date()` parameters to `markRunning`, `markCompleted`, `markFailed`, `markStopped`, `appendUserPrompt`, and `appendCodexEvent`, and pass `now` into `updateConversation`.

- [ ] **Step 7: Add reorder and archive methods**

Add:

```swift
public func reorderWorkspace(_ id: UUID, to targetIndex: Int) {
    guard let sourceIndex = workspaces.firstIndex(where: { $0.id == id }),
          workspaces.indices.contains(targetIndex),
          sourceIndex != targetIndex
    else {
        return
    }

    let workspace = workspaces.remove(at: sourceIndex)
    workspaces.insert(workspace, at: targetIndex)
}

public func reorderConversation(_ id: UUID, to targetIndex: Int) {
    guard let workspaceIndex = workspaces.firstIndex(where: { $0.conversationIDs.contains(id) }) else {
        return
    }

    var ids = workspaces[workspaceIndex].conversationIDs
    guard let sourceIndex = ids.firstIndex(of: id),
          ids.indices.contains(targetIndex),
          sourceIndex != targetIndex
    else {
        return
    }

    let conversationID = ids.remove(at: sourceIndex)
    ids.insert(conversationID, at: targetIndex)
    workspaces[workspaceIndex].conversationIDs = ids
}

@discardableResult
public func archiveConversation(_ id: UUID, now: Date = Date()) -> ConversationArchiveResult? {
    guard let conversationIndex = conversations.firstIndex(where: { $0.id == id }),
          let workspaceIndex = workspaces.firstIndex(where: { $0.path == conversations[conversationIndex].workspacePath })
    else {
        return nil
    }

    let neighborID = archiveFallbackNeighbor(
        archivedID: id,
        conversationIDs: workspaces[workspaceIndex].conversationIDs
    )

    conversations[conversationIndex].isArchived = true
    conversations[conversationIndex].lastActivityAt = now
    workspaces[workspaceIndex].conversationIDs.removeAll { $0 == id }

    if workspaces[workspaceIndex].conversationIDs.isEmpty {
        workspaces.remove(at: workspaceIndex)
    }

    if activeConversationID == id {
        if let neighborID, conversations.contains(where: { $0.id == neighborID && !$0.isArchived }) {
            selectConversation(neighborID)
        } else if let nextWorkspace = workspaces.max(by: { $0.lastActivityAt < $1.lastActivityAt }) {
            selectWorkspace(nextWorkspace.id)
        } else {
            activeWorkspaceID = nil
            activeConversationID = nil
            draft = ConversationDraft()
        }
    }

    return ConversationArchiveResult(
        archivedConversationID: id,
        activeWorkspaceID: activeWorkspaceID,
        activeConversationID: activeConversationID
    )
}

private func archiveFallbackNeighbor(archivedID: UUID, conversationIDs: [UUID]) -> UUID? {
    guard let index = conversationIDs.firstIndex(of: archivedID) else {
        return nil
    }

    let leftID = index > 0 ? conversationIDs[index - 1] : nil
    let rightIndex = conversationIDs.index(after: index)
    let rightID = conversationIDs.indices.contains(rightIndex) ? conversationIDs[rightIndex] : nil

    switch (leftID.flatMap(conversation(with:)), rightID.flatMap(conversation(with:))) {
    case let (left?, right?):
        return left.lastActivityAt >= right.lastActivityAt ? left.id : right.id
    case let (left?, nil):
        return left.id
    case let (nil, right?):
        return right.id
    case (nil, nil):
        return nil
    }
}
```

- [ ] **Step 8: Run tests to verify pass**

Run: `swift run CodexPlusCoreTests`

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/CodexPlusCore/ConversationCoordinator.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat(core): manage workspace conversations"
```

---

### Task 3: Parallel Run Registry And Working Directory

**Files:**
- Modify: `Sources/CodexPlusCore/ProcessCodexRunner.swift`
- Modify: `Sources/CodexPlusCore/CodexRunController.swift`
- Test: `Tests/CodexPlusCoreTests/main.swift`

**Interfaces:**
- Consumes:
  - Existing `CodexRunHandle`
  - Existing `ProcessCodexRunner.run`
- Produces:
  - `ProcessCodexRunner.run(prompt:permissionMode:workingDirectoryURL:onEvent:onFinish:)`
  - `CodexRunController.isRunning(sessionID:) -> Bool`
  - Parallel-safe `CodexRunController.start`
  - Per-session `CodexRunController.stop(sessionID:)`

- [ ] **Step 1: Write failing runner tests**

Add after the existing `CodexRunController` success test:

```swift
let workingDirectory = makeTemporaryDirectory(named: "runner-working-directory")
defer {
    try? FileManager.default.removeItem(at: workingDirectory)
}
let workingDirectoryScriptPath = makeTemporaryScript(
    named: "working-directory",
    contents: """
    pwd
    """
)
defer {
    try? FileManager.default.removeItem(atPath: workingDirectoryScriptPath)
}
let workingDirectoryCapture = LockedRunCapture()
let workingDirectoryFinish = DispatchSemaphore(value: 0)
let workingDirectoryRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [workingDirectoryScriptPath],
    parser: { line in .agentMessage(line) }
)
_ = workingDirectoryRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    workingDirectoryURL: workingDirectory,
    onEvent: { event in
        workingDirectoryCapture.appendEvent(event)
    },
    onFinish: { result in
        workingDirectoryCapture.appendResult(result)
        workingDirectoryFinish.signal()
    }
)
expect(
    workingDirectoryFinish.wait(timeout: .now() + .seconds(5)) == .success,
    "working-directory process finishes"
)
expect(
    agentMessageTexts(from: workingDirectoryCapture.events()).first == workingDirectory.path,
    "process runner starts in supplied working directory"
)

let parallelScriptPath = makeTemporaryScript(
    named: "parallel-controller",
    contents: """
    printf 'started\\n'
    sleep 1
    printf 'done\\n'
    """
)
defer {
    try? FileManager.default.removeItem(atPath: parallelScriptPath)
}
let parallelRunner = ProcessCodexRunner(
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    executableArgumentsPrefix: [parallelScriptPath],
    parser: { line in .agentMessage(line) }
)
let parallelController = CodexRunController(runner: parallelRunner)
let parallelFirstSessionID = UUID()
let parallelSecondSessionID = UUID()
var parallelFinishedSessionIDs: [UUID] = []
let firstParallelStarted = parallelController.start(
    prompt: "first",
    permissionMode: .semiAutomatic,
    sessionID: parallelFirstSessionID,
    workingDirectoryURL: nil,
    onEvent: { _, _ in },
    onFinish: { _, sessionID in
        parallelFinishedSessionIDs.append(sessionID)
    }
)
let secondParallelStarted = parallelController.start(
    prompt: "second",
    permissionMode: .semiAutomatic,
    sessionID: parallelSecondSessionID,
    workingDirectoryURL: nil,
    onEvent: { _, _ in },
    onFinish: { _, sessionID in
        parallelFinishedSessionIDs.append(sessionID)
    }
)
let duplicateParallelStarted = parallelController.start(
    prompt: "duplicate",
    permissionMode: .semiAutomatic,
    sessionID: parallelFirstSessionID,
    workingDirectoryURL: nil,
    onEvent: { _, _ in },
    onFinish: { _, _ in }
)
expect(firstParallelStarted, "parallel controller starts first session")
expect(secondParallelStarted, "parallel controller starts second session")
expect(!duplicateParallelStarted, "parallel controller rejects duplicate session run")
expect(parallelController.isRunning(sessionID: parallelFirstSessionID), "first session is running")
expect(parallelController.isRunning(sessionID: parallelSecondSessionID), "second session is running")
expect(
    waitUntil(timeout: 5) { parallelFinishedSessionIDs.count == 2 },
    "parallel controller forwards both finishes"
)
expect(!parallelController.isRunning, "parallel controller clears aggregate running state")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run CodexPlusCoreTests`

Expected: FAIL because `workingDirectoryURL` and `isRunning(sessionID:)` are missing, and duplicate-session behavior is not implemented.

- [ ] **Step 3: Add working directory to `ProcessCodexRunner.run`**

In `Sources/CodexPlusCore/ProcessCodexRunner.swift`, change the public `run` signature to:

```swift
public func run(
    prompt: String,
    permissionMode: PermissionMode,
    workingDirectoryURL: URL? = nil,
    onEvent: @escaping @Sendable (CodexEvent) -> Void,
    onFinish: @escaping @Sendable (CodexRunResult) -> Void
) -> CodexRunHandle
```

After `let process = Process()`, add:

```swift
process.currentDirectoryURL = workingDirectoryURL
```

Existing call sites continue to compile because the new parameter has a default value.

- [ ] **Step 4: Replace single active run storage**

In `Sources/CodexPlusCore/CodexRunController.swift`, replace the single active fields with:

```swift
private struct ActiveRun {
    var handle: CodexRunHandle
    var runID: UUID
    var sessionID: UUID
    var eventHandler: (CodexEvent, UUID) -> Void
    var finishHandler: (CodexRunResult, UUID) -> Void
}

private var activeRuns: [UUID: ActiveRun] = [:]
private var stoppedRunIDs = Set<UUID>()

public var isRunning: Bool {
    !activeRuns.isEmpty
}

public func isRunning(sessionID: UUID) -> Bool {
    activeRuns[sessionID] != nil
}
```

- [ ] **Step 5: Update `start` to allow parallel sessions**

Change the `start` signature to:

```swift
@discardableResult
public func start(
    prompt: String,
    permissionMode: PermissionMode,
    sessionID: UUID,
    workingDirectoryURL: URL? = nil,
    onEvent: @escaping (CodexEvent, UUID) -> Void,
    onFinish: @escaping (CodexRunResult, UUID) -> Void
) -> Bool
```

Replace the guard and handle assignment with:

```swift
guard activeRuns[sessionID] == nil else {
    return false
}

let runID = UUID()
let callbackQueue = callbackQueue
let callbackTarget = WeakCodexRunControllerBox(self)
let handle = runner.run(
    prompt: prompt,
    permissionMode: permissionMode,
    workingDirectoryURL: workingDirectoryURL,
    onEvent: { event in
        callbackQueue.async {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    callbackTarget.value?.handleEvent(event, sessionID: sessionID, runID: runID)
                }
            }
        }
    },
    onFinish: { result in
        callbackQueue.async {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    callbackTarget.value?.handleFinish(result, sessionID: sessionID, runID: runID)
                }
            }
        }
    }
)

activeRuns[sessionID] = ActiveRun(
    handle: handle,
    runID: runID,
    sessionID: sessionID,
    eventHandler: onEvent,
    finishHandler: onFinish
)

return true
```

- [ ] **Step 6: Update stop and callbacks**

Replace `stop`, `handleEvent`, `handleFinish`, and `clearRunIfCurrent` with:

```swift
@discardableResult
public func stop(sessionID: UUID) -> Bool {
    guard let activeRun = activeRuns[sessionID] else {
        return false
    }

    stoppedRunIDs.insert(activeRun.runID)
    activeRun.handle.stop()
    return true
}

private func handleEvent(_ event: CodexEvent, sessionID: UUID, runID: UUID) {
    guard let activeRun = activeRuns[sessionID], activeRun.runID == runID else {
        return
    }

    activeRun.eventHandler(event, sessionID)
}

private func handleFinish(_ result: CodexRunResult, sessionID: UUID, runID: UUID) {
    if stoppedRunIDs.remove(runID) != nil {
        clearRunIfCurrent(sessionID: sessionID, runID: runID)
        return
    }

    guard let activeRun = activeRuns[sessionID], activeRun.runID == runID else {
        return
    }

    let finishHandler = activeRun.finishHandler
    clearRunIfCurrent(sessionID: sessionID, runID: runID)
    finishHandler(result, sessionID)
}

private func clearRunIfCurrent(sessionID: UUID, runID: UUID) {
    guard activeRuns[sessionID]?.runID == runID else {
        return
    }

    activeRuns[sessionID] = nil
}
```

- [ ] **Step 7: Update old controller tests**

In existing tests that call `codexRunController.start`, add `workingDirectoryURL: nil` after `sessionID:` so the intended API is explicit:

```swift
workingDirectoryURL: nil,
```

- [ ] **Step 8: Run tests to verify pass**

Run: `swift run CodexPlusCoreTests`

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/CodexPlusCore/ProcessCodexRunner.swift Sources/CodexPlusCore/CodexRunController.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat(core): run conversations in parallel"
```

---

### Task 4: App Integration And Tab UI

**Files:**
- Modify: `Sources/CodexPlusApp/PermissionPrompter.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`
- Modify: `Sources/CodexPlusApp/Views/ConversationPanelHostView.swift`
- Modify: `Sources/CodexPlusApp/Views/ConversationView.swift`
- Create: `Sources/CodexPlusApp/Views/ConversationTabHeaderView.swift`
- Create: `Sources/CodexPlusApp/Views/ConversationDraftView.swift`

**Interfaces:**
- Consumes:
  - `ConversationCoordinator.snapshot`
  - `ConversationCoordinator.beginDraft`
  - `ConversationCoordinator.setDraftWorkspacePath`
  - `ConversationCoordinator.startConversation(prompt:workspacePath:now:)`
  - `ConversationCoordinator.archiveConversation`
  - `CodexRunController.start(... workingDirectoryURL:)`
  - `CodexRunController.isRunning(sessionID:)`
  - `WorkspaceSessionGroup`
  - `ConversationSession`
  - `ConversationDraft`
- Produces:
  - `ConversationPanelModel.snapshot`
  - App closures for tab selection, new draft, archive, reorder, and workspace selection
  - Default workspace directory creation
  - Two-level draggable tab header
  - Draft view with optional workspace selection
  - Conversation view that renders either draft or active conversation

- [ ] **Step 1: Add archive confirmation copy**

Modify `Sources/CodexPlusApp/PermissionPrompter.swift` by adding:

```swift
func confirmStopRunningTaskOnArchive() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Archive running conversation?"
    alert.informativeText = "Archiving this conversation will stop its running Codex task."
    alert.addButton(withTitle: "Stop and Archive")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
}
```

- [ ] **Step 2: Change the panel model to a snapshot**

Replace `ConversationPanelModel` in `Sources/CodexPlusApp/Views/ConversationPanelHostView.swift` with:

```swift
@MainActor
final class ConversationPanelModel: ObservableObject {
    @Published var snapshot: ConversationCoordinatorSnapshot

    init(snapshot: ConversationCoordinatorSnapshot) {
        self.snapshot = snapshot
    }
}
```

Change `ConversationPanelHostView` properties to include:

```swift
let onSubmitDraft: (String) -> Void
let onSelectWorkspace: (UUID) -> Void
let onSelectConversation: (UUID) -> Void
let onNewDraft: () -> Void
let onArchiveConversation: (UUID) -> Void
let onPickWorkspace: () -> Void
let onReorderWorkspace: (UUID, Int) -> Void
let onReorderConversation: (UUID, Int) -> Void
```

Keep existing follow-up, stop, pin, side, and full-access closures.

- [ ] **Step 3: Add default workspace helpers to `WindowCoordinator`**

In `Sources/CodexPlusApp/WindowCoordinator.swift`, add:

```swift
private func createDefaultWorkspaceDirectory() throws -> String {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.path

    for _ in 0..<20 {
        let suffix = Int.random(in: 1000...9999)
        let path = ConversationWorkspacePolicy.defaultWorkspacePath(
            homeDirectoryPath: homePath,
            date: Date(),
            randomSuffix: suffix
        )
        let url = URL(fileURLWithPath: path, isDirectory: true)

        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.path
        }
    }

    throw CocoaError(.fileWriteFileExists)
}

private func resolveDraftWorkspacePath() throws -> String {
    if let selectedPath = conversationCoordinator.snapshot.draft?.selectedWorkspacePath {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: selectedPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        return selectedPath
    }

    return try createDefaultWorkspaceDirectory()
}
```

- [ ] **Step 4: Add directory picker**

Add:

```swift
private func pickDraftWorkspace() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else {
        return
    }

    conversationCoordinator.setDraftWorkspacePath(url.path)
    refreshSidePanelContent()
}
```

- [ ] **Step 5: Replace `startConversation(prompt:)` with draft-aware start**

Replace the current `startConversation(prompt:)` body with:

```swift
private func startConversation(prompt: String) {
    let workspacePath: String

    do {
        workspacePath = try resolveDraftWorkspacePath()
    } catch {
        conversationCoordinator.setDraftError("Unable to prepare workspace: \(error.localizedDescription)")
        refreshSidePanelContent()
        return
    }

    let session = conversationCoordinator.startConversation(
        prompt: prompt,
        workspacePath: workspacePath
    )
    prepareCenteredSidePanelFrame()
    showSidePanel()
    startCodexRun(prompt: prompt, sessionID: session.id, workspacePath: session.workspacePath)
}
```

- [ ] **Step 6: Update follow-up and run start**

Change `handleFollowUp` to check only the active conversation:

```swift
guard !runController.isRunning(sessionID: session.id) else {
    conversationCoordinator.appendCodexEvent(
        .error("Codex is already running in this conversation. Stop the current task before sending a follow-up."),
        to: session.id
    )
    refreshSidePanelContent()
    return
}
```

Change `startCodexRun` signature to:

```swift
private func startCodexRun(prompt: String, sessionID: UUID, workspacePath: String)
```

Inside `runController.start`, pass:

```swift
workingDirectoryURL: URL(fileURLWithPath: workspacePath, isDirectory: true),
```

- [ ] **Step 7: Add archive action**

Add:

```swift
private func archiveConversation(_ id: UUID) {
    guard let session = conversationCoordinator.conversation(with: id) else {
        return
    }

    if runController.isRunning(sessionID: id) {
        guard permissionPrompter.confirmStopRunningTaskOnArchive() else {
            return
        }

        _ = runController.stop(sessionID: id)
        if session.state == .running {
            conversationCoordinator.markStopped(id)
        }
    }

    _ = conversationCoordinator.archiveConversation(id)

    if conversationCoordinator.activeConversation == nil {
        returnToCompactEntry()
    } else {
        refreshSidePanelContent()
    }
}
```

Add the compact transition:

```swift
private func returnToCompactEntry() {
    guard let screen = activeScreen() else {
        showCompactPanel()
        return
    }

    let targetFrame = defaultCompactPanelFrame(on: screen)

    if let sidePanel, sidePanel.isVisible {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sidePanel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.sidePanel?.orderOut(nil)
                self?.sidePanelModel = nil
                self?.isSidePanelContentInstalled = false
                self?.showCompactPanel()
            }
        }
        return
    }

    showCompactPanel()
}
```

Add `import QuartzCore` to `WindowCoordinator.swift` for `CAMediaTimingFunction`.

- [ ] **Step 8: Update refresh and host installation**

In `refreshSidePanelContent`, use `snapshot`:

```swift
let snapshot = conversationCoordinator.snapshot
let targetPanel = panel ?? sidePanel
let model: ConversationPanelModel

if let sidePanelModel {
    sidePanelModel.snapshot = snapshot
    model = sidePanelModel
} else {
    model = ConversationPanelModel(snapshot: snapshot)
    sidePanelModel = model
}
```

Remove the early guard that returns when `activeConversation` is nil, because draft state must render.

In `installSidePanelContent`, pass all new closures:

```swift
onSubmitDraft: { [weak self] prompt in
    Task { @MainActor in self?.startConversation(prompt: prompt) }
},
onSelectWorkspace: { [weak self] id in
    Task { @MainActor in self?.conversationCoordinator.selectWorkspace(id); self?.refreshSidePanelContent() }
},
onSelectConversation: { [weak self] id in
    Task { @MainActor in self?.conversationCoordinator.selectConversation(id); self?.refreshSidePanelContent() }
},
onNewDraft: { [weak self] in
    Task { @MainActor in self?.conversationCoordinator.beginDraft(); self?.refreshSidePanelContent() }
},
onArchiveConversation: { [weak self] id in
    Task { @MainActor in self?.archiveConversation(id) }
},
onPickWorkspace: { [weak self] in
    Task { @MainActor in self?.pickDraftWorkspace() }
},
onReorderWorkspace: { [weak self] id, index in
    Task { @MainActor in self?.conversationCoordinator.reorderWorkspace(id, to: index); self?.refreshSidePanelContent() }
},
onReorderConversation: { [weak self] id, index in
    Task { @MainActor in self?.conversationCoordinator.reorderConversation(id, to: index); self?.refreshSidePanelContent() }
},
```

- [ ] **Step 9: Create `ConversationTabHeaderView.swift`**

Add this file:

```swift
import CodexPlusCore
import SwiftUI

struct ConversationTabHeaderView: View {
    let snapshot: ConversationCoordinatorSnapshot
    let onSelectWorkspace: (UUID) -> Void
    let onSelectConversation: (UUID) -> Void
    let onNewDraft: () -> Void
    let onArchiveConversation: (UUID) -> Void
    let onReorderWorkspace: (UUID, Int) -> Void
    let onReorderConversation: (UUID, Int) -> Void

    @State private var draggedWorkspaceID: UUID?
    @State private var draggedConversationID: UUID?

    private var activeWorkspace: WorkspaceSessionGroup? {
        guard let activeWorkspaceID = snapshot.activeWorkspaceID else {
            return nil
        }

        return snapshot.workspaces.first { $0.id == activeWorkspaceID }
    }

    private var activeWorkspaceConversations: [ConversationSession] {
        guard let activeWorkspace else {
            return []
        }

        return activeWorkspace.conversationIDs.compactMap { id in
            snapshot.conversations.first { $0.id == id && !$0.isArchived }
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            tabScrollRow {
                ForEach(Array(snapshot.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    workspaceTab(workspace, index: index)
                }
            }

            tabScrollRow {
                ForEach(Array(activeWorkspaceConversations.enumerated()), id: \.element.id) { index, conversation in
                    conversationTab(conversation, index: index)
                }

                Button(action: onNewDraft) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .help("New Conversation")
                .accessibilityLabel("New Conversation")
            }
        }
    }

    private func tabScrollRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                content()
            }
            .padding(.horizontal, 2)
        }
    }

    private func workspaceTab(_ workspace: WorkspaceSessionGroup, index: Int) -> some View {
        Button {
            onSelectWorkspace(workspace.id)
        } label: {
            HStack(spacing: 6) {
                statusDot(
                    isRunning: workspace.conversationIDs.contains { id in
                        snapshot.conversations.first { $0.id == id }?.state == .running
                    }
                )

                Text(workspace.displayName)
                    .font(.caption.weight(snapshot.activeWorkspaceID == workspace.id ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(tabBackground(isActive: snapshot.activeWorkspaceID == workspace.id))
        }
        .buttonStyle(.plain)
        .help(workspace.path)
        .onDrag {
            draggedWorkspaceID = workspace.id
            return NSItemProvider(object: workspace.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            guard let draggedWorkspaceID else {
                return false
            }

            onReorderWorkspace(draggedWorkspaceID, index)
            self.draggedWorkspaceID = nil
            return true
        }
    }

    private func conversationTab(_ conversation: ConversationSession, index: Int) -> some View {
        Button {
            onSelectConversation(conversation.id)
        } label: {
            HStack(spacing: 6) {
                Button {
                    onArchiveConversation(conversation.id)
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 18, height: 20)
                }
                .buttonStyle(.plain)
                .help("Archive")
                .accessibilityLabel("Archive Conversation")

                Text(conversation.title)
                    .font(.caption2.weight(snapshot.activeConversationID == conversation.id ? .semibold : .regular))
                    .lineLimit(1)

                statusDot(isRunning: conversation.state == .running)
            }
            .padding(.leading, 4)
            .padding(.trailing, 9)
            .frame(height: 26)
            .background(tabBackground(isActive: snapshot.activeConversationID == conversation.id))
        }
        .buttonStyle(.plain)
        .onDrag {
            draggedConversationID = conversation.id
            return NSItemProvider(object: conversation.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            guard let draggedConversationID else {
                return false
            }

            onReorderConversation(draggedConversationID, index)
            self.draggedConversationID = nil
            return true
        }
    }

    private func tabBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
    }

    private func statusDot(isRunning: Bool) -> some View {
        Circle()
            .fill(isRunning ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 6, height: 6)
    }
}
```

- [ ] **Step 10: Create `ConversationDraftView.swift`**

Add:

```swift
import CodexPlusCore
import SwiftUI

struct ConversationDraftView: View {
    let draft: ConversationDraft?
    let onPickWorkspace: () -> Void
    let onSubmit: (String) -> Void

    @FocusState private var isPromptFocused: Bool
    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onPickWorkspace) {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .semibold))

                    Text(workspaceText)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .help("Choose Workspace")
            .accessibilityLabel("Choose Workspace")

            if let errorMessage = draft?.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            LiquidGlassContainer(cornerRadius: 22) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Ask Codex...", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .lineLimit(1...4)
                        .focused($isPromptFocused)
                        .onSubmit(submitPrompt)

                    Button(action: submitPrompt) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Send")
                    .accessibilityLabel("Send")
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .onAppear {
            isPromptFocused = true
        }
    }

    private var workspaceText: String {
        guard let path = draft?.selectedWorkspacePath else {
            return "Choose workspace or send to create a default workspace"
        }

        return path
    }

    private func submitPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        onSubmit(trimmedPrompt)
        prompt = ""
    }
}
```

- [ ] **Step 11: Update `ConversationPanelHostView` body**

Change the `ConversationView` call to pass snapshot and new closures:

```swift
ConversationView(
    snapshot: model.snapshot,
    onSubmitDraft: onSubmitDraft,
    onFollowUp: onFollowUp,
    onStop: onStop,
    onTogglePin: onTogglePin,
    onToggleSide: onToggleSide,
    onToggleFullAccess: onToggleFullAccess,
    onSelectWorkspace: onSelectWorkspace,
    onSelectConversation: onSelectConversation,
    onNewDraft: onNewDraft,
    onArchiveConversation: onArchiveConversation,
    onPickWorkspace: onPickWorkspace,
    onReorderWorkspace: onReorderWorkspace,
    onReorderConversation: onReorderConversation
)
.id(model.snapshot.activeConversationID ?? UUID())
```

- [ ] **Step 12: Update `ConversationView` inputs**

Replace the old `session` property with:

```swift
let snapshot: ConversationCoordinatorSnapshot
let onSubmitDraft: (String) -> Void
let onFollowUp: (String) -> Void
let onStop: () -> Void
let onTogglePin: () -> Void
let onToggleSide: () -> Void
let onToggleFullAccess: () -> Void
let onSelectWorkspace: (UUID) -> Void
let onSelectConversation: (UUID) -> Void
let onNewDraft: () -> Void
let onArchiveConversation: (UUID) -> Void
let onPickWorkspace: () -> Void
let onReorderWorkspace: (UUID, Int) -> Void
let onReorderConversation: (UUID, Int) -> Void

private var session: ConversationSession? {
    snapshot.activeConversation
}
```

- [ ] **Step 13: Replace `body` state switching**

Use:

```swift
var body: some View {
    VStack(spacing: 12) {
        header

        if let session {
            conversationBody(for: session)
            footer(for: session)
        } else {
            Spacer(minLength: 0)
            ConversationDraftView(
                draft: snapshot.draft,
                onPickWorkspace: onPickWorkspace,
                onSubmit: onSubmitDraft
            )
        }
    }
    .padding(14)
    .frame(minWidth: 360, minHeight: 420)
    .onAppear {
        isFollowUpFocused = true
    }
}
```

Extract the existing scroll container into:

```swift
private func conversationBody(for session: ConversationSession) -> some View {
    LiquidGlassContainer(cornerRadius: 24) {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(timelineItems(for: session)) { item in
                        timelineRow(for: item)
                            .id(item.id)
                    }
                }
                .padding(14)
            }
            .onChange(of: session.events.count) {
                scrollToLatest(session: session, using: proxy)
            }
            .onAppear {
                scrollToLatest(session: session, using: proxy)
            }
        }
    }
}
```

- [ ] **Step 14: Replace header**

Use:

```swift
private var header: some View {
    LiquidGlassContainer(cornerRadius: 20) {
        VStack(spacing: 8) {
            ConversationTabHeaderView(
                snapshot: snapshot,
                onSelectWorkspace: onSelectWorkspace,
                onSelectConversation: onSelectConversation,
                onNewDraft: onNewDraft,
                onArchiveConversation: onArchiveConversation,
                onReorderWorkspace: onReorderWorkspace,
                onReorderConversation: onReorderConversation
            )

            if let session {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.state.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(session.state.tint)
                            .lineLimit(1)

                        Text(session.permissionMode.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    iconButton(
                        systemName: session.permissionMode == .fullAccess ? "lock.open.fill" : "lock.fill",
                        help: fullAccessWarningText,
                        accessibilityLabel: session.permissionMode == .fullAccess ? "Disable Full Access" : "Enable Full Access",
                        action: onToggleFullAccess
                    )

                    iconButton(
                        systemName: "sidebar.trailing",
                        help: "Switch Side",
                        accessibilityLabel: "Switch Side",
                        action: onToggleSide
                    )

                    iconButton(
                        systemName: session.isPinned ? "pin.fill" : "pin",
                        help: "Pin",
                        accessibilityLabel: session.isPinned ? "Unpin Window" : "Pin Window",
                        action: onTogglePin
                    )

                    iconButton(
                        systemName: "stop.fill",
                        help: "Stop",
                        accessibilityLabel: "Stop Codex Task",
                        isDisabled: session.state != .running,
                        action: onStop
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
```

Remove the old `xmark` close button.

- [ ] **Step 15: Update footer and timeline helpers**

Change footer signature:

```swift
private func footer(for session: ConversationSession) -> some View
```

Change timeline helpers:

```swift
private func timelineItems(for session: ConversationSession) -> [ConversationTimelineItem] {
    ConversationTimelineBuilder.items(from: session.events)
}

private func scrollToLatest(session: ConversationSession, using proxy: ScrollViewProxy) {
    guard let latestID = timelineItems(for: session).last?.id else {
        return
    }

    proxy.scrollTo(latestID, anchor: .bottom)
}
```

- [ ] **Step 16: Build and run core tests**

Run:

```bash
swift build
swift run CodexPlusCoreTests
```

Expected: both PASS.

- [ ] **Step 17: Commit**

```bash
git add Sources/CodexPlusApp/PermissionPrompter.swift Sources/CodexPlusApp/WindowCoordinator.swift Sources/CodexPlusApp/Views/ConversationPanelHostView.swift Sources/CodexPlusApp/Views/ConversationView.swift Sources/CodexPlusApp/Views/ConversationTabHeaderView.swift Sources/CodexPlusApp/Views/ConversationDraftView.swift
git commit -m "feat(app): add conversation tab UI"
```

---

### Task 5: Shortcut, Edge Cases, And Verification

**Files:**
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`
- Modify: `Sources/CodexPlusCore/ConversationCoordinator.swift`
- Test: `Tests/CodexPlusCoreTests/main.swift`
- Create: `docs/superpowers/manual-tests/2026-07-03-conversation-management.md`

**Interfaces:**
- Consumes:
  - Previous task UI and coordinator APIs
- Produces:
  - Shortcut behavior that shows existing workbench or draft
  - Manual verification checklist

- [ ] **Step 1: Write final shortcut behavior test**

Add near other shortcut tests:

```swift
let archivedShortcutCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [6101]))
let archivedShortcutConversation = archivedShortcutCoordinator.startConversation(prompt: "archive", workspacePath: "/tmp/archive-shortcut")
archivedShortcutCoordinator.archiveConversation(archivedShortcutConversation.id)
expect(
    archivedShortcutCoordinator.shortcutDecision() == .openFreshEntry,
    "shortcut opens fresh entry when every conversation is archived"
)

let visibleCompletedShortcutCoordinator = ConversationCoordinator(titleGenerator: ConversationTitleGenerator(randomSuffixes: [6201]))
let visibleCompletedConversation = visibleCompletedShortcutCoordinator.startConversation(prompt: "done", workspacePath: "/tmp/done")
visibleCompletedShortcutCoordinator.markCompleted(visibleCompletedConversation.id)
expect(
    visibleCompletedShortcutCoordinator.shortcutDecision() == .recallExisting(visibleCompletedConversation.id),
    "completed visible conversation recalls workbench while it remains unarchived"
)
```

- [ ] **Step 2: Run test to verify it fails if shortcut still uses terminal state**

Run: `swift run CodexPlusCoreTests`

Expected: FAIL if `shortcutDecision()` still opens fresh for completed unarchived conversations.

- [ ] **Step 3: Update shortcut decision**

Change `shortcutDecision()` in `ConversationCoordinator` to:

```swift
public func shortcutDecision() -> ShortcutDecision {
    guard let activeConversation else {
        return .openFreshEntry
    }

    return .recallExisting(activeConversation.id)
}
```

This keeps the workbench visible while there are unarchived conversations, even if the active one is terminal.

- [ ] **Step 4: Update `showSidePanel` draft behavior**

In `WindowCoordinator.showSidePanel()`, replace the guard that falls back to compact when no active conversation exists with:

```swift
if conversationCoordinator.activeConversation == nil,
   conversationCoordinator.snapshot.draft == nil {
    conversationCoordinator.beginDraft()
}
```

Then continue to install side panel content so draft state renders.

- [ ] **Step 5: Add manual verification doc**

Create `docs/superpowers/manual-tests/2026-07-03-conversation-management.md`:

```markdown
# Conversation Management Manual Test

Date: 2026-07-03

## Checks

- Open the compact entry with the global shortcut.
- Submit a prompt without choosing a workspace.
- Confirm a directory is created under `~/Documents/Codex Plus Workspace`.
- Confirm a workspace tab and a `对话_####` conversation tab appear.
- Click `+`, choose a different folder, submit another prompt, and confirm a second workspace tab appears.
- Start two long-running prompts and switch tabs while both continue updating.
- Try a follow-up in a running conversation and confirm only that conversation blocks the follow-up.
- Archive a running conversation and cancel the confirmation; confirm it continues running.
- Archive a running conversation and confirm; confirm only that conversation stops and disappears from active tabs.
- Archive a completed conversation and confirm it disappears without a confirmation prompt.
- Archive the selected middle conversation in a three-tab workspace; confirm the neighbor with newest activity is selected.
- Drag workspace tabs and confirm their order changes.
- Drag conversation tabs inside one workspace and confirm their order changes.
- Archive all conversations and confirm the panel animates back to compact entry.
```

- [ ] **Step 6: Run full verification**

Run:

```bash
swift run CodexPlusCoreTests
swift build
```

Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusApp/WindowCoordinator.swift Sources/CodexPlusCore/ConversationCoordinator.swift Tests/CodexPlusCoreTests/main.swift docs/superpowers/manual-tests/2026-07-03-conversation-management.md
git commit -m "test: cover conversation management flows"
```

---

## Self-Review Notes

Spec coverage:

- Two-level workspace/conversation tabs are covered by Tasks 2 and 4.
- Optional directory selection and default workspace creation are covered by Tasks 1 and 4.
- Parallel run support is covered by Task 3.
- Archive behavior and fallback selection are covered by Tasks 2, 4, and 5.
- Drag ordering is covered by Tasks 2 and 4.
- Compact return animation is covered by Task 4.
- Archive manager, persistence, worktree modes, smart titles, cross-workspace drag, and search are excluded in Global Constraints and not implemented by any task.

Verification:

- Each core behavior has a failing-test-first step.
- AppKit and SwiftUI wiring is checked with `swift build`.
- Manual checks cover the user-visible flows that executable core tests cannot inspect.
