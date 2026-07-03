# Codex Usage Rings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Liquid Glass Codex usage tile that shows 5-hour usage as an outer ring and 1-week usage as an inner ring.

**Architecture:** Add a small Core usage domain that reads the latest Codex `token_count.rate_limits` event from local JSONL files, converts it into a display-ready status, and exposes it through a timer-backed monitor matching the existing battery monitor pattern. The App layer renders that status in one double-ring tile beside the battery tile and does no JSON parsing or threshold math.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit host windows, Foundation JSON parsing, existing `CodexPlusCoreTests` executable test harness.

---

## File Structure

- Create `Sources/CodexPlusCore/CodexUsageStatus.swift`
  - Owns `CodexUsageWindow`, `CodexUsageRingColor`, and `CodexUsageStatus`.
  - Keeps percentage clamping and RGB color interpolation deterministic and testable.
- Create `Sources/CodexPlusCore/LocalCodexUsageProvider.swift`
  - Owns `CodexUsageProviding` and `LocalCodexUsageProvider`.
  - Reads local Codex session JSONL files, ignores malformed lines, and returns the newest usable usage event.
- Create `Sources/CodexPlusCore/CodexUsageMonitor.swift`
  - Timer wrapper matching `BatteryStatusMonitor`.
- Create `Sources/CodexPlusApp/Views/CodexUsageRingTileView.swift`
  - SwiftUI-only rendering of the double ring tile.
- Modify `Sources/CodexPlusApp/Views/CompactEntryHostView.swift`
  - Observe `CodexUsageMonitor` and pass usage status to compact entry.
- Modify `Sources/CodexPlusApp/Views/CompactEntryView.swift`
  - Add the Codex usage tile beside the battery tile.
- Modify `Sources/CodexPlusApp/WindowCoordinator.swift`
  - Own, start, and wire the usage monitor using `LocalCodexUsageProvider`.
- Modify `Tests/CodexPlusCoreTests/main.swift`
  - Add focused tests for status color logic, JSONL parsing, newest event selection, malformed lines, unknown status, and monitor refresh.

---

## Task 1: Core Usage Status And Color Bands

**Files:**
- Create: `Sources/CodexPlusCore/CodexUsageStatus.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Write the failing color/status tests**

Add these tests near the battery monitor tests in `Tests/CodexPlusCoreTests/main.swift`:

```swift
let unknownCodexUsage = CodexUsageStatus.unknown
expect(unknownCodexUsage.fiveHourPercent == nil, "unknown codex usage has no five-hour percent")
expect(unknownCodexUsage.weeklyPercent == nil, "unknown codex usage has no weekly percent")
expect(unknownCodexUsage.ringColor(for: .fiveHour) == .inactive, "unknown codex usage uses inactive ring color")

let greenCodexUsage = CodexUsageStatus(fiveHourPercent: 42, weeklyPercent: 12, observedAt: Date(timeIntervalSince1970: 10))
expect(greenCodexUsage.fiveHourPercent == 42, "codex usage stores five-hour percent")
expect(greenCodexUsage.weeklyPercent == 12, "codex usage stores weekly percent")
expect(greenCodexUsage.ringColor(for: .fiveHour) == .lowUsageGreen, "codex usage below sixty percent is green")

let yellowCodexUsage = CodexUsageStatus(fiveHourPercent: 80, weeklyPercent: 75, observedAt: nil)
expect(yellowCodexUsage.ringColor(for: .fiveHour) == .midUsageYellow, "codex usage at eighty percent is yellow")
expect(
    yellowCodexUsage.ringColor(for: .weekly) != .lowUsageGreen,
    "codex usage between sixty and eighty percent interpolates away from green"
)

let redCodexUsage = CodexUsageStatus(fiveHourPercent: 96, weeklyPercent: 100, observedAt: nil)
expect(redCodexUsage.ringColor(for: .fiveHour) != .midUsageYellow, "codex usage above eighty percent interpolates away from yellow")
expect(redCodexUsage.ringColor(for: .weekly) == .highUsageRed, "codex usage at one hundred percent is red")

