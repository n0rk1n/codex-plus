# Codex+ Mac Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS MVP with a Liquid Glass quick AI entry, one battery tile, Codex CLI JSONL streaming, side-window conversation behavior, and per-conversation permission reset.

**Architecture:** Use a Swift Package with a testable `CodexPlusCore` library and a `CodexPlusApp` executable. Keep pure state, battery mapping, Codex event parsing, and conversation coordination in the library; keep AppKit/SwiftUI windowing and visual treatment in the app target.

**Tech Stack:** Swift 6.3, Swift Package Manager, custom executable Swift test harness, SwiftUI, AppKit, IOKit power source APIs, Carbon global hotkey APIs, Foundation `Process` for `codex exec --json`.

---

## Scope Check

The approved MVP is one coherent subsystem: a quick AI overlay with one battery dashboard tile and one Codex-backed conversation surface. Do not implement system toggles, Homebrew management, maintenance diagnostics, persistent history, Markdown audit export, SQLite, or extra dashboard tiles in this plan.

## Execution Amendment: Test Harness

This Mac has Command Line Tools only. `XCTest` and Swift Testing are unavailable, so every `swift test` instruction in this plan is superseded by the executable harness command:

```bash
swift run CodexPlusCoreTests
```

New tests should be added to `Tests/CodexPlusCoreTests/main.swift` or helper files in that executable target. Keep the same red-green discipline: first run the harness and observe the expected failure, then implement, then run the harness again until it passes. Continue to run `swift build` for compilation checks.

## File Structure

- Create: `Package.swift`
  - Defines a library target, app executable target, and XCTest target.
- Create: `Sources/CodexPlusCore/BatteryStatus.swift`
  - Battery domain model and IOKit-backed provider.
- Create: `Sources/CodexPlusCore/ConversationModels.swift`
  - Permission, conversation state, side, session, and UI event models.
- Create: `Sources/CodexPlusCore/CodexEventParser.swift`
  - Converts `codex exec --json` JSONL lines into displayable events.
- Create: `Sources/CodexPlusCore/CodexCommandBuilder.swift`
  - Produces exact `codex exec` arguments for semi-automatic and Full Access modes.
- Create: `Sources/CodexPlusCore/ConversationCoordinator.swift`
  - Owns in-memory conversation lifecycle, shortcut recall rules, and permission reset.
- Create: `Sources/CodexPlusCore/LineBuffer.swift`
  - Buffers process stdout chunks into complete lines.
- Create: `Sources/CodexPlusCore/ProcessCodexRunner.swift`
  - Runs `codex exec --json`, streams stdout/stderr, supports stop.
- Create: `Sources/CodexPlusApp/main.swift`
  - Starts an accessory-style `NSApplication`.
- Create: `Sources/CodexPlusApp/AppDelegate.swift`
  - Wires services, hotkey, window coordinator, and runner.
- Create: `Sources/CodexPlusApp/HotKeyController.swift`
  - Registers Control-Option-Space through Carbon.
- Create: `Sources/CodexPlusApp/WindowCoordinator.swift`
  - Shows compact panel, expands side window, remembers side, hides on mouse exit.
- Create: `Sources/CodexPlusApp/GlassPanel.swift`
  - Borderless, transparent, key-capable `NSPanel`.
- Create: `Sources/CodexPlusApp/Views/LiquidGlassContainer.swift`
  - Shared translucent material wrapper.
- Create: `Sources/CodexPlusApp/Views/BatteryTileView.swift`
  - Square battery tile.
- Create: `Sources/CodexPlusApp/Views/CompactEntryView.swift`
  - Two-layer quick entry with focused input.
- Create: `Sources/CodexPlusApp/Views/ConversationView.swift`
  - Header controls, event stream, footer input.
- Create: `Sources/CodexPlusApp/Views/ConversationEventRow.swift`
  - Renders one conversation event.
- Create: `Tests/CodexPlusCoreTests/BatteryStatusTests.swift`
- Create: `Tests/CodexPlusCoreTests/CodexEventParserTests.swift`
- Create: `Tests/CodexPlusCoreTests/CodexCommandBuilderTests.swift`
- Create: `Tests/CodexPlusCoreTests/ConversationCoordinatorTests.swift`
- Create: `Tests/CodexPlusCoreTests/LineBufferTests.swift`

## Task 1: Scaffold Swift Package

**Files:**
- Create: `Package.swift`
- Create: `Sources/CodexPlusCore/ConversationModels.swift`
- Create: `Sources/CodexPlusApp/main.swift`
- Create: `Tests/CodexPlusCoreTests/ConversationModelsSmokeTests.swift`

- [ ] **Step 1: Create the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexPlus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexPlusCore", targets: ["CodexPlusCore"]),
        .executable(name: "CodexPlusApp", targets: ["CodexPlusApp"])
    ],
    targets: [
        .target(
            name: "CodexPlusCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "CodexPlusApp",
            dependencies: ["CodexPlusCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "CodexPlusCoreTests",
            dependencies: ["CodexPlusCore"]
        )
    ]
)
```

- [ ] **Step 2: Add initial core model file**

Create `Sources/CodexPlusCore/ConversationModels.swift`:

```swift
import Foundation

public enum PermissionMode: String, Equatable, Sendable {
    case semiAutomatic
    case fullAccess

    public var displayName: String {
        switch self {
        case .semiAutomatic:
            return "Semi-Automatic"
        case .fullAccess:
            return "Full Access"
        }
    }
}

public enum ConversationRunState: String, Equatable, Sendable {
    case idle
    case running
    case completed
    case failed
    case stopped

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .stopped:
            return true
        case .idle, .running:
            return false
        }
    }
}

public enum SideAttachment: String, Equatable, Sendable {
    case left
    case right
}

public struct ConversationSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var prompt: String
    public var state: ConversationRunState
    public var permissionMode: PermissionMode
    public var isPinned: Bool
    public var isExplicitlyKept: Bool

    public init(
        id: UUID = UUID(),
        prompt: String,
        state: ConversationRunState = .idle,
        permissionMode: PermissionMode = .semiAutomatic,
        isPinned: Bool = false,
        isExplicitlyKept: Bool = false
    ) {
        self.id = id
        self.prompt = prompt
        self.state = state
        self.permissionMode = permissionMode
        self.isPinned = isPinned
        self.isExplicitlyKept = isExplicitlyKept
    }
}
```

- [ ] **Step 3: Add temporary executable entry point**

Create `Sources/CodexPlusApp/main.swift`:

```swift
import Foundation
import CodexPlusCore

