# Prompt Template Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an independent Settings prompt template manager with built-in read-only templates, editable user templates, persistence, and a visible workbench Settings entry.

**Architecture:** Add prompt template models, validation, filtering, built-ins, and persistence contracts to `CodexPlusCore`. Add Settings presentation and dirty draft state in `CodexPlusApp`, opened from a gear button in the workbench top strip. Keep the manager completely independent from composer, archive generation, prompt optimization, and Codex execution.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSPanel`, SQLite via existing `SQLiteDatabase`, XCTest, existing `LiquidGlassScene` / `LiquidGlassContainer`.

## Global Constraints

- Preserve existing uncommitted user changes; do not revert or overwrite unrelated worktree modifications.
- The first version only manages templates and does not integrate with composer, archive flow, prompt optimization, Codex command construction, or execution.
- Supported prompt template types are exactly `对归档对话进行总结` and `优化用户对话输入框提示词`.
- System built-in templates are visible, read-only, non-deletable, and copyable to user custom templates.
- User custom templates can be created, edited, copied, deleted, searched, filtered, and persisted.
- `systemPrompt` is required; `userPrompt` is optional.
- Left pane type filter is multi-select; right pane type field is a required dropdown single-select.
- The right detail pane does not show source.
- Add a visible gear-shaped Settings entry in the main workbench top strip near the pin control.
- The manager must remain independent from all runtime Codex flows.

---

## File Structure

- Create `Sources/CodexPlusCore/PromptTemplates/PromptTemplateModels.swift`
  - Owns `PromptTemplate`, `PromptTemplateSource`, `PromptTemplateType`, `PromptTemplateDraft`, and validation errors.
- Create `Sources/CodexPlusCore/PromptTemplates/PromptTemplateLibrary.swift`
  - Owns built-in templates, validation, copying, filtering, and sorting.
- Create `Sources/CodexPlusCore/Persistence/PromptTemplateRepository.swift`
  - Owns the repository protocol for user custom prompt templates.
- Modify `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift`
  - Adds `prompt_templates` table and bumps schema version.
- Modify `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
  - Adds SQLite repository methods for user custom prompt templates.
- Modify `Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift`
  - Forwards prompt template repository calls.
- Create `Tests/CodexPlusCoreXCTests/PromptTemplateLibraryTests.swift`
  - Covers built-ins, validation, copy, filtering, and sorting.
- Create `Tests/CodexPlusCoreXCTests/PromptTemplatePersistenceTests.swift`
  - Covers schema migration and SQLite round trips.
- Create `Sources/CodexPlusApp/Settings/PromptTemplateSettingsStore.swift`
  - Owns Settings-local load/save/delete/copy/selection/dirty state.
- Create `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`
  - Owns the two-pane Settings UI.
- Create `Sources/CodexPlusApp/Settings/SettingsPanelController.swift`
  - Owns the Settings panel lifecycle.
- Modify `Sources/CodexPlusApp/AppDelegate.swift`
  - Passes the repository into `WindowCoordinator`.
- Modify `Sources/CodexPlusApp/WindowCoordinator.swift`
  - Creates and shows the Settings panel.
- Modify `Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift`
  - Passes the Settings action into `WorkbenchView`.
- Modify `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`
  - Adds `openSettings`.