let clampedCodexUsage = CodexUsageStatus(fiveHourPercent: -5, weeklyPercent: 140, observedAt: nil)
expect(clampedCodexUsage.fiveHourPercent == 0, "codex usage clamps low percent to zero")
expect(clampedCodexUsage.weeklyPercent == 100, "codex usage clamps high percent to one hundred")
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: FAIL because `CodexUsageStatus`, `CodexUsageWindow`, and `CodexUsageRingColor` are not defined.

- [ ] **Step 3: Implement the minimal status model**

Create `Sources/CodexPlusCore/CodexUsageStatus.swift`:

```swift
import Foundation

public enum CodexUsageWindow: Equatable, Sendable {
    case fiveHour
    case weekly
}

public struct CodexUsageRingColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    public static let lowUsageGreen = CodexUsageRingColor(red: 0.20, green: 0.78, blue: 0.35)
    public static let midUsageYellow = CodexUsageRingColor(red: 1.00, green: 0.84, blue: 0.20)
    public static let highUsageRed = CodexUsageRingColor(red: 1.00, green: 0.23, blue: 0.19)
    public static let inactive = CodexUsageRingColor(red: 0.55, green: 0.55, blue: 0.58, opacity: 0.38)
}

public struct CodexUsageStatus: Equatable, Sendable {
    public let fiveHourPercent: Int?
    public let weeklyPercent: Int?
    public let observedAt: Date?

    public init(fiveHourPercent: Int?, weeklyPercent: Int?, observedAt: Date?) {
        self.fiveHourPercent = Self.clamped(fiveHourPercent)
        self.weeklyPercent = Self.clamped(weeklyPercent)
        self.observedAt = observedAt
    }

    public static let unknown = CodexUsageStatus(
        fiveHourPercent: nil,
        weeklyPercent: nil,
        observedAt: nil
    )

    public func percent(for window: CodexUsageWindow) -> Int? {
        switch window {
        case .fiveHour:
            return fiveHourPercent
        case .weekly:
            return weeklyPercent
        }
    }

    public func ringColor(for window: CodexUsageWindow) -> CodexUsageRingColor {
        guard let percent = percent(for: window) else {
            return .inactive
        }

        if percent <= 60 {
            return .lowUsageGreen
        }

        if percent == 80 {
            return .midUsageYellow
        }

        if percent < 80 {
            return Self.interpolate(
                from: .lowUsageGreen,
                to: .midUsageYellow,
                progress: Double(percent - 60) / 20.0
            )
        }

        if percent >= 100 {
            return .highUsageRed
        }

        return Self.interpolate(
            from: .midUsageYellow,
            to: .highUsageRed,
            progress: Double(percent - 80) / 20.0
        )
    }

    private static func clamped(_ percent: Int?) -> Int? {
        guard let percent else {
            return nil
        }

        return max(0, min(100, percent))
    }

    private static func interpolate(
        from start: CodexUsageRingColor,
        to end: CodexUsageRingColor,
        progress: Double
    ) -> CodexUsageRingColor {
        let clampedProgress = max(0, min(1, progress))

        return CodexUsageRingColor(
            red: start.red + ((end.red - start.red) * clampedProgress),
            green: start.green + ((end.green - start.green) * clampedProgress),
            blue: start.blue + ((end.blue - start.blue) * clampedProgress),
            opacity: start.opacity + ((end.opacity - start.opacity) * clampedProgress)
        )
    }
}
```

- [ ] **Step 4: Run the test and verify GREEN**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: PASS with the assertion count increased by 12.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/CodexPlusCore/CodexUsageStatus.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: add codex usage status model"
```

---

## Task 2: Local Codex Usage Provider

**Files:**
- Create: `Sources/CodexPlusCore/LocalCodexUsageProvider.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Add temporary JSONL helpers and failing provider tests**

Add this helper below `makeTemporaryScript` in `Tests/CodexPlusCoreTests/main.swift`:

```swift
@MainActor
func makeTemporaryDirectory(named name: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "codex-plus-\(UUID().uuidString)-\(name)",
        isDirectory: true
    )

    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        expect(false, "temporary directory \(name) can be created")
    }

    return url
}

@MainActor
func writeText(_ text: String, to url: URL) {
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        expect(false, "temporary text file \(url.lastPathComponent) can be written")
    }
}
```