let mode = PermissionMode.semiAutomatic
print("CodexPlusApp bootstrap: \(mode.displayName)")
```

- [ ] **Step 4: Add a smoke test**

Create `Tests/CodexPlusCoreTests/ConversationModelsSmokeTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class ConversationModelsSmokeTests: XCTestCase {
    func testPermissionModeDisplayName() {
        XCTAssertEqual(PermissionMode.semiAutomatic.displayName, "Semi-Automatic")
        XCTAssertEqual(PermissionMode.fullAccess.displayName, "Full Access")
    }

    func testTerminalStates() {
        XCTAssertFalse(ConversationRunState.idle.isTerminal)
        XCTAssertFalse(ConversationRunState.running.isTerminal)
        XCTAssertTrue(ConversationRunState.completed.isTerminal)
        XCTAssertTrue(ConversationRunState.failed.isTerminal)
        XCTAssertTrue(ConversationRunState.stopped.isTerminal)
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test
```

Expected: test build succeeds and `2 tests` pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: scaffold quick AI dashboard package"
```

## Task 2: Battery Status Model And Provider

**Files:**
- Create: `Sources/CodexPlusCore/BatteryStatus.swift`
- Create: `Tests/CodexPlusCoreTests/BatteryStatusTests.swift`

- [ ] **Step 1: Write failing battery mapping tests**

Create `Tests/CodexPlusCoreTests/BatteryStatusTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class BatteryStatusTests: XCTestCase {
    func testMapsChargingBattery() {
        let status = BatteryStatus.from(
            currentCapacity: 43,
            maxCapacity: 100,
            isCharging: true,
            powerSourceState: "AC Power"
        )

        XCTAssertEqual(status.percentage, 43)
        XCTAssertEqual(status.state, .charging)
    }

    func testMapsFullBattery() {
        let status = BatteryStatus.from(
            currentCapacity: 100,
            maxCapacity: 100,
            isCharging: false,
            powerSourceState: "AC Power"
        )

        XCTAssertEqual(status.percentage, 100)
        XCTAssertEqual(status.state, .full)
    }

    func testMapsDischargingBattery() {
        let status = BatteryStatus.from(
            currentCapacity: 66,
            maxCapacity: 100,
            isCharging: false,
            powerSourceState: "Battery Power"
        )

        XCTAssertEqual(status.percentage, 66)
        XCTAssertEqual(status.state, .discharging)
    }

    func testUnknownWhenCapacityInvalid() {
        let status = BatteryStatus.from(
            currentCapacity: nil,
            maxCapacity: 0,
            isCharging: nil,
            powerSourceState: nil
        )

        XCTAssertNil(status.percentage)
        XCTAssertEqual(status.state, .unknown)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter BatteryStatusTests
```

Expected: FAIL because `BatteryStatus` is not defined.

- [ ] **Step 3: Implement battery status and native provider**

Create `Sources/CodexPlusCore/BatteryStatus.swift`:

```swift
import Foundation
import IOKit.ps

public enum BatteryChargingState: String, Equatable, Sendable {
    case charging
    case discharging
    case full
    case unknown
}

public struct BatteryStatus: Equatable, Sendable {
    public let percentage: Int?
    public let state: BatteryChargingState

    public init(percentage: Int?, state: BatteryChargingState) {
        self.percentage = percentage
        self.state = state
    }

    public static let unknown = BatteryStatus(percentage: nil, state: .unknown)

    public static func from(
        currentCapacity: Int?,
        maxCapacity: Int?,
        isCharging: Bool?,
        powerSourceState: String?
    ) -> BatteryStatus {
        guard
            let currentCapacity,
            let maxCapacity,
            maxCapacity > 0
        else {
            return .unknown
        }

        let percentage = max(0, min(100, Int((Double(currentCapacity) / Double(maxCapacity)) * 100.0)))

        if percentage >= 100 {
            return BatteryStatus(percentage: percentage, state: .full)
        }

        if isCharging == true {
            return BatteryStatus(percentage: percentage, state: .charging)
        }

        if powerSourceState == kIOPSBatteryPowerValue {
            return BatteryStatus(percentage: percentage, state: .discharging)
        }

        return BatteryStatus(percentage: percentage, state: .unknown)
    }
}

public protocol BatteryStatusProviding: Sendable {
    func currentStatus() -> BatteryStatus
}

public struct IOKitBatteryStatusProvider: BatteryStatusProviding {
    public init() {}

    public func currentStatus() -> BatteryStatus {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
            let firstSource = list.first,
            let description = IOPSGetPowerSourceDescription(info, firstSource)?.takeUnretainedValue() as? [String: Any]
        else {
            return .unknown
        }

        let current = description[kIOPSCurrentCapacityKey as String] as? Int
        let max = description[kIOPSMaxCapacityKey as String] as? Int
        let charging = description[kIOPSIsChargingKey as String] as? Bool
        let sourceState = description[kIOPSPowerSourceStateKey as String] as? String

        return BatteryStatus.from(
            currentCapacity: current,
            maxCapacity: max,
            isCharging: charging,
            powerSourceState: sourceState
        )
    }
}
```

- [ ] **Step 4: Run battery tests**

Run:

```bash
swift test --filter BatteryStatusTests
```

Expected: all `BatteryStatusTests` pass.

- [ ] **Step 5: Run full tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/CodexPlusCore/BatteryStatus.swift Tests/CodexPlusCoreTests/BatteryStatusTests.swift
git commit -m "feat: add battery status provider"
```

## Task 3: Codex Event Parsing And Command Building

**Files:**
- Create: `Sources/CodexPlusCore/CodexEventParser.swift`
- Create: `Sources/CodexPlusCore/CodexCommandBuilder.swift`
- Create: `Tests/CodexPlusCoreTests/CodexEventParserTests.swift`
- Create: `Tests/CodexPlusCoreTests/CodexCommandBuilderTests.swift`

- [ ] **Step 1: Write failing parser tests**

Create `Tests/CodexPlusCoreTests/CodexEventParserTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class CodexEventParserTests: XCTestCase {
    func testParsesThreadStarted() {
        let event = CodexEventParser.parseLine(#"{"type":"thread.started","thread_id":"abc"}"#)
        XCTAssertEqual(event, .threadStarted("abc"))
    }

    func testParsesAgentMessage() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"Hello"}} "#
        let event = CodexEventParser.parseLine(line)
        XCTAssertEqual(event, .agentMessage("Hello"))
    }

    func testParsesCommandExecution() {
        let line = #"{"type":"item.started","item":{"id":"cmd1","type":"command_execution","command":"pwd","status":"in_progress"}}"#
        let event = CodexEventParser.parseLine(line)
        XCTAssertEqual(event, .command(id: "cmd1", command: "pwd", status: .inProgress))
    }

    func testMalformedLineReturnsParseWarning() {
        let event = CodexEventParser.parseLine("{broken")
        XCTAssertEqual(event, .parseWarning("{broken"))
    }
}
```

- [ ] **Step 2: Write failing command builder tests**

Create `Tests/CodexPlusCoreTests/CodexCommandBuilderTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class CodexCommandBuilderTests: XCTestCase {
    func testSemiAutomaticUsesReadOnlySandbox() {
        let args = CodexCommandBuilder.arguments(
            prompt: "Summarize this Mac",
            permissionMode: .semiAutomatic
        )

        XCTAssertEqual(args, [
            "exec",
            "--json",
            "--sandbox",
            "read-only",
            "--",
            "Summarize this Mac"
        ])
    }

    func testFullAccessUsesDangerFullAccessSandbox() {
        let args = CodexCommandBuilder.arguments(
            prompt: "Fix the local setup",
            permissionMode: .fullAccess
        )

        XCTAssertEqual(args, [
            "exec",
            "--json",
            "--sandbox",
            "danger-full-access",
            "--",
            "Fix the local setup"
        ])
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --filter Codex
```

Expected: FAIL because parser and command builder are not defined.

- [ ] **Step 4: Implement parser**

Create `Sources/CodexPlusCore/CodexEventParser.swift`:

```swift
import Foundation

public enum CodexCommandStatus: String, Equatable, Sendable {
    case inProgress
    case completed
    case failed
    case unknown

    static func from(_ value: String?) -> CodexCommandStatus {
        switch value {
        case "in_progress":
            return .inProgress
        case "completed":
            return .completed
        case "failed":
            return .failed
        default:
            return .unknown
        }
    }
}

public enum CodexEvent: Equatable, Sendable {
    case threadStarted(String)
    case turnStarted
    case turnCompleted
    case turnFailed(String)
    case agentMessage(String)
    case command(id: String?, command: String, status: CodexCommandStatus)
    case error(String)
    case raw(String)
    case parseWarning(String)
}

public enum CodexEventParser {
    public static func parseLine(_ line: String) -> CodexEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .raw("")
        }

        guard let data = trimmed.data(using: .utf8) else {
            return .parseWarning(trimmed)
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else {
            return .parseWarning(trimmed)
        }

        switch type {
        case "thread.started":
            return .threadStarted(object["thread_id"] as? String ?? "unknown")
        case "turn.started":
            return .turnStarted
        case "turn.completed":
            return .turnCompleted
        case "turn.failed":
            return .turnFailed(object["message"] as? String ?? "Codex turn failed")
        case "error":
            return .error(object["message"] as? String ?? "Codex error")
        case "item.started", "item.completed":
            return parseItem(object["item"] as? [String: Any], fallback: trimmed)
        default:
            return .raw(trimmed)
        }
    }

    private static func parseItem(_ item: [String: Any]?, fallback: String) -> CodexEvent {
        guard let item, let itemType = item["type"] as? String else {
            return .raw(fallback)
        }

        switch itemType {
        case "agent_message":
            guard let text = item["text"] as? String, !text.isEmpty else {
                return .raw(fallback)
            }
            return .agentMessage(text)
        case "command_execution":
            let command = item["command"] as? String ?? "unknown command"
            let status = CodexCommandStatus.from(item["status"] as? String)
            return .command(id: item["id"] as? String, command: command, status: status)
        default:
            return .raw(fallback)
        }
    }
}
```

- [ ] **Step 5: Implement command builder**

Create `Sources/CodexPlusCore/CodexCommandBuilder.swift`:

```swift
import Foundation

public enum CodexCommandBuilder {
    public static func arguments(prompt: String, permissionMode: PermissionMode) -> [String] {
        [
            "exec",
            "--json",
            "--sandbox",
            sandboxValue(for: permissionMode),
            "--",
            prompt
        ]
    }

    private static func sandboxValue(for permissionMode: PermissionMode) -> String {
        switch permissionMode {
        case .semiAutomatic:
            return "read-only"
        case .fullAccess:
            return "danger-full-access"
        }
    }
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --filter Codex
```

Expected: all Codex parser and command builder tests pass.

- [ ] **Step 7: Run full tests and commit**

Run:

```bash
swift test
```

Expected: all tests pass.

Commit:

```bash
git add Sources/CodexPlusCore/CodexEventParser.swift Sources/CodexPlusCore/CodexCommandBuilder.swift Tests/CodexPlusCoreTests/CodexEventParserTests.swift Tests/CodexPlusCoreTests/CodexCommandBuilderTests.swift
git commit -m "feat: parse codex json events"
```

## Task 4: Conversation Coordination And Permission Reset

**Files:**
- Modify: `Sources/CodexPlusCore/ConversationModels.swift`
- Create: `Sources/CodexPlusCore/ConversationCoordinator.swift`
- Create: `Tests/CodexPlusCoreTests/ConversationCoordinatorTests.swift`

- [ ] **Step 1: Replace conversation models with event-capable models**

Replace `Sources/CodexPlusCore/ConversationModels.swift` with:

```swift
import Foundation

public enum PermissionMode: String, Equatable, Sendable {
    case semiAutomatic
    case fullAccess

    public var displayName: String {
        switch self {
        case .semiAutomatic:
            return "Semi-Automatic"
        case .fullAccess:
            return "Full Access"
        }
    }
}

public enum ConversationRunState: String, Equatable, Sendable {
    case idle
    case running
    case completed
    case failed
    case stopped

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .stopped:
            return true
        case .idle, .running:
            return false
        }
    }
}