- Modify `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
  - Wires Settings action to the top strip.
- Modify `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift`
  - Adds gear button near the pin control.
- Modify `Sources/CodexPlusApp/Workbench/WorkbenchStrings.swift`
  - Adds Settings labels.

---

### Task 1: Core Prompt Template Models And Library

**Files:**
- Create: `Sources/CodexPlusCore/PromptTemplates/PromptTemplateModels.swift`
- Create: `Sources/CodexPlusCore/PromptTemplates/PromptTemplateLibrary.swift`
- Test: `Tests/CodexPlusCoreXCTests/PromptTemplateLibraryTests.swift`

**Interfaces:**
- Produces:
  - `public enum PromptTemplateSource: String, CaseIterable, Sendable`
  - `public enum PromptTemplateType: String, CaseIterable, Sendable`
  - `public struct PromptTemplate: Equatable, Identifiable, Sendable`
  - `public struct PromptTemplateDraft: Equatable, Sendable`
  - `public enum PromptTemplateValidationError: Error, Equatable, Sendable`
  - `public enum PromptTemplateLibrary`
  - `PromptTemplateLibrary.builtInTemplates(now:) -> [PromptTemplate]`
  - `PromptTemplateLibrary.validate(_:) -> PromptTemplateValidationError?`
  - `PromptTemplateLibrary.filteredTemplates(_:sourceFilter:selectedTypes:searchQuery:) -> [PromptTemplate]`
  - `PromptTemplateLibrary.copyDraft(from:now:) -> PromptTemplateDraft`
- Consumes: no new project interfaces.

- [ ] **Step 1: Write failing library tests**

Create `Tests/CodexPlusCoreXCTests/PromptTemplateLibraryTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class PromptTemplateLibraryTests: XCTestCase {
    func testBuiltInTemplatesAreReadOnlyAndCoverBothTypes() {
        let templates = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(templates.map(\.source), [.systemBuiltIn, .systemBuiltIn])
        XCTAssertEqual(Set(templates.map(\.type)), Set(PromptTemplateType.allCases))
        XCTAssertTrue(templates.allSatisfy { !$0.name.isEmpty })
        XCTAssertTrue(templates.allSatisfy { !$0.systemPrompt.isEmpty })
    }

    func testValidationRequiresNameTypeAndSystemPromptOnly() {
        let now = Date(timeIntervalSince1970: 100)
        var draft = PromptTemplateDraft(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            type: .archiveConversationSummary,
            name: "摘要",
            systemPrompt: "整理归档对话",
            userPrompt: "",
            note: "",
            createdAt: now,
            updatedAt: now
        )

        XCTAssertNil(PromptTemplateLibrary.validate(draft))

        draft.name = "   "
        XCTAssertEqual(PromptTemplateLibrary.validate(draft), .emptyName)

        draft.name = "摘要"
        draft.type = nil
        XCTAssertEqual(PromptTemplateLibrary.validate(draft), .missingType)

        draft.type = .archiveConversationSummary
        draft.systemPrompt = "\n "
        XCTAssertEqual(PromptTemplateLibrary.validate(draft), .emptySystemPrompt)
    }

    func testTypeFilteringSupportsNoneOneAndBothSelectedTypes() {
        let now = Date(timeIntervalSince1970: 100)
        let archive = PromptTemplate(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            source: .userCustom,
            type: .archiveConversationSummary,
            name: "归档",
            systemPrompt: "归档",
            userPrompt: "",
            note: "",
            createdAt: now,
            updatedAt: now
        )
        let optimize = PromptTemplate(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            source: .userCustom,
            type: .optimizeUserInputPrompt,
            name: "优化",
            systemPrompt: "优化",
            userPrompt: "",
            note: "",
            createdAt: now,
            updatedAt: now
        )
        let templates = [archive, optimize]

        XCTAssertEqual(
            PromptTemplateLibrary.filteredTemplates(
                templates,
                sourceFilter: .all,
                selectedTypes: [],
                searchQuery: ""
            ).map(\.id),
            [archive.id, optimize.id]
        )
        XCTAssertEqual(
            PromptTemplateLibrary.filteredTemplates(
                templates,
                sourceFilter: .all,
                selectedTypes: [.archiveConversationSummary],
                searchQuery: ""
            ).map(\.id),
            [archive.id]
        )
        XCTAssertEqual(
            PromptTemplateLibrary.filteredTemplates(
                templates,
                sourceFilter: .all,
                selectedTypes: Set(PromptTemplateType.allCases),
                searchQuery: ""
            ).map(\.id),
            [archive.id, optimize.id]
        )
    }

    func testSearchMatchesNameNoteSystemPromptAndUserPrompt() {
        let now = Date(timeIntervalSince1970: 100)
        let template = PromptTemplate(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            source: .userCustom,
            type: .archiveConversationSummary,
            name: "项目复盘摘要",
            systemPrompt: "保留验证结果",
            userPrompt: "输出中文摘要",
            note: "归档后检索",
            createdAt: now,
            updatedAt: now
        )

        for query in ["复盘", "验证", "中文", "检索"] {
            XCTAssertEqual(
                PromptTemplateLibrary.filteredTemplates(
                    [template],
                    sourceFilter: .all,
                    selectedTypes: [],
                    searchQuery: query
                ),
                [template]
            )
        }
    }

    func testSortingPlacesBuiltInsBeforeCustomTemplates() {
        let older = Date(timeIntervalSince1970: 10)
        let newer = Date(timeIntervalSince1970: 20)
        let customOld = PromptTemplate(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            source: .userCustom,
            type: .archiveConversationSummary,
            name: "旧",
            systemPrompt: "旧",
            userPrompt: "",
            note: "",
            createdAt: older,
            updatedAt: older
        )
        let customNew = PromptTemplate(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            source: .userCustom,
            type: .archiveConversationSummary,
            name: "新",
            systemPrompt: "新",
            userPrompt: "",
            note: "",
            createdAt: newer,
            updatedAt: newer
        )
        let builtIn = PromptTemplateLibrary.builtInTemplates(now: older)[0]

        XCTAssertEqual(
            PromptTemplateLibrary.sortedTemplates([customOld, builtIn, customNew]).map(\.id),
            [builtIn.id, customNew.id, customOld.id]
        )
    }

    func testCopyingTemplateCreatesUserCustomDraft() {
        let source = PromptTemplateLibrary.builtInTemplates(now: Date(timeIntervalSince1970: 100))[0]
        let draft = PromptTemplateLibrary.copyDraft(from: source, now: Date(timeIntervalSince1970: 200))

        XCTAssertNotEqual(draft.id, source.id)
        XCTAssertEqual(draft.type, source.type)
        XCTAssertEqual(draft.systemPrompt, source.systemPrompt)
        XCTAssertEqual(draft.userPrompt, source.userPrompt)
        XCTAssertEqual(draft.note, source.note)
        XCTAssertTrue(draft.name.contains("副本"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PromptTemplateLibraryTests`

Expected: FAIL because `PromptTemplateLibrary` and related types do not exist.

- [ ] **Step 3: Implement prompt template models**

Create `Sources/CodexPlusCore/PromptTemplates/PromptTemplateModels.swift`:

```swift
import Foundation

public enum PromptTemplateSource: String, CaseIterable, Sendable {
    case systemBuiltIn
    case userCustom

    public var displayName: String {
        switch self {
        case .systemBuiltIn:
            return "系统内置提示词"
        case .userCustom:
            return "用户自定义提示词"
        }
    }
}

public enum PromptTemplateType: String, CaseIterable, Sendable {
    case archiveConversationSummary
    case optimizeUserInputPrompt

    public var displayName: String {
        switch self {
        case .archiveConversationSummary:
            return "对归档对话进行总结"
        case .optimizeUserInputPrompt:
            return "优化用户对话输入框提示词"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .archiveConversationSummary:
            return "归档总结"
        case .optimizeUserInputPrompt:
            return "优化输入"
        }
    }
}

public enum PromptTemplateSourceFilter: Equatable, Hashable, Sendable {
    case all
    case source(PromptTemplateSource)
}

public struct PromptTemplate: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var source: PromptTemplateSource
    public var type: PromptTemplateType
    public var name: String
    public var systemPrompt: String
    public var userPrompt: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        source: PromptTemplateSource,
        type: PromptTemplateType,
        name: String,
        systemPrompt: String,
        userPrompt: String,
        note: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.type = type
        self.name = name
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PromptTemplateDraft: Equatable, Sendable {
    public var id: UUID
    public var type: PromptTemplateType?
    public var name: String
    public var systemPrompt: String
    public var userPrompt: String
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        type: PromptTemplateType?,
        name: String,
        systemPrompt: String,
        userPrompt: String,
        note: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(template: PromptTemplate) {
        self.init(
            id: template.id,
            type: template.type,
            name: template.name,
            systemPrompt: template.systemPrompt,
            userPrompt: template.userPrompt,
            note: template.note,
            createdAt: template.createdAt,
            updatedAt: template.updatedAt
        )
    }
}

public enum PromptTemplateValidationError: Error, Equatable, Sendable {
    case emptyName
    case missingType
    case emptySystemPrompt
}
```

- [ ] **Step 4: Implement prompt template library**

Create `Sources/CodexPlusCore/PromptTemplates/PromptTemplateLibrary.swift`:

```swift
import Foundation

public enum PromptTemplateLibrary {
    private static let archiveBuiltInID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let optimizeBuiltInID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    public static func builtInTemplates(now: Date = Date()) -> [PromptTemplate] {
        [
            PromptTemplate(
                id: archiveBuiltInID,
                source: .systemBuiltIn,
                type: .archiveConversationSummary,
                name: "归档对话总结",
                systemPrompt: "你是 Codex 对话归档助手。请把对话整理成可复用的归档摘要，保留目标、关键决策、完成内容、验证结果、遗留风险和后续动作。输出应简洁、结构清晰，并避免加入对话中没有出现的信息。",
                userPrompt: "请总结当前归档对话，输出适合保存和检索的摘要。",
                note: "用于将已归档 Codex 对话整理成摘要。",
                createdAt: now,
                updatedAt: now
            ),
            PromptTemplate(
                id: optimizeBuiltInID,
                source: .systemBuiltIn,
                type: .optimizeUserInputPrompt,
                name: "优化输入框提示词",
                systemPrompt: "你是 Codex 提示词优化助手。请把用户输入改写成更清晰、可执行、边界明确的 Codex 请求，保留用户原意，不添加用户没有要求的范围。",
                userPrompt: "请优化这段用户输入，使它更适合发送给 Codex。",
                note: "用于优化用户对话输入框中的提示词。",
                createdAt: now,
                updatedAt: now
            )
        ]
    }

    public static func validate(_ draft: PromptTemplateDraft) -> PromptTemplateValidationError? {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptyName
        }
        guard draft.type != nil else {
            return .missingType
        }
        if draft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .emptySystemPrompt
        }
        return nil
    }

    public static func userTemplate(from draft: PromptTemplateDraft, now: Date = Date()) throws -> PromptTemplate {
        if let validationError = validate(draft) {
            throw validationError
        }

        return PromptTemplate(
            id: draft.id,
            source: .userCustom,
            type: draft.type!,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: draft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            userPrompt: draft.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: draft.createdAt,
            updatedAt: now
        )
    }

    public static func copyDraft(from template: PromptTemplate, now: Date = Date()) -> PromptTemplateDraft {
        PromptTemplateDraft(
            id: UUID(),
            type: template.type,
            name: "\(template.name) 副本",
            systemPrompt: template.systemPrompt,
            userPrompt: template.userPrompt,
            note: template.note,
            createdAt: now,
            updatedAt: now
        )
    }

    public static func sortedTemplates(_ templates: [PromptTemplate]) -> [PromptTemplate] {
        templates.sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source == .systemBuiltIn
            }
            if lhs.source == .userCustom, lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func filteredTemplates(
        _ templates: [PromptTemplate],
        sourceFilter: PromptTemplateSourceFilter,
        selectedTypes: Set<PromptTemplateType>,
        searchQuery: String
    ) -> [PromptTemplate] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return sortedTemplates(templates).filter { template in
            switch sourceFilter {
            case .all:
                break
            case let .source(source):
                guard template.source == source else {
                    return false
                }
            }

            if !selectedTypes.isEmpty, !selectedTypes.contains(template.type) {
                return false
            }

            guard !trimmedQuery.isEmpty else {
                return true
            }

            return [
                template.name,
                template.note,
                template.systemPrompt,
                template.userPrompt
            ].contains { text in
                text.lowercased().contains(trimmedQuery)
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify the task passes**

Run: `swift test --filter PromptTemplateLibraryTests`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexPlusCore/PromptTemplates/PromptTemplateModels.swift Sources/CodexPlusCore/PromptTemplates/PromptTemplateLibrary.swift Tests/CodexPlusCoreXCTests/PromptTemplateLibraryTests.swift
git commit -m "feat: add prompt template core models"
```

---

### Task 2: Prompt Template SQLite Persistence

**Files:**
- Create: `Sources/CodexPlusCore/Persistence/PromptTemplateRepository.swift`
- Modify: `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift`
- Modify: `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
- Modify: `Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift`
- Test: `Tests/CodexPlusCoreXCTests/PromptTemplatePersistenceTests.swift`

**Interfaces:**
- Consumes:
  - `PromptTemplate`
  - `PromptTemplateSource`
  - `PromptTemplateType`
- Produces:
  - `public protocol PromptTemplateRepository`
  - `savePromptTemplate(_:) throws`
  - `loadPromptTemplates() throws -> [PromptTemplate]`
  - `deletePromptTemplate(_:) throws`

- [ ] **Step 1: Write failing persistence tests**

Create `Tests/CodexPlusCoreXCTests/PromptTemplatePersistenceTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class PromptTemplatePersistenceTests: XCTestCase {
    func testSchemaCreatesPromptTemplateTableAndBumpsVersion() throws {
        let database = try temporaryDatabase()

        try CodexPlusSchema.migrate(database)

        let versionRows = try database.query("PRAGMA user_version;")
        XCTAssertEqual(versionRows.first?["user_version"], .integer(Int64(CodexPlusSchema.version)))

        let tableRows = try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'prompt_templates';"
        )
        XCTAssertEqual(tableRows.count, 1)
    }

    func testRepositoryRoundTripsUserCustomPromptTemplates() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let template = PromptTemplate(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            source: .userCustom,
            type: .archiveConversationSummary,
            name: "项目复盘摘要",
            systemPrompt: "整理归档对话",
            userPrompt: "",
            note: "用于项目复盘",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try repository.savePromptTemplate(template)

        XCTAssertEqual(try repository.loadPromptTemplates(), [template])

        var renamed = template
        renamed.name = "项目复盘摘要 v2"
        renamed.updatedAt = Date(timeIntervalSince1970: 30)
        try repository.savePromptTemplate(renamed)

        XCTAssertEqual(try repository.loadPromptTemplates(), [renamed])

        try repository.deletePromptTemplate(template.id)
        XCTAssertTrue(try repository.loadPromptTemplates().isEmpty)
    }

    func testRepositoryRejectsSavingBuiltInPromptTemplates() throws {
        let database = try temporaryDatabase()
        try CodexPlusSchema.migrate(database)
        let repository = SQLiteCodexPlusRepository(database: database)
        let builtIn = PromptTemplateLibrary.builtInTemplates()[0]

        XCTAssertThrowsError(try repository.savePromptTemplate(builtIn))
    }

    private func temporaryDatabase() throws -> SQLiteDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-plus-\(UUID().uuidString).sqlite")
        return try SQLiteDatabase(path: url.path)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PromptTemplatePersistenceTests`

Expected: FAIL because repository methods and schema table do not exist.

- [ ] **Step 3: Add repository protocol**

Create `Sources/CodexPlusCore/Persistence/PromptTemplateRepository.swift`:

```swift
import Foundation

public protocol PromptTemplateRepository: Sendable {
    func savePromptTemplate(_ template: PromptTemplate) throws
    func loadPromptTemplates() throws -> [PromptTemplate]
    func deletePromptTemplate(_ id: UUID) throws
}
```

Modify `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift` so the aggregate protocol includes prompt templates:

```swift
public protocol CodexPlusRepository: ProjectRepository, ConversationRepository, ArchiveRepository, MemoryRepository, AttachmentRepository, PromptTemplateRepository, Sendable {}
```

In the same extension, add default unsupported methods:

```swift
func savePromptTemplate(_ template: PromptTemplate) throws {
    throw UnsupportedRepositoryOperation()
}

func loadPromptTemplates() throws -> [PromptTemplate] {
    throw UnsupportedRepositoryOperation()
}

func deletePromptTemplate(_ id: UUID) throws {
    throw UnsupportedRepositoryOperation()
}
```

- [ ] **Step 4: Add schema table**

Modify `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift`:

```swift
public enum CodexPlusSchema {
    public static let version = 2
```

Add this table before `PRAGMA user_version`:

```swift
try database.execute("""
CREATE TABLE IF NOT EXISTS prompt_templates (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    name TEXT NOT NULL,
    system_prompt TEXT NOT NULL,
    user_prompt TEXT NOT NULL,
    note TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
""")
```

Keep all existing table creation statements intact. Leave the final user version assignment as:

```swift
try database.execute("PRAGMA user_version = \(version);")
```

- [ ] **Step 5: Implement SQLite repository methods**

In `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`, add:

```swift
private enum PromptTemplatePersistenceError: Error {
    case builtInTemplatesAreReadOnly
    case invalidPromptTemplateType(String)
}
```

Inside `SQLiteCodexPlusRepository`, add:

```swift
public func savePromptTemplate(_ template: PromptTemplate) throws {
    guard template.source == .userCustom else {
        throw PromptTemplatePersistenceError.builtInTemplatesAreReadOnly
    }

    try database.execute(
        """
        INSERT INTO prompt_templates (
            id,
            type,
            name,
            system_prompt,
            user_prompt,
            note,
            created_at,
            updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            type = excluded.type,
            name = excluded.name,
            system_prompt = excluded.system_prompt,
            user_prompt = excluded.user_prompt,
            note = excluded.note,
            created_at = excluded.created_at,
            updated_at = excluded.updated_at;
        """,
        [
            .text(template.id.uuidString.lowercased()),
            .text(template.type.rawValue),
            .text(template.name),
            .text(template.systemPrompt),
            .text(template.userPrompt),
            .text(template.note),
            .real(template.createdAt.timeIntervalSince1970),
            .real(template.updatedAt.timeIntervalSince1970)
        ]
    )
}

public func loadPromptTemplates() throws -> [PromptTemplate] {
    let rows = try database.query(
        """
        SELECT id, type, name, system_prompt, user_prompt, note, created_at, updated_at
        FROM prompt_templates
        ORDER BY updated_at DESC, id ASC;
        """
    )

    return try rows.map(decodePromptTemplate)
}

public func deletePromptTemplate(_ id: UUID) throws {
    try database.execute(
        "DELETE FROM prompt_templates WHERE id = ?;",
        [.text(id.uuidString.lowercased())]
    )
}

private func decodePromptTemplate(_ row: [String: SQLiteValue]) throws -> PromptTemplate {
    let rawType = try text(for: "type", in: row)
    guard let type = PromptTemplateType(rawValue: rawType) else {
        throw PromptTemplatePersistenceError.invalidPromptTemplateType(rawType)
    }

    return PromptTemplate(
        id: try uuid(for: "id", in: row),
        source: .userCustom,
        type: type,
        name: try text(for: "name", in: row),
        systemPrompt: try text(for: "system_prompt", in: row),
        userPrompt: try text(for: "user_prompt", in: row),
        note: try text(for: "note", in: row),
        createdAt: Date(timeIntervalSince1970: try double(for: "created_at", in: row)),
        updatedAt: Date(timeIntervalSince1970: try double(for: "updated_at", in: row))
    )
}
```

- [ ] **Step 6: Forward through SQLite store**

Modify `Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift`:

```swift
public func savePromptTemplate(_ template: PromptTemplate) throws {
    try repository.savePromptTemplate(template)
}

public func loadPromptTemplates() throws -> [PromptTemplate] {
    try repository.loadPromptTemplates()
}

public func deletePromptTemplate(_ id: UUID) throws {
    try repository.deletePromptTemplate(id)
}
```

- [ ] **Step 7: Run tests to verify the task passes**

Run: `swift test --filter PromptTemplatePersistenceTests`

Expected: PASS.

Run: `swift test --filter CodexPlusCoreTestSuite`

Expected: PASS; legacy persistence tests still pass with schema version 2.

- [ ] **Step 8: Commit**

```bash
git add Sources/CodexPlusCore/Persistence/PromptTemplateRepository.swift Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift Tests/CodexPlusCoreXCTests/PromptTemplatePersistenceTests.swift
git commit -m "feat: persist prompt templates"
```

---

### Task 3: Settings Store State

**Files:**
- Create: `Sources/CodexPlusApp/Settings/PromptTemplateSettingsStore.swift`

**Interfaces:**
- Consumes:
  - `PromptTemplateRepository`
  - `PromptTemplateLibrary`
  - `PromptTemplate`
  - `PromptTemplateDraft`
- Produces:
  - `@MainActor final class PromptTemplateSettingsStore: ObservableObject`
  - Published state for templates, filters, selection, draft, dirty flag, validation error, and local error message.

- [ ] **Step 1: Create Settings store**

Create `Sources/CodexPlusApp/Settings/PromptTemplateSettingsStore.swift`:

```swift
import CodexPlusCore
import Foundation

@MainActor
final class PromptTemplateSettingsStore: ObservableObject {
    @Published private(set) var templates: [PromptTemplate] = []
    @Published var searchQuery = ""
    @Published var sourceFilter: PromptTemplateSourceFilter = .all
    @Published var selectedTypes = Set(PromptTemplateType.allCases)
    @Published private(set) var selectedTemplateID: UUID?
    @Published private(set) var draft: PromptTemplateDraft?
    @Published private(set) var isEditable = false
    @Published private(set) var isDirty = false
    @Published private(set) var validationError: PromptTemplateValidationError?
    @Published private(set) var errorMessage: String?

    private let repository: any PromptTemplateRepository
    private var savedDraft: PromptTemplateDraft?

    init(repository: any PromptTemplateRepository) {
        self.repository = repository
        reload()
    }

    var visibleTemplates: [PromptTemplate] {
        PromptTemplateLibrary.filteredTemplates(
            templates,
            sourceFilter: sourceFilter,
            selectedTypes: selectedTypes,
            searchQuery: searchQuery
        )
    }

    var selectedTemplate: PromptTemplate? {
        guard let selectedTemplateID else {
            return nil
        }
        return templates.first { $0.id == selectedTemplateID }
    }

    func reload() {
        do {
            templates = PromptTemplateLibrary.builtInTemplates() + (try repository.loadPromptTemplates())
            errorMessage = nil
            if selectedTemplateID == nil {
                select(visibleTemplates.first?.id)
            }
        } catch {
            errorMessage = "无法加载提示词模板：\(error)"
            templates = PromptTemplateLibrary.builtInTemplates()
            select(templates.first?.id)
        }
    }

    func select(_ id: UUID?) {
        guard let id, let template = templates.first(where: { $0.id == id }) else {
            selectedTemplateID = nil
            draft = nil
            savedDraft = nil
            isEditable = false
            isDirty = false
            validationError = nil
            return
        }

        selectedTemplateID = id
        let nextDraft = PromptTemplateDraft(template: template)
        draft = nextDraft
        savedDraft = nextDraft
        isEditable = template.source == .userCustom
        isDirty = false
        validationError = nil
    }

    func createTemplate() {
        let now = Date()
        let defaultType = selectedTypes.count == 1 ? selectedTypes.first : .archiveConversationSummary
        let nextDraft = PromptTemplateDraft(
            type: defaultType,
            name: "",
            systemPrompt: "",
            userPrompt: "",
            note: "",
            createdAt: now,
            updatedAt: now
        )
        selectedTemplateID = nextDraft.id
        draft = nextDraft
        savedDraft = nil
        isEditable = true
        isDirty = true
        validationError = nil
    }

    func copySelectedTemplate() {
        guard let selectedTemplate else {
            return
        }
        let nextDraft = PromptTemplateLibrary.copyDraft(from: selectedTemplate)
        selectedTemplateID = nextDraft.id
        draft = nextDraft
        savedDraft = nil
        isEditable = true
        isDirty = true
        validationError = nil
    }

    func updateDraft(_ mutation: (inout PromptTemplateDraft) -> Void) {
        guard isEditable, var nextDraft = draft else {
            return
        }
        mutation(&nextDraft)
        draft = nextDraft
        isDirty = nextDraft != savedDraft
        validationError = nil
    }

    func discardChanges() {
        guard let savedDraft else {
            select(visibleTemplates.first?.id)
            return
        }
        draft = savedDraft
        isDirty = false
        validationError = nil
    }

    func save() {
        guard let draft else {
            return
        }
        do {
            let template = try PromptTemplateLibrary.userTemplate(from: draft)
            try repository.savePromptTemplate(template)
            reload()
            select(template.id)
        } catch let validation as PromptTemplateValidationError {
            validationError = validation
        } catch {
            errorMessage = "无法保存提示词模板：\(error)"
        }
    }

    func deleteSelectedTemplate() {
        guard let template = selectedTemplate, template.source == .userCustom else {
            return
        }
        do {
            try repository.deletePromptTemplate(template.id)
            reload()
            select(visibleTemplates.first?.id)
        } catch {
            errorMessage = "无法删除提示词模板：\(error)"
        }
    }

    func toggleTypeFilter(_ type: PromptTemplateType) {
        if selectedTypes.contains(type) {
            selectedTypes.remove(type)
        } else {
            selectedTypes.insert(type)
        }
    }
}
```

- [ ] **Step 2: Build to verify store compiles**

Run: `swift build`

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/CodexPlusApp/Settings/PromptTemplateSettingsStore.swift
git commit -m "feat: add prompt template settings state"
```

---

### Task 4: Prompt Template Manager SwiftUI

**Files:**
- Create: `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchMetrics.swift`

**Interfaces:**
- Consumes:
  - `PromptTemplateSettingsStore`
  - `PromptTemplateType`
  - `PromptTemplateSourceFilter`
- Produces:
  - `struct PromptTemplateManagerView: View`

- [ ] **Step 1: Add Settings metrics**

Modify `Sources/CodexPlusApp/Workbench/WorkbenchMetrics.swift`:

```swift
static let settingsCornerRadius = CGFloat(18)
static let settingsSidebarWidth = CGFloat(300)
```

- [ ] **Step 2: Create manager view**

Create `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`:

```swift
import CodexPlusCore
import SwiftUI

struct PromptTemplateManagerView: View {
    @StateObject private var store: PromptTemplateSettingsStore
    @State private var isShowingDeleteConfirmation = false

    init(repository: any PromptTemplateRepository) {
        _store = StateObject(wrappedValue: PromptTemplateSettingsStore(repository: repository))
    }

    var body: some View {
        LiquidGlassScene(padding: 18, minWidth: 980, minHeight: 620) {
            HStack(spacing: 16) {
                sidebar
                    .frame(width: WorkbenchMetrics.settingsSidebarWidth)

                detailPane
            }
        }
        .alert("删除提示词模板？", isPresented: $isShowingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteSelectedTemplate()
            }
        } message: {
            Text("这个操作只会删除用户自定义提示词模板，系统内置提示词不会被删除。")
        }
    }

    private var sidebar: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.settingsCornerRadius) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("提示词模板")
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

                    Button(action: store.createTemplate) {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("新增用户自定义提示词")
                }

                TextField("搜索名称、说明、系统提示词、用户提示词", text: $store.searchQuery)
                    .textFieldStyle(.roundedBorder)

                sourceFilter
                typeFilter

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.visibleTemplates) { template in
                            templateRow(template)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private var sourceFilter: some View {
        Picker("来源", selection: sourceFilterBinding) {
            Text("全部").tag(PromptTemplateSourceFilter.all)
            Text("系统内置").tag(PromptTemplateSourceFilter.source(.systemBuiltIn))
            Text("用户自定义").tag(PromptTemplateSourceFilter.source(.userCustom))
        }
        .pickerStyle(.segmented)
    }

    private var typeFilter: some View {
        HStack(spacing: 8) {
            ForEach(PromptTemplateType.allCases, id: \.self) { type in
                Toggle(isOn: typeFilterBinding(type)) {
                    Text(type.shortDisplayName)
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
            }
        }
    }

    private func templateRow(_ template: PromptTemplate) -> some View {
        Button(action: { store.select(template.id) }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(template.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text("类型  \(template.type.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("来源  \(template.source.displayName)")
                    .font(.caption2)
                    .foregroundStyle(template.source == .systemBuiltIn ? .green : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(rowBackground(isSelected: store.selectedTemplateID == template.id))
        }
        .buttonStyle(.plain)
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.05))
    }

    private var detailPane: some View {
        LiquidGlassContainer(cornerRadius: WorkbenchMetrics.settingsCornerRadius) {
            VStack(spacing: 0) {
                detailHeader
                Divider().opacity(0.4)
                detailForm
                Spacer(minLength: 0)
                Divider().opacity(0.4)
                detailFooter
            }
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.draft?.name.isEmpty == false ? store.draft?.name ?? "未命名提示词" : "未命名提示词")
                    .font(.system(size: 20, weight: .semibold))
                Text(store.isEditable ? "用户自定义提示词，可以编辑保存。" : "系统内置提示词不可直接编辑，可以复制为用户模板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(store.isEditable ? "复制" : "复制为用户模板", action: store.copySelectedTemplate)
                .buttonStyle(.borderless)

            if store.isEditable {
                Button("删除", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(18)
    }

    private var detailForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            labeledField("名称 *") {
                TextField("模板名称", text: draftTextBinding(\.name))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!store.isEditable)
            }

            labeledField("类型 *") {
                Picker("类型", selection: draftTypeBinding) {
                    ForEach(PromptTemplateType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(Optional(type))
                    }
                }
                .pickerStyle(.menu)
                .disabled(!store.isEditable)
            }

            labeledField("系统提示词 *") {
                TextEditor(text: draftTextBinding(\.systemPrompt))
                    .frame(minHeight: 130)
                    .disabled(!store.isEditable)
                    .scrollContentBackground(.hidden)
            }

            labeledField("用户提示词") {
                TextEditor(text: draftTextBinding(\.userPrompt))
                    .frame(minHeight: 90)
                    .disabled(!store.isEditable)
                    .scrollContentBackground(.hidden)
            }

            labeledField("说明") {
                TextField("说明", text: draftTextBinding(\.note))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!store.isEditable)
            }

            if let validationError = store.validationError {
                Text(validationMessage(for: validationError))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(18)
        .opacity(store.isEditable ? 1 : 0.55)
    }

    private var detailFooter: some View {
        HStack {
            Circle()
                .fill(store.isEditable ? Color.blue : Color.green)
                .frame(width: 6, height: 6)
            Text(store.isEditable ? (store.isDirty ? "有未保存修改" : "可编辑状态") : "不可编辑状态")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("放弃修改", action: store.discardChanges)
                .disabled(!store.isEditable || !store.isDirty)
            Button("保存", action: store.save)
                .disabled(!store.isEditable || !store.isDirty)
        }
        .padding(18)
    }

    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
                .padding(.top, 7)
            content()
        }
    }

    private var sourceFilterBinding: Binding<PromptTemplateSourceFilter> {
        Binding(
            get: { store.sourceFilter },
            set: { store.sourceFilter = $0 }
        )
    }

    private func typeFilterBinding(_ type: PromptTemplateType) -> Binding<Bool> {
        Binding(
            get: { store.selectedTypes.contains(type) },
            set: { _ in store.toggleTypeFilter(type) }
        )
    }

    private func draftTextBinding(_ keyPath: WritableKeyPath<PromptTemplateDraft, String>) -> Binding<String> {
        Binding(
            get: { store.draft?[keyPath: keyPath] ?? "" },
            set: { value in store.updateDraft { $0[keyPath: keyPath] = value } }
        )
    }

    private var draftTypeBinding: Binding<PromptTemplateType?> {
        Binding(
            get: { store.draft?.type },
            set: { value in store.updateDraft { $0.type = value } }
        )
    }

    private func validationMessage(for error: PromptTemplateValidationError) -> String {
        switch error {
        case .emptyName:
            return "名称不能为空。"
        case .missingType:
            return "类型必须选择一项。"
        case .emptySystemPrompt:
            return "系统提示词不能为空。"
        }
    }
}
```

- [ ] **Step 3: Build to verify UI compiles**

Run: `swift build`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift Sources/CodexPlusApp/Workbench/WorkbenchMetrics.swift
git commit -m "feat: add prompt template manager view"
```

---

### Task 5: Settings Entry And Panel Integration

**Files:**
- Create: `Sources/CodexPlusApp/Settings/SettingsPanelController.swift`
- Modify: `Sources/CodexPlusApp/AppDelegate.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift`
- Modify: `Sources/CodexPlusApp/Workbench/WorkbenchStrings.swift`

**Interfaces:**
- Consumes:
  - `PromptTemplateRepository`
  - `PromptTemplateManagerView`
- Produces:
  - `SettingsPanelController.show()`
  - `ProjectStripActions.openSettings`
  - Workbench gear button opening Settings.

- [ ] **Step 1: Add Settings panel controller**

Create `Sources/CodexPlusApp/Settings/SettingsPanelController.swift`:

```swift
import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class SettingsPanelController {
    private let panelFactory: PanelFactory
    private weak var panelDelegate: NSWindowDelegate?
    private let repository: any PromptTemplateRepository

    private var panel: GlassPanel?

    init(
        panelFactory: PanelFactory,
        panelDelegate: NSWindowDelegate?,
        repository: any PromptTemplateRepository
    ) {
        self.panelFactory = panelFactory
        self.panelDelegate = panelDelegate
        self.repository = repository
    }

    func show() {
        let frame = panel?.frame ?? Self.defaultFrame()
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)
        panel.hasShadow = false
        panel.setFrame(frame, display: true)
        panel.contentView = SettingsHostingView(
            rootView: PromptTemplateManagerView(repository: repository)
        )
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        movedPanel === panel
    }

    static func defaultFrame() -> NSRect {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSRect(x: 120, y: 120, width: 980, height: 620)
        }

        let width = min(CGFloat(1100), visibleFrame.width > 96 ? visibleFrame.width - 96 : visibleFrame.width)
        let height = min(CGFloat(700), visibleFrame.height > 96 ? visibleFrame.height - 96 : visibleFrame.height)

        return NSRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2),
            width: width,
            height: height
        )
    }
}

private final class SettingsHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

- [ ] **Step 2: Pass repository to WindowCoordinator**

Modify `Sources/CodexPlusApp/AppDelegate.swift` by replacing `makeWorkbenchStore()` with a small runtime factory:

```swift
private struct AppRuntime {
    var store: WorkbenchStore
    var repository: any CodexPlusRepository
}

func applicationDidFinishLaunching(_ notification: Notification) {
    do {
        let runtime = try makeRuntime()
        self.windowCoordinator = WindowCoordinator(
            batteryProvider: IOKitBatteryStatusProvider(),
            workbenchStore: runtime.store,
            promptTemplateRepository: runtime.repository
        )
    } catch {
        presentInitializationFailure(error)
        return
    }

    let hotKeyController = HotKeyController { [windowCoordinator] in
        Task { @MainActor in
            windowCoordinator?.handleGlobalShortcut()
        }
    }

    do {
        try hotKeyController.register()
        self.hotKeyController = hotKeyController
    } catch {
        NSLog("CodexPlus hotkey registration failed: \(error)")
        presentHotKeyRegistrationFailure(error)
    }
}

private func makeRuntime() throws -> AppRuntime {
    try ApplicationDataMigrator.migrateLegacyLocalDataIfNeeded()
    let databasePath = try makeDatabasePath()
    let database = try SQLiteDatabase(path: databasePath)
    try CodexPlusSchema.migrate(database)
    let repository = SQLiteCodexPlusRepository(database: database)
    let engine = CodexCLIEngine(runner: ProcessCodexRunner())
    return AppRuntime(
        store: WorkbenchStore(repository: repository, engine: engine),
        repository: repository
    )
}
```

Remove the old `makeWorkbenchStore()` after the runtime factory compiles.

- [ ] **Step 3: Add settings controller to WindowCoordinator**

Modify `Sources/CodexPlusApp/WindowCoordinator.swift`:

```swift
private let promptTemplateRepository: any PromptTemplateRepository

private lazy var settingsPanelController = SettingsPanelController(
    panelFactory: panelFactory,
    panelDelegate: self,
    repository: promptTemplateRepository
)
```

Update the initializer:

```swift
init(
    batteryProvider: any BatteryStatusProviding,
    workbenchStore: WorkbenchStore,
    promptTemplateRepository: any PromptTemplateRepository
) {
    self.workbenchStore = workbenchStore
    self.promptTemplateRepository = promptTemplateRepository
    self.batteryMonitor = BatteryStatusMonitor(provider: batteryProvider)
    self.codexUsageMonitor = CodexUsageMonitor(provider: LocalCodexUsageProvider())
    self.dailyTokenUsageMonitor = DailyTokenUsageMonitor(provider: LocalDailyTokenUsageProvider())

    super.init()
    codexUsageMonitor.start()
    dailyTokenUsageMonitor.start()
    workbenchLauncherPanelController.show()
}
```

Add:

```swift
private func showSettings() {
    settingsPanelController.show()
}
```

Update `windowDidMove(_:)`:

```swift
if settingsPanelController.recordMove(of: panel) {
    return
}
```

- [ ] **Step 4: Add Settings action**

Modify `Sources/CodexPlusApp/Workbench/WorkbenchActions.swift`:

```swift
struct ProjectStripActions {
    let newConversation: () -> Void
    let returnToConversation: () -> Void
    let openArchive: () -> Void
    let openSettings: () -> Void
    let togglePin: () -> Void
    let selectProject: (UUID) -> Void
    let selectConversation: (UUID) -> Void
}
```

Modify `Sources/CodexPlusApp/Workbench/WorkbenchView.swift` in `actions`:

```swift
projectStrip: ProjectStripActions(
    newConversation: { store.beginNewConversationDraft() },
    returnToConversation: { store.returnToConversationPage() },
    openArchive: { store.showArchiveSearch() },
    openSettings: showSettings,
    togglePin: { store.togglePin() },
    selectProject: { store.selectProject($0) },
    selectConversation: { store.selectConversation($0) }
),
```

Add an `onOpenSettings` closure to `WorkbenchView`:

```swift
let onOpenSettings: () -> Void
```

Modify `Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift` by adding storage:

```swift
private let onOpenSettings: () -> Void
```

Update `WorkbenchPanelController.init`:

```swift
init(
    panelFactory: PanelFactory,
    screenProvider: ActiveScreenProvider,
    store: WorkbenchStore,
    codexUsageMonitor: CodexUsageMonitor,
    panelDelegate: NSWindowDelegate?,
    onShow: @escaping () -> Void,
    onHide: @escaping () -> Void,
    onOpenSettings: @escaping () -> Void
) {
    self.panelFactory = panelFactory
    self.screenProvider = screenProvider
    self.store = store
    self.codexUsageMonitor = codexUsageMonitor
    self.panelDelegate = panelDelegate
    self.onShow = onShow
    self.onHide = onHide
    self.onOpenSettings = onOpenSettings
}
```

Update `WorkbenchPanelController.show()`:

```swift
panel.contentView = WorkbenchPanelHostingView(
    rootView: WorkbenchView(
        store: store,
        codexUsageMonitor: codexUsageMonitor,
        onOpenSettings: onOpenSettings
    )
)
```

Update the lazy `workbenchPanelController` construction in `WindowCoordinator`:

```swift
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
    },
    onOpenSettings: { [weak self] in
        self?.showSettings()
    }
)
```

- [ ] **Step 5: Add gear button to top strip**

Modify `Sources/CodexPlusApp/Workbench/WorkbenchStrings.swift`:

```swift
static let settings = "设置"
static let openSettings = "打开设置"
```

Modify `Sources/CodexPlusApp/Workbench/TopProjectStripView.swift` in the top `HStack`, before `pinButton`:

```swift
settingsButton
pinButton
```

Add:

```swift
private var settingsButton: some View {
    Button(action: actions.openSettings) {
        Image(systemName: "gearshape")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 32, height: 32)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular, in: Circle())
    .compositingGroup()
    .mask(Circle())
    .help(WorkbenchStrings.settings)
    .accessibilityLabel(WorkbenchStrings.openSettings)
}
```

- [ ] **Step 6: Build to verify integration compiles**

Run: `swift build`

Expected: PASS.

- [ ] **Step 7: Manual smoke check**

Run the app from the local checkout:

```bash
swift run CodexPlusApp
```

Expected manual checks:

- Workbench shows a gear-shaped Settings button near the pin control.
- Clicking gear opens the Settings panel.
- Settings panel shows the prompt template manager.
- Built-in templates are greyed out.
- `复制为用户模板` creates an editable draft.
- User templates can be saved and reloaded.
- Left type filter can select both, one, or no type chips.
- Right type field is a dropdown single-select.

- [ ] **Step 8: Commit**

```bash
git add Sources/CodexPlusApp/Settings/SettingsPanelController.swift Sources/CodexPlusApp/AppDelegate.swift Sources/CodexPlusApp/WindowCoordinator.swift Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift Sources/CodexPlusApp/Workbench/WorkbenchActions.swift Sources/CodexPlusApp/Workbench/WorkbenchView.swift Sources/CodexPlusApp/Workbench/TopProjectStripView.swift Sources/CodexPlusApp/Workbench/WorkbenchStrings.swift
git commit -m "feat: add prompt template settings entry"
```

---

### Task 6: Full Verification

**Files:**
- No new files.

**Interfaces:**
- Consumes all task outputs.
- Produces final verification evidence.

- [ ] **Step 1: Run focused tests**

Run:

```bash
swift test --filter PromptTemplateLibraryTests
swift test --filter PromptTemplatePersistenceTests
```

Expected: PASS.

- [ ] **Step 2: Run full core tests**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 3: Run build**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 4: Check diff cleanliness**

Run:

```bash
git diff --check
git status --short
```

Expected:

- `git diff --check` exits 0.
- `git status --short` shows only intentional files from this feature plus any unrelated pre-existing user changes that were present before implementation.

- [ ] **Step 5: Commit any verification-only fixes**

If Step 1-4 required fixes, commit only feature files that changed during verification:

```bash
git add Sources/CodexPlusCore/PromptTemplates/PromptTemplateModels.swift Sources/CodexPlusCore/PromptTemplates/PromptTemplateLibrary.swift Sources/CodexPlusCore/Persistence/PromptTemplateRepository.swift Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift Sources/CodexPlusApp/Settings/PromptTemplateSettingsStore.swift Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift Sources/CodexPlusApp/Settings/SettingsPanelController.swift Sources/CodexPlusApp/AppDelegate.swift Sources/CodexPlusApp/WindowCoordinator.swift Sources/CodexPlusApp/Workbench/WorkbenchPanelController.swift Sources/CodexPlusApp/Workbench/WorkbenchActions.swift Sources/CodexPlusApp/Workbench/WorkbenchView.swift Sources/CodexPlusApp/Workbench/TopProjectStripView.swift Sources/CodexPlusApp/Workbench/WorkbenchStrings.swift Sources/CodexPlusApp/Workbench/WorkbenchMetrics.swift Tests/CodexPlusCoreXCTests/PromptTemplateLibraryTests.swift Tests/CodexPlusCoreXCTests/PromptTemplatePersistenceTests.swift
git commit -m "fix: stabilize prompt template manager"
```