Add these tests after the Task 1 Codex usage status tests:

```swift
let codexUsageSessionsDirectory = makeTemporaryDirectory(named: "codex-usage-sessions")
let codexUsageArchivesDirectory = makeTemporaryDirectory(named: "codex-usage-archives")
defer {
    try? FileManager.default.removeItem(at: codexUsageSessionsDirectory)
    try? FileManager.default.removeItem(at: codexUsageArchivesDirectory)
}

let olderUsageFile = codexUsageArchivesDirectory.appendingPathComponent("older.jsonl")
writeText(
    """
    {"timestamp":"2026-07-03T01:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":30,"window_minutes":300},"secondary":{"used_percent":40,"window_minutes":10080}}}}
    """,
    to: olderUsageFile
)

let newerUsageFile = codexUsageSessionsDirectory.appendingPathComponent("newer.jsonl")
writeText(
    """
    {not json
    {"timestamp":"2026-07-03T02:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":65,"window_minutes":300},"secondary":{"used_percent":55,"window_minutes":10080}}}}
    {"timestamp":"2026-07-03T03:00:00Z","type":"event_msg","payload":{"type":"agent_message","message":"ignored"}}
    """,
    to: newerUsageFile
)

let codexUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [codexUsageSessionsDirectory],
    archiveDirectories: [codexUsageArchivesDirectory]
)
let codexUsageStatus = codexUsageProvider.currentStatus()
expect(codexUsageStatus.fiveHourPercent == 65, "codex usage provider reads newest five-hour percent")
expect(codexUsageStatus.weeklyPercent == 55, "codex usage provider reads newest weekly percent")
expect(
    codexUsageStatus.observedAt == ISO8601DateFormatter().date(from: "2026-07-03T02:00:00Z"),
    "codex usage provider preserves newest usage timestamp"
)

let emptyUsageDirectory = makeTemporaryDirectory(named: "codex-usage-empty")
defer {
    try? FileManager.default.removeItem(at: emptyUsageDirectory)
}
let emptyUsageProvider = LocalCodexUsageProvider(
    sessionDirectories: [emptyUsageDirectory],
    archiveDirectories: []
)
expect(emptyUsageProvider.currentStatus() == .unknown, "codex usage provider returns unknown without usage data")
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: FAIL because `LocalCodexUsageProvider` and `CodexUsageProviding` are not defined.

- [ ] **Step 3: Implement JSONL parsing and newest-event selection**

Create `Sources/CodexPlusCore/LocalCodexUsageProvider.swift`:

```swift
import Foundation

public protocol CodexUsageProviding: Sendable {
    func currentStatus() -> CodexUsageStatus
}

public struct LocalCodexUsageProvider: CodexUsageProviding {
    private let sessionDirectories: [URL]
    private let archiveDirectories: [URL]
    private let fileManager: FileManager
    private let maxFilesToScan: Int

    public init(
        sessionDirectories: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")],
        archiveDirectories: [URL] = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/archived_sessions")],
        fileManager: FileManager = .default,
        maxFilesToScan: Int = 80
    ) {
        self.sessionDirectories = sessionDirectories
        self.archiveDirectories = archiveDirectories
        self.fileManager = fileManager
        self.maxFilesToScan = max(1, maxFilesToScan)
    }

    public func currentStatus() -> CodexUsageStatus {
        let files = candidateFiles()
        var newestStatus = CodexUsageStatus.unknown

        for file in files {
            guard let fileStatus = newestStatus(in: file) else {
                continue
            }

            if shouldReplace(newestStatus, with: fileStatus) {
                newestStatus = fileStatus
            }
        }

        return newestStatus
    }