public enum SideAttachment: String, Equatable, Sendable {
    case left
    case right

    public mutating func toggle() {
        self = self == .left ? .right : .left
    }
}

public enum ConversationDisplayEvent: Equatable, Identifiable, Sendable {
    case userPrompt(id: UUID, text: String)
    case status(id: UUID, text: String)
    case assistantMessage(id: UUID, text: String)
    case command(id: UUID, executionID: String?, command: String, status: CodexCommandStatus)
    case error(id: UUID, text: String)
    case parseWarning(id: UUID, text: String)

    public var id: UUID {
        switch self {
        case let .userPrompt(id, _),
             let .status(id, _),
             let .assistantMessage(id, _),
             let .command(id, _, _, _),
             let .error(id, _),
             let .parseWarning(id, _):
            return id
        }
    }
}

public struct ConversationSession: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var prompt: String
    public var state: ConversationRunState
    public var permissionMode: PermissionMode
    public var isPinned: Bool
    public var isExplicitlyKept: Bool
    public var events: [ConversationDisplayEvent]

    public init(
        id: UUID = UUID(),
        prompt: String,
        state: ConversationRunState = .idle,
        permissionMode: PermissionMode = .semiAutomatic,
        isPinned: Bool = false,
        isExplicitlyKept: Bool = false,
        events: [ConversationDisplayEvent] = []
    ) {
        self.id = id
        self.prompt = prompt
        self.state = state
        self.permissionMode = permissionMode
        self.isPinned = isPinned
        self.isExplicitlyKept = isExplicitlyKept
        self.events = events
    }
}

public enum ShortcutDecision: Equatable, Sendable {
    case recallExisting(UUID)
    case openFreshEntry
}
```

- [ ] **Step 2: Write failing coordinator tests**

Create `Tests/CodexPlusCoreTests/ConversationCoordinatorTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

@MainActor
final class ConversationCoordinatorTests: XCTestCase {
    func testShortcutOpensFreshEntryWhenNoConversation() {
        let coordinator = ConversationCoordinator()
        XCTAssertEqual(coordinator.shortcutDecision(), .openFreshEntry)
    }

    func testShortcutRecallsRunningConversation() {
        let coordinator = ConversationCoordinator()
        let session = coordinator.startConversation(prompt: "run")
        coordinator.markRunning(session.id)

        XCTAssertEqual(coordinator.shortcutDecision(), .recallExisting(session.id))
    }

    func testShortcutRecallsPinnedConversation() {
        let coordinator = ConversationCoordinator()
        let session = coordinator.startConversation(prompt: "pin")
        coordinator.setPinned(true, for: session.id)

        XCTAssertEqual(coordinator.shortcutDecision(), .recallExisting(session.id))
    }

    func testShortcutRecallsKeptConversation() {
        let coordinator = ConversationCoordinator()
        let session = coordinator.startConversation(prompt: "keep")
        coordinator.setExplicitlyKept(true, for: session.id)

        XCTAssertEqual(coordinator.shortcutDecision(), .recallExisting(session.id))
    }

    func testCompletedConversationResetsFullAccessAndAllowsFreshEntry() {
        let coordinator = ConversationCoordinator()
        let session = coordinator.startConversation(prompt: "full")
        coordinator.setPermissionMode(.fullAccess, for: session.id)
        coordinator.markRunning(session.id)
        coordinator.markCompleted(session.id)

        XCTAssertEqual(coordinator.activeConversation?.permissionMode, .semiAutomatic)
        XCTAssertEqual(coordinator.activeConversation?.state, .completed)
        XCTAssertEqual(coordinator.shortcutDecision(), .openFreshEntry)
    }