    private func candidateFiles() -> [URL] {
        let directories = sessionDirectories + archiveDirectories
        var files: [(url: URL, modifiedAt: Date)] = []

        for directory in directories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else {
                    continue
                }

                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true
                else {
                    continue
                }

                files.append((url, values.contentModificationDate ?? .distantPast))
            }
        }

        return files
            .sorted { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }
            .prefix(maxFilesToScan)
            .map(\.url)
    }

    private func newestStatus(in file: URL) -> CodexUsageStatus? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else {
            return nil
        }

        var newestStatus: CodexUsageStatus?
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let status = Self.status(fromJSONLine: String(line)) else {
                continue
            }

            if shouldReplace(newestStatus, with: status) {
                newestStatus = status
            }
        }

        return newestStatus
    }

    private func shouldReplace(_ current: CodexUsageStatus?, with candidate: CodexUsageStatus) -> Bool {
        guard let current else {
            return true
        }

        guard let currentDate = current.observedAt else {
            return true
        }

        guard let candidateDate = candidate.observedAt else {
            return false
        }

        return candidateDate > currentDate
    }

    static func status(fromJSONLine line: String) -> CodexUsageStatus? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any]
        else {
            return nil
        }

        let timestamp = (object["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        let fiveHourPercent = Self.percent(from: rateLimits["primary"], expectedWindowMinutes: 300)
        let weeklyPercent = Self.percent(from: rateLimits["secondary"], expectedWindowMinutes: 10_080)

        guard fiveHourPercent != nil || weeklyPercent != nil else {
            return nil
        }

        return CodexUsageStatus(
            fiveHourPercent: fiveHourPercent,
            weeklyPercent: weeklyPercent,
            observedAt: timestamp
        )
    }

    private static func percent(from value: Any?, expectedWindowMinutes: Int) -> Int? {
        guard let object = value as? [String: Any],
              object["window_minutes"] as? Int == expectedWindowMinutes
        else {
            return nil
        }

        if let integer = object["used_percent"] as? Int {
            return integer
        }

        if let double = object["used_percent"] as? Double {
            return Int(double.rounded())
        }

        return nil
    }
}
```

- [ ] **Step 4: Run the test and verify GREEN**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: PASS with assertion count increased by 4 from Task 2.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/CodexPlusCore/LocalCodexUsageProvider.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: read codex usage from sessions"
```

---

## Task 3: Codex Usage Monitor

**Files:**
- Create: `Sources/CodexPlusCore/CodexUsageMonitor.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Add a sequence provider and failing monitor tests**

Add this test helper near `SequenceBatteryProvider` in `Tests/CodexPlusCoreTests/main.swift`:

```swift
final class SequenceCodexUsageProvider: CodexUsageProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [CodexUsageStatus]

    init(_ statuses: [CodexUsageStatus]) {
        self.statuses = statuses
    }

    func currentStatus() -> CodexUsageStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        guard !statuses.isEmpty else {
            return .unknown
        }

        return statuses.removeFirst()
    }
}
```

Add these tests after the battery monitor tests:

```swift
let codexUsageMonitorProvider = SequenceCodexUsageProvider([
    CodexUsageStatus(fiveHourPercent: 11, weeklyPercent: 22, observedAt: nil),
    CodexUsageStatus(fiveHourPercent: 33, weeklyPercent: 44, observedAt: nil)
])
let codexUsageMonitor = CodexUsageMonitor(provider: codexUsageMonitorProvider)
expect(codexUsageMonitor.status == .unknown, "codex usage monitor starts unknown before refresh")
codexUsageMonitor.refresh()
expect(
    codexUsageMonitor.status == CodexUsageStatus(fiveHourPercent: 11, weeklyPercent: 22, observedAt: nil),
    "codex usage monitor refresh reads provider status"
)
codexUsageMonitor.refresh()
expect(
    codexUsageMonitor.status == CodexUsageStatus(fiveHourPercent: 33, weeklyPercent: 44, observedAt: nil),
    "codex usage monitor refresh updates status from provider"
)
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: FAIL because `CodexUsageMonitor` is not defined.

- [ ] **Step 3: Implement the monitor**

Create `Sources/CodexPlusCore/CodexUsageMonitor.swift`:

```swift
import Combine
import Foundation

@MainActor
public final class CodexUsageMonitor: ObservableObject {
    @Published public private(set) var status: CodexUsageStatus

    private let provider: any CodexUsageProviding
    private let interval: TimeInterval
    private var timer: Timer?

    public init(
        provider: any CodexUsageProviding,
        initialStatus: CodexUsageStatus = .unknown,
        interval: TimeInterval = 60
    ) {
        self.provider = provider
        self.status = initialStatus
        self.interval = interval
    }

    deinit {
        MainActor.assumeIsolated {
            timer?.invalidate()
        }
    }

    public func start() {
        refresh()

        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        status = provider.currentStatus()
    }
}
```

- [ ] **Step 4: Run the test and verify GREEN**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: PASS with assertion count increased by 3 from Task 3.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/CodexPlusCore/CodexUsageMonitor.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "feat: monitor codex usage status"
```

---

## Task 4: Double-Ring Usage Tile UI

**Files:**
- Create: `Sources/CodexPlusApp/Views/CodexUsageRingTileView.swift`
- Modify: `Sources/CodexPlusApp/Views/CompactEntryView.swift`
- Modify: `Sources/CodexPlusApp/Views/CompactEntryHostView.swift`

- [ ] **Step 1: Create the SwiftUI ring tile**

Create `Sources/CodexPlusApp/Views/CodexUsageRingTileView.swift`:

```swift
import CodexPlusCore
import SwiftUI

struct CodexUsageRingTileView: View {
    let status: CodexUsageStatus