    func testCodexEventsBecomeDisplayEvents() {
        let coordinator = ConversationCoordinator()
        let session = coordinator.startConversation(prompt: "hello")
        coordinator.appendCodexEvent(.agentMessage("world"), to: session.id)

        XCTAssertEqual(coordinator.activeConversation?.events.count, 2)
        XCTAssertEqual(coordinator.activeConversation?.events.last, .assistantMessage(id: coordinator.activeConversation!.events.last!.id, text: "world"))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --filter ConversationCoordinatorTests
```

Expected: FAIL because `ConversationCoordinator` is not defined.

- [ ] **Step 4: Implement coordinator**

Create `Sources/CodexPlusCore/ConversationCoordinator.swift`:

```swift
import Combine
import Foundation

@MainActor
public final class ConversationCoordinator: ObservableObject {
    @Published public private(set) var activeConversation: ConversationSession?
    @Published public private(set) var preferredSide: SideAttachment = .right

    public init() {}

    @discardableResult
    public func startConversation(prompt: String) -> ConversationSession {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = ConversationSession(
            prompt: trimmed,
            events: [.userPrompt(id: UUID(), text: trimmed)]
        )
        activeConversation = session
        return session
    }

    public func shortcutDecision() -> ShortcutDecision {
        guard let activeConversation else {
            return .openFreshEntry
        }

        if activeConversation.state == .running || activeConversation.isPinned || activeConversation.isExplicitlyKept {
            return .recallExisting(activeConversation.id)
        }

        return .openFreshEntry
    }

    public func markRunning(_ id: UUID) {
        update(id) { conversation in
            conversation.state = .running
            conversation.events.append(.status(id: UUID(), text: "Codex task running"))
        }
    }

    public func markCompleted(_ id: UUID) {
        updateTerminal(id, state: .completed, message: "Codex task completed")
    }

    public func markFailed(_ id: UUID, message: String) {
        update(id) { conversation in
            conversation.events.append(.error(id: UUID(), text: message))
        }
        updateTerminal(id, state: .failed, message: "Codex task failed")
    }

    public func markStopped(_ id: UUID) {
        updateTerminal(id, state: .stopped, message: "Codex task stopped")
    }

    public func setPermissionMode(_ mode: PermissionMode, for id: UUID) {
        update(id) { conversation in
            conversation.permissionMode = mode
            conversation.events.append(.status(id: UUID(), text: "Permission mode: \(mode.displayName)"))
        }
    }

    public func setPinned(_ isPinned: Bool, for id: UUID) {
        update(id) { conversation in
            conversation.isPinned = isPinned
        }
    }

    public func setExplicitlyKept(_ isKept: Bool, for id: UUID) {
        update(id) { conversation in
            conversation.isExplicitlyKept = isKept
        }
    }

    public func togglePreferredSide() {
        preferredSide.toggle()
    }

    public func appendCodexEvent(_ event: CodexEvent, to id: UUID) {
        update(id) { conversation in
            conversation.events.append(Self.displayEvent(from: event))
        }
    }

    private func updateTerminal(_ id: UUID, state: ConversationRunState, message: String) {
        update(id) { conversation in
            conversation.state = state
            conversation.permissionMode = .semiAutomatic
            conversation.events.append(.status(id: UUID(), text: message))
        }
    }

    private func update(_ id: UUID, _ change: (inout ConversationSession) -> Void) {
        guard var conversation = activeConversation, conversation.id == id else {
            return
        }
        change(&conversation)
        activeConversation = conversation
    }

    private static func displayEvent(from event: CodexEvent) -> ConversationDisplayEvent {
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
        case let .command(executionID, command, status):
            return .command(id: UUID(), executionID: executionID, command: command, status: status)
        case let .error(message):
            return .error(id: UUID(), text: message)
        case let .raw(text):
            return .status(id: UUID(), text: text)
        case let .parseWarning(text):
            return .parseWarning(id: UUID(), text: text)
        }
    }
}
```

- [ ] **Step 5: Run coordinator tests**

Run:

```bash
swift test --filter ConversationCoordinatorTests
```

Expected: all coordinator tests pass.

- [ ] **Step 6: Run full tests and commit**

Run:

```bash
swift test
```

Expected: all tests pass.

Commit:

```bash
git add Sources/CodexPlusCore/ConversationModels.swift Sources/CodexPlusCore/ConversationCoordinator.swift Tests/CodexPlusCoreTests/ConversationCoordinatorTests.swift
git commit -m "feat: coordinate conversation lifecycle"
```

## Task 5: Line Buffer And Process Codex Runner

**Files:**
- Create: `Sources/CodexPlusCore/LineBuffer.swift`
- Create: `Sources/CodexPlusCore/ProcessCodexRunner.swift`
- Create: `Tests/CodexPlusCoreTests/LineBufferTests.swift`

- [ ] **Step 1: Write failing line buffer tests**

Create `Tests/CodexPlusCoreTests/LineBufferTests.swift`:

```swift
import XCTest
@testable import CodexPlusCore

final class LineBufferTests: XCTestCase {
    func testReturnsCompleteLinesAndKeepsPartialLine() {
        var buffer = LineBuffer()

        let first = buffer.append("one\ntw")
        XCTAssertEqual(first, ["one"])

        let second = buffer.append("o\nthree\n")
        XCTAssertEqual(second, ["two", "three"])

        XCTAssertEqual(buffer.flush(), nil)
    }

    func testFlushReturnsRemainingPartialLine() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append("partial"), [])
        XCTAssertEqual(buffer.flush(), "partial")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter LineBufferTests
```

Expected: FAIL because `LineBuffer` is not defined.

- [ ] **Step 3: Implement line buffer**

Create `Sources/CodexPlusCore/LineBuffer.swift`:

```swift
import Foundation

public struct LineBuffer: Sendable {
    private var storage = ""

    public init() {}

    public mutating func append(_ chunk: String) -> [String] {
        storage += chunk
        var lines: [String] = []

        while let newlineRange = storage.range(of: "\n") {
            let line = String(storage[..<newlineRange.lowerBound])
            lines.append(line)
            storage.removeSubrange(storage.startIndex...newlineRange.lowerBound)
        }

        return lines
    }

    public mutating func flush() -> String? {
        guard !storage.isEmpty else {
            return nil
        }
        let remaining = storage
        storage.removeAll()
        return remaining
    }
}
```

- [ ] **Step 4: Implement Codex runner**

Create `Sources/CodexPlusCore/ProcessCodexRunner.swift`:

```swift
import Foundation

public struct CodexRunResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stderr: String

    public var succeeded: Bool {
        exitCode == 0
    }
}

public protocol CodexRunHandle: Sendable {
    func stop()
}

public final class ProcessCodexRunHandle: CodexRunHandle, @unchecked Sendable {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    public func stop() {
        if process.isRunning {
            process.terminate()
        }
    }
}

public final class ProcessCodexRunner: @unchecked Sendable {
    private let executableURL: URL
    private let parser: (String) -> CodexEvent

    public init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        parser: @escaping (String) -> CodexEvent = CodexEventParser.parseLine
    ) {
        self.executableURL = executableURL
        self.parser = parser
    }

    @discardableResult
    public func run(
        prompt: String,
        permissionMode: PermissionMode,
        onEvent: @escaping @Sendable (CodexEvent) -> Void,
        onFinish: @escaping @Sendable (CodexRunResult) -> Void
    ) -> CodexRunHandle {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutLock = NSLock()
        let stderrLock = NSLock()
        var stdoutBuffer = LineBuffer()
        var stderrText = ""

        process.executableURL = executableURL
        process.arguments = ["codex"] + CodexCommandBuilder.arguments(
            prompt: prompt,
            permissionMode: permissionMode
        )
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                return
            }

            stdoutLock.lock()
            let lines = stdoutBuffer.append(chunk)
            stdoutLock.unlock()

            for line in lines {
                onEvent(self.parser(line))
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                return
            }

            stderrLock.lock()
            stderrText += chunk
            stderrLock.unlock()
        }

        process.terminationHandler = { process in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil

            stdoutLock.lock()
            let remainingLine = stdoutBuffer.flush()
            stdoutLock.unlock()

            if let remainingLine {
                onEvent(self.parser(remainingLine))
            }

            stderrLock.lock()
            let finalStderr = stderrText
            stderrLock.unlock()

            onFinish(CodexRunResult(exitCode: process.terminationStatus, stderr: finalStderr))
        }

        do {
            try process.run()
        } catch {
            onEvent(.error("Unable to start codex: \(error.localizedDescription)"))
            onFinish(CodexRunResult(exitCode: 127, stderr: error.localizedDescription))
        }

        return ProcessCodexRunHandle(process: process)
    }
}
```

- [ ] **Step 5: Run line buffer tests**

Run:

```bash
swift test --filter LineBufferTests
```

Expected: all line buffer tests pass.

- [ ] **Step 6: Run full tests and commit**

Run:

```bash
swift test
```

Expected: all tests pass.

Commit:

```bash
git add Sources/CodexPlusCore/LineBuffer.swift Sources/CodexPlusCore/ProcessCodexRunner.swift Tests/CodexPlusCoreTests/LineBufferTests.swift
git commit -m "feat: stream codex process output"
```

## Task 6: App Bootstrap, Hotkey, And Window Shell

**Files:**
- Replace: `Sources/CodexPlusApp/main.swift`
- Create: `Sources/CodexPlusApp/AppDelegate.swift`
- Create: `Sources/CodexPlusApp/HotKeyController.swift`
- Create: `Sources/CodexPlusApp/GlassPanel.swift`
- Create: `Sources/CodexPlusApp/WindowCoordinator.swift`

- [ ] **Step 1: Replace executable entry point**

Replace `Sources/CodexPlusApp/main.swift` with:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 2: Add app delegate**

Create `Sources/CodexPlusApp/AppDelegate.swift`:

```swift
import AppKit
import CodexPlusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let conversationCoordinator = ConversationCoordinator()
    private let batteryProvider = IOKitBatteryStatusProvider()
    private let codexRunner = ProcessCodexRunner()
    private var windowCoordinator: WindowCoordinator?
    private var hotKeyController: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let windowCoordinator = WindowCoordinator(
            conversationCoordinator: conversationCoordinator,
            batteryProvider: batteryProvider,
            codexRunner: codexRunner
        )
        self.windowCoordinator = windowCoordinator

        let hotKeyController = HotKeyController {
            Task { @MainActor in
                windowCoordinator.handleGlobalShortcut()
            }
        }
        self.hotKeyController = hotKeyController
        hotKeyController.register()
    }
}
```

- [ ] **Step 3: Add global hotkey controller**

Create `Sources/CodexPlusApp/HotKeyController.swift`:

```swift
import Carbon
import Foundation

final class HotKeyController {
    private let onPressed: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(onPressed: @escaping () -> Void) {
        self.onPressed = onPressed
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if hotKeyID.signature == HotKeyController.signature && hotKeyID.id == HotKeyController.identifier {
                    let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                    controller.onPressed()
                }

                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandlerRef
        )

        var hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private static let signature = OSType(0x51414944)
    private static let identifier = UInt32(1)
}
```

- [ ] **Step 4: Add key-capable glass panel**

Create `Sources/CodexPlusApp/GlassPanel.swift`:

```swift
import AppKit

final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
    }
}
```

- [ ] **Step 5: Add temporary window coordinator shell**

Create `Sources/CodexPlusApp/WindowCoordinator.swift`:

```swift
import AppKit
import SwiftUI
import CodexPlusCore

@MainActor
final class WindowCoordinator {
    private let conversationCoordinator: ConversationCoordinator
    private let batteryProvider: BatteryStatusProviding
    private let codexRunner: ProcessCodexRunner

    private var compactPanel: GlassPanel?
    private var sidePanel: GlassPanel?

    init(
        conversationCoordinator: ConversationCoordinator,
        batteryProvider: BatteryStatusProviding,
        codexRunner: ProcessCodexRunner
    ) {
        self.conversationCoordinator = conversationCoordinator
        self.batteryProvider = batteryProvider
        self.codexRunner = codexRunner
    }

    func handleGlobalShortcut() {
        switch conversationCoordinator.shortcutDecision() {
        case .recallExisting:
            showSidePanel()
        case .openFreshEntry:
            showCompactPanel()
        }
    }

    private func showCompactPanel() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: 420, height: 210)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - screenFrame.height * 0.28 - size.height / 2
        )

        let panel = compactPanel ?? GlassPanel(contentRect: NSRect(origin: origin, size: size))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.contentView = NSHostingView(
            rootView: Text("Codex+").padding()
        )
        compactPanel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSidePanel() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: 460, height: screenFrame.height)
        let origin = NSPoint(x: screenFrame.maxX - size.width, y: screenFrame.minY)

        let panel = sidePanel ?? GlassPanel(contentRect: NSRect(origin: origin, size: size))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.contentView = NSHostingView(
            rootView: Text("Conversation").padding()
        )
        sidePanel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 6: Build the app target**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 7: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/CodexPlusApp
git commit -m "feat: add mac app window shell"
```

## Task 7: Liquid Glass SwiftUI Views

**Files:**
- Create: `Sources/CodexPlusApp/Views/LiquidGlassContainer.swift`
- Create: `Sources/CodexPlusApp/Views/BatteryTileView.swift`
- Create: `Sources/CodexPlusApp/Views/ConversationEventRow.swift`
- Create: `Sources/CodexPlusApp/Views/CompactEntryView.swift`
- Create: `Sources/CodexPlusApp/Views/ConversationView.swift`

- [ ] **Step 1: Add shared Liquid Glass container**

Create `Sources/CodexPlusApp/Views/LiquidGlassContainer.swift`:

```swift
import SwiftUI

struct LiquidGlassContainer<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.20), radius: 28, x: 0, y: 18)
    }
}
```

- [ ] **Step 2: Add battery tile view**

Create `Sources/CodexPlusApp/Views/BatteryTileView.swift`:

```swift
import SwiftUI
import CodexPlusCore

struct BatteryTileView: View {
    let status: BatteryStatus