    var body: some View {
        LiquidGlassContainer(cornerRadius: 22) {
            ZStack {
                UsageRing(
                    percent: status.fiveHourPercent,
                    color: color(for: .fiveHour),
                    lineWidth: 7,
                    diameter: 72
                )

                UsageRing(
                    percent: status.weeklyPercent,
                    color: color(for: .weekly),
                    lineWidth: 5,
                    diameter: 52
                )

                VStack(spacing: 1) {
                    Text("5H \(percentText(status.fiveHourPercent))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("1W \(percentText(status.weeklyPercent))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(labelText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 54)
            }
            .frame(width: 92, height: 92)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var labelText: String {
        if status.fiveHourPercent == nil && status.weeklyPercent == nil {
            return "No Data"
        }

        return "Codex"
    }

    private var accessibilityText: String {
        "Codex usage, five hours \(percentText(status.fiveHourPercent)), one week \(percentText(status.weeklyPercent))"
    }

    private func percentText(_ percent: Int?) -> String {
        guard let percent else {
            return "--%"
        }

        return "\(percent)%"
    }

    private func color(for window: CodexUsageWindow) -> Color {
        let ringColor = status.ringColor(for: window)

        return Color(
            red: ringColor.red,
            green: ringColor.green,
            blue: ringColor.blue,
            opacity: ringColor.opacity
        )
    }
}

private struct UsageRing: View {
    let percent: Int?
    let color: Color
    let lineWidth: CGFloat
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private var progress: CGFloat {
        guard let percent else {
            return 0
        }

        return CGFloat(max(0, min(100, percent))) / 100
    }
}
```

- [ ] **Step 2: Thread usage status through compact entry views**

Update `Sources/CodexPlusApp/Views/CompactEntryHostView.swift` to:

```swift
import CodexPlusCore
import SwiftUI

struct CompactEntryHostView: View {
    @ObservedObject var batteryMonitor: BatteryStatusMonitor
    @ObservedObject var codexUsageMonitor: CodexUsageMonitor
    let onSubmit: (String) -> Void

    var body: some View {
        CompactEntryView(
            batteryStatus: batteryMonitor.status,
            codexUsageStatus: codexUsageMonitor.status,
            onSubmit: onSubmit
        )
    }
}
```

Update the top of `Sources/CodexPlusApp/Views/CompactEntryView.swift` to include the new status:

```swift
struct CompactEntryView: View {
    let batteryStatus: BatteryStatus
    let codexUsageStatus: CodexUsageStatus
    let onSubmit: (String) -> Void
```

Update the top dashboard row in `CompactEntryView` to:

```swift
HStack(spacing: 12) {
    BatteryTileView(status: batteryStatus)
    CodexUsageRingTileView(status: codexUsageStatus)
}
.frame(maxWidth: .infinity)
```

- [ ] **Step 3: Build and verify RED if wiring is incomplete**

Run:

```bash
swift build
```

Expected before Task 5 wiring: FAIL at `WindowCoordinator` because `CompactEntryHostView` now requires `codexUsageMonitor`.

- [ ] **Step 4: Do not commit yet**

Task 4 intentionally leaves App wiring incomplete so Task 5 can own the coordinator changes. Keep these changes unstaged until Task 5 passes build.

---

## Task 5: Wire Usage Monitor Into Window Coordinator

**Files:**
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`
- Uses existing changes from Task 4.

- [ ] **Step 1: Add monitor ownership**

In `Sources/CodexPlusApp/WindowCoordinator.swift`, add this property beside `batteryMonitor`:

```swift
private let codexUsageMonitor: CodexUsageMonitor
```

In `init(...)`, after `self.batteryMonitor = BatteryStatusMonitor(provider: batteryProvider)`, add:

```swift
self.codexUsageMonitor = CodexUsageMonitor(provider: LocalCodexUsageProvider())
```

- [ ] **Step 2: Start the monitor with the compact panel**

In `showCompactPanel()`, add this immediately after `batteryMonitor.start()`:

```swift
codexUsageMonitor.start()
```

- [ ] **Step 3: Pass the monitor into the host view**

In `showCompactPanel()`, update the `CompactEntryHostView` call to:

```swift
rootView: CompactEntryHostView(
    batteryMonitor: batteryMonitor,
    codexUsageMonitor: codexUsageMonitor,
    onSubmit: { [weak self] prompt in
        Task { @MainActor in
            self?.startConversation(prompt: prompt)
        }
    }
)
```

- [ ] **Step 4: Run build and verify GREEN**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 5: Run core tests**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: PASS with all assertions passing.

- [ ] **Step 6: Commit Tasks 4 and 5 together**

```bash
git add Sources/CodexPlusApp/Views/CodexUsageRingTileView.swift Sources/CodexPlusApp/Views/CompactEntryHostView.swift Sources/CodexPlusApp/Views/CompactEntryView.swift Sources/CodexPlusApp/WindowCoordinator.swift
git commit -m "feat: show codex usage rings"
```

---

## Task 6: Final Verification And Cleanup

**Files:**
- Inspect all changed files.
- No planned source changes unless verification reveals a problem.

- [ ] **Step 1: Run full verification commands**

Run:

```bash
swift run CodexPlusCoreTests
swift build
git diff --check
```

Expected:

- `CodexPlusCoreTests` passes.
- `swift build` exits 0.
- `git diff --check` prints no whitespace errors.

- [ ] **Step 2: Inspect git state**

Run:

```bash
git status --short
git log --oneline -5
```

Expected:

- No unstaged source changes remain.
- Recent commits include the usage status, provider, monitor, and UI wiring commits.

- [ ] **Step 3: Manual smoke test**

Run the app in the usual local way:

```bash
swift run CodexPlusApp
```

Expected:

- Compact entry opens with battery tile and Codex usage tile side by side.
- Outer 5H ring and inner 1W ring render.
- Percent text shows values from the latest local Codex usage event, or `--%` / `No Data` when no event is readable.
- Text fits inside the 92x92 tile.

If running the GUI app is blocked by sandboxing, request approval for the app run. If approval is not available, report that automated build/test verification passed and GUI smoke testing was not run.

---

## Self-Review

- Spec coverage: The plan reads local Codex JSONL usage events, uses primary 300-minute and secondary 10080-minute windows, renders one Liquid Glass double-ring tile, handles missing data, ignores malformed lines, refreshes on a 60-second monitor, and keeps parsing in Core.
- Placeholder scan: No unfinished implementation markers or unspecified steps remain.
- Type consistency: The plan consistently uses `CodexUsageStatus`, `CodexUsageWindow`, `CodexUsageRingColor`, `CodexUsageProviding`, `LocalCodexUsageProvider`, `CodexUsageMonitor`, and `CodexUsageRingTileView`.