    var body: some View {
        LiquidGlassContainer(cornerRadius: 18) {
            VStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(percentText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text(stateText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 92, height: 92)
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Battery \(percentText), \(stateText)")
    }

    private var percentText: String {
        guard let percentage = status.percentage else {
            return "--%"
        }
        return "\(percentage)%"
    }

    private var stateText: String {
        switch status.state {
        case .charging:
            return "Charging"
        case .discharging:
            return "Battery"
        case .full:
            return "Full"
        case .unknown:
            return "Unknown"
        }
    }

    private var symbolName: String {
        switch status.state {
        case .charging:
            return "battery.100.bolt"
        case .discharging:
            return "battery.75"
        case .full:
            return "battery.100"
        case .unknown:
            return "battery.0"
        }
    }
}
```

- [ ] **Step 3: Add conversation event row**

Create `Sources/CodexPlusApp/Views/ConversationEventRow.swift`:

```swift
import SwiftUI
import CodexPlusCore

struct ConversationEventRow: View {
    let event: ConversationDisplayEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 18)
                .foregroundStyle(iconColor)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var iconName: String {
        switch event {
        case .userPrompt:
            return "person.crop.circle"
        case .status:
            return "circle.dotted"
        case .assistantMessage:
            return "sparkles"
        case .command:
            return "terminal"
        case .error:
            return "exclamationmark.triangle"
        case .parseWarning:
            return "curlybraces"
        }
    }

    private var iconColor: Color {
        switch event {
        case .error:
            return .red
        case .parseWarning:
            return .orange
        case .command:
            return .blue
        default:
            return .secondary
        }
    }

    private var text: String {
        switch event {
        case let .userPrompt(_, text):
            return text
        case let .status(_, text):
            return text
        case let .assistantMessage(_, text):
            return text
        case let .command(_, _, command, status):
            return "\(status.rawValue): \(command)"
        case let .error(_, text):
            return text
        case let .parseWarning(_, text):
            return "Event parsing warning: \(text)"
        }
    }
}
```

- [ ] **Step 4: Add compact entry view**

Create `Sources/CodexPlusApp/Views/CompactEntryView.swift`:

```swift
import SwiftUI
import CodexPlusCore

struct CompactEntryView: View {
    let batteryStatus: BatteryStatus
    let onSubmit: (String) -> Void

    @State private var prompt = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                BatteryTileView(status: batteryStatus)
                Spacer(minLength: 0)
            }

            LiquidGlassContainer(cornerRadius: 20) {
                TextField("Ask Codex", text: $prompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 15)
                    .focused($isInputFocused)
                    .onSubmit(submit)
            }
        }
        .padding(18)
        .background(Color.clear)
        .onAppear {
            isInputFocused = true
        }
    }

    private func submit() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        prompt = ""
        onSubmit(trimmed)
    }
}
```

- [ ] **Step 5: Add conversation view**

Create `Sources/CodexPlusApp/Views/ConversationView.swift`:

```swift
import SwiftUI
import CodexPlusCore

struct ConversationView: View {
    let session: ConversationSession
    let onFollowUp: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onToggleSide: () -> Void
    let onToggleFullAccess: () -> Void

    @State private var followUp = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        LiquidGlassContainer(cornerRadius: 0) {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.25)
                eventList
                Divider().opacity(0.25)
                footer
            }
        }
        .onAppear {
            isInputFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(session.permissionMode.displayName)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(permissionColor.opacity(0.18), in: Capsule())

            Text(session.state.rawValue.capitalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onToggleFullAccess) {
                Image(systemName: "lock.open")
            }
            .help("Toggle Full Access for this conversation")

            Button(action: onToggleSide) {
                Image(systemName: "sidebar.right")
            }
            .help("Switch side")

            Button(action: onTogglePin) {
                Image(systemName: session.isPinned ? "pin.fill" : "pin")
            }
            .help("Pin window")

            Button(action: onStop) {
                Image(systemName: "stop.fill")
            }
            .disabled(session.state != .running)
            .help("Stop Codex task")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Close")
        }
        .buttonStyle(.borderless)
        .padding(14)
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(session.events) { event in
                    ConversationEventRow(event: event)
                }
            }
            .padding(16)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            TextField("Continue with Codex", text: $followUp)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
    }

    private var permissionColor: Color {
        session.permissionMode == .fullAccess ? .orange : .blue
    }

    private func submit() {
        let trimmed = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        followUp = ""
        onFollowUp(trimmed)
    }
}
```

- [ ] **Step 6: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/CodexPlusApp/Views
git commit -m "feat: add liquid glass swiftui views"
```

## Task 8: Wire Views, Codex Runner, Hide, Pin, And Side Switching

**Files:**
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`

- [ ] **Step 1: Replace window coordinator**

Replace `Sources/CodexPlusApp/WindowCoordinator.swift` with:

```swift
import AppKit
import SwiftUI
import CodexPlusCore

@MainActor
final class WindowCoordinator {
    private let conversationCoordinator: ConversationCoordinator
    private let batteryProvider: BatteryStatusProviding
    private let codexRunner: ProcessCodexRunner

    private var compactPanel: GlassPanel?
    private var sidePanel: GlassPanel?
    private var activeRunHandle: CodexRunHandle?
    private var mouseExitMonitor: Any?

    init(
        conversationCoordinator: ConversationCoordinator,
        batteryProvider: BatteryStatusProviding,
        codexRunner: ProcessCodexRunner
    ) {
        self.conversationCoordinator = conversationCoordinator
        self.batteryProvider = batteryProvider
        self.codexRunner = codexRunner
    }

    deinit {
        if let mouseExitMonitor {
            NSEvent.removeMonitor(mouseExitMonitor)
        }
    }

    func handleGlobalShortcut() {
        switch conversationCoordinator.shortcutDecision() {
        case .recallExisting:
            showSidePanel()
        case .openFreshEntry:
            showCompactPanel()
        }
    }

    private func showCompactPanel() {
        sidePanel?.orderOut(nil)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: 420, height: 210)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - screenFrame.height * 0.28 - size.height / 2
        )

        let panel = compactPanel ?? GlassPanel(contentRect: NSRect(origin: origin, size: size))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.contentView = NSHostingView(
            rootView: CompactEntryView(batteryStatus: batteryProvider.currentStatus()) { [weak self] prompt in
                self?.startConversation(prompt: prompt)
            }
        )
        compactPanel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startConversation(prompt: String) {
        let session = conversationCoordinator.startConversation(prompt: prompt)
        compactPanel?.orderOut(nil)
        showSidePanel()
        runCodex(for: session.id, prompt: prompt)
    }

    private func runCodex(for sessionID: UUID, prompt: String) {
        guard let session = conversationCoordinator.activeConversation else {
            return
        }

        conversationCoordinator.markRunning(sessionID)
        refreshSidePanelContent()

        activeRunHandle = codexRunner.run(
            prompt: prompt,
            permissionMode: session.permissionMode,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.conversationCoordinator.appendCodexEvent(event, to: sessionID)
                    self?.refreshSidePanelContent()
                }
            },
            onFinish: { [weak self] result in
                Task { @MainActor in
                    guard let self else {
                        return
                    }
                    self.activeRunHandle = nil
                    if result.succeeded {
                        self.conversationCoordinator.markCompleted(sessionID)
                    } else {
                        self.conversationCoordinator.markFailed(sessionID, message: result.stderr.isEmpty ? "Codex exited with code \(result.exitCode)" : result.stderr)
                    }
                    self.refreshSidePanelContent()
                }
            }
        )
    }

    private func showSidePanel() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let size = NSSize(width: 460, height: screenFrame.height)
        let side = conversationCoordinator.preferredSide
        let x = side == .right ? screenFrame.maxX - size.width : screenFrame.minX
        let origin = NSPoint(x: x, y: screenFrame.minY)

        let panel = sidePanel ?? GlassPanel(contentRect: NSRect(origin: origin, size: size))
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        sidePanel = panel
        refreshSidePanelContent()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installMouseExitMonitor()
    }

    private func refreshSidePanelContent() {
        guard let panel = sidePanel, let session = conversationCoordinator.activeConversation else {
            return
        }

        panel.contentView = NSHostingView(
            rootView: ConversationView(
                session: session,
                onFollowUp: { [weak self] prompt in
                    guard let self, let active = self.conversationCoordinator.activeConversation else {
                        return
                    }
                    self.runCodex(for: active.id, prompt: prompt)
                },
                onStop: { [weak self] in
                    self?.stopActiveRun()
                },
                onClose: { [weak self] in
                    self?.closeSidePanel()
                },
                onTogglePin: { [weak self] in
                    guard let self, let active = self.conversationCoordinator.activeConversation else {
                        return
                    }
                    self.conversationCoordinator.setPinned(!active.isPinned, for: active.id)
                    self.refreshSidePanelContent()
                },
                onToggleSide: { [weak self] in
                    self?.conversationCoordinator.togglePreferredSide()
                    self?.showSidePanel()
                },
                onToggleFullAccess: { [weak self] in
                    guard let self, let active = self.conversationCoordinator.activeConversation else {
                        return
                    }
                    let next: PermissionMode = active.permissionMode == .fullAccess ? .semiAutomatic : .fullAccess
                    self.conversationCoordinator.setPermissionMode(next, for: active.id)
                    self.refreshSidePanelContent()
                }
            )
        )
    }

    private func stopActiveRun() {
        activeRunHandle?.stop()
        activeRunHandle = nil
        if let active = conversationCoordinator.activeConversation {
            conversationCoordinator.markStopped(active.id)
        }
        refreshSidePanelContent()
    }

    private func closeSidePanel() {
        if conversationCoordinator.activeConversation?.state == .running {
            let alert = NSAlert()
            alert.messageText = "Stop the running Codex task?"
            alert.informativeText = "Closing this conversation will stop the active Codex process."
            alert.addButton(withTitle: "Stop and Close")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() != .alertFirstButtonReturn {
                return
            }

            stopActiveRun()
        }
        sidePanel?.orderOut(nil)
    }

    private func installMouseExitMonitor() {
        if let mouseExitMonitor {
            NSEvent.removeMonitor(mouseExitMonitor)
        }

        mouseExitMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.hideSidePanelIfMouseExited()
            }
        }
    }

    private func hideSidePanelIfMouseExited() {
        guard
            let panel = sidePanel,
            panel.isVisible,
            conversationCoordinator.activeConversation?.isPinned != true
        else {
            return
        }

        let frame = panel.frame.insetBy(dx: -12, dy: -12)
        if !frame.contains(NSEvent.mouseLocation) {
            panel.orderOut(nil)
        }
    }
}
```

- [ ] **Step 2: Build**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Run tests**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/CodexPlusApp/WindowCoordinator.swift
git commit -m "feat: wire quick entry conversation flow"
```

## Task 9: Manual Smoke Script And Final Verification Notes

**Files:**
- Create: `docs/superpowers/manual-tests/2026-07-02-codex-plus-smoke.md`

- [ ] **Step 1: Create manual smoke checklist**

Create `docs/superpowers/manual-tests/2026-07-02-codex-plus-smoke.md`:

```markdown
# Codex+ Manual Smoke Test

Date: 2026-07-02

## Build

- Command: `swift build`
- Expected: build succeeds.

## Unit Tests

- Command: `swift test`
- Expected: all tests pass.

## App Launch

- Command: `swift run CodexPlusApp`
- Expected: app launches as an accessory app without opening a dock window.

## Global Shortcut

- Press: Control-Option-Space
- Expected: compact panel appears near the upper third of the active screen.

## Compact Panel

- Expected: panel has exactly two vertical layers.
- Expected: top layer contains one square battery tile.
- Expected: bottom layer contains one focused AI input.
- Expected: empty Enter does not expand.

## Conversation

- Type: `Say hello in one sentence.`
- Press: Enter
- Expected: compact panel hides and side conversation window opens on the right edge.
- Expected: event rows stream or a clear Codex startup error appears.

## Window Behavior

- Move mouse outside side window.
- Expected: side window hides unless pinned.
- Press Control-Option-Space while a task is running or pinned.
- Expected: existing side conversation is recalled.
- Press pin, move mouse outside.
- Expected: side window remains visible.
- Press side switch.
- Expected: window moves to the left edge.

## Stop And Permission Reset

- Start a prompt that runs long enough to stop.
- Press stop.
- Expected: state changes to stopped.
- Switch to Full Access, then stop or complete the run.
- Expected: permission returns to Semi-Automatic.
```

- [ ] **Step 2: Run full verification**

Run:

```bash
swift test
swift build
```

Expected: both commands exit 0.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/manual-tests/2026-07-02-codex-plus-smoke.md
git commit -m "test: document dashboard smoke test"
```

## Final Implementation Verification

After all tasks are implemented:

1. Run:

```bash
swift test
swift build
```

2. Launch:

```bash
swift run CodexPlusApp
```

3. Perform every step in `docs/superpowers/manual-tests/2026-07-02-codex-plus-smoke.md`.
4. Confirm `git status --short` is clean.
5. Report the exact test/build output and any manual smoke gaps.
