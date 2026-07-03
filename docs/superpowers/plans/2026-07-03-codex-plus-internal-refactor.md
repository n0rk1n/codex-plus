# Codex+ Internal Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Codex+ as a local Mac app with a smaller SwiftPM product surface, a cleaner internal Core target, and thinner AppKit coordination code without changing user-visible behavior.

**Architecture:** Keep `CodexPlusCore` as an internal pure-logic target and keep `CodexPlusApp` as the only shipped product. Move platform integration and AppKit window mechanics into app-owned files, while leaving conversation run orchestration in `WindowCoordinator`. Use small, compile-checked refactors with existing core harness coverage and release build verification after each risky boundary change.

**Tech Stack:** Swift 6, SwiftPM, Foundation, CoreGraphics, Combine, AppKit, SwiftUI, Carbon, IOKit.

---

## File Structure

- Modify: `Package.swift`
  - Expose only the `CodexPlusApp` product.
  - Keep `CodexPlusCore` and `CodexPlusCoreTests` as targets.
  - Move IOKit linking from Core to App.
- Modify: `Sources/CodexPlusCore/BatteryStatus.swift`
  - Keep `BatteryStatus`, `BatteryChargingState`, and `BatteryStatusProviding`.
  - Remove IOKit imports and `IOKitBatteryStatusProvider`.
- Create: `Sources/CodexPlusApp/IOKitBatteryStatusProvider.swift`
  - Own App-side IOKit battery integration.
- Modify: `Sources/CodexPlusCore/CompactEntryDismissPolicy.swift`
  - Replace `ScreenPoint` and `ScreenRect` with `CGPoint` and `CGRect`.
- Modify: `Sources/CodexPlusCore/CompactPanelSnapPolicy.swift`
  - Use `CGRect` for snap policy inputs and output.
- Modify: `Sources/CodexPlusCore/CompactDashboardTileDragPolicy.swift`
  - Use `CGPoint` and `CGRect` for drag policy inputs and output.
- Modify: `Sources/CodexPlusCore/ConversationPanelLayoutPolicy.swift`
  - Use `CGRect` for initial panel frame calculation.
- Modify: `Sources/CodexPlusCore/ProcessCodexRunner.swift`
  - Remove the one-implementation `CodexRunHandle` protocol.
  - Return `ProcessCodexRunHandle` directly.
- Modify: `Sources/CodexPlusCore/CodexRunController.swift`
  - Store `ProcessCodexRunHandle?` directly.
- Delete: `Sources/CodexPlusCore/LineBuffer.swift`
  - Remove unused production type and its direct tests.
- Modify: `Sources/CodexPlusCore/LocalCodexUsageProvider.swift`
  - Reuse locked ISO8601 timestamp formatters.
- Create: `Sources/CodexPlusApp/PanelFactory.swift`
  - Centralize `GlassPanel` creation and delegate assignment.
- Create: `Sources/CodexPlusApp/ActiveScreenProvider.swift`
  - Centralize active screen lookup.
- Create: `Sources/CodexPlusApp/CompactPanelController.swift`
  - Own compact panel lifecycle, stored frame, battery monitor lifetime, and compact dismiss monitors.
- Create: `Sources/CodexPlusApp/SidePanelController.swift`
  - Own side panel lifecycle, edge affordance, mouse-exit monitors, custom frame, and hosted conversation model.
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`
  - Keep global shortcut, conversation run flow, permissions, pin, and side toggles.
  - Delegate panel mechanics to the new controllers.
- Modify: `Sources/CodexPlusApp/DraggableHostingView.swift`
  - Remove App-specific `ScreenRect` conversion helpers.
  - Pass native geometry to Core policies.
- Modify: `Tests/CodexPlusCoreTests/main.swift`
  - Update package boundary assertions.
  - Update geometry tests to native types.
  - Remove direct `LineBuffer` assertions.
  - Add compile coverage for concrete `ProcessCodexRunHandle`.

SwiftPM note: `Package.swift` should declare only `CodexPlusApp` in its explicit `products` array. SwiftPM still synthesizes a runnable product for root executable targets, so keep using `swift run CodexPlusCoreTests` as the internal test command. Use `swift package dump-package` when verifying explicit manifest products; `swift package describe` includes synthesized runnable products.

---

### Task 1: SwiftPM Product Boundary and IOKit Ownership

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/CodexPlusCore/BatteryStatus.swift`
- Create: `Sources/CodexPlusApp/IOKitBatteryStatusProvider.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Write the failing package-boundary tests**

Replace the body of `expectCodexPlusNaming()` in `Tests/CodexPlusCoreTests/main.swift` with this body:

```swift
@MainActor
func expectCodexPlusNaming() {
    let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let expectedPaths = [
        "Sources/CodexPlusCore",
        "Sources/CodexPlusApp",
        "Tests/CodexPlusCoreTests"
    ]

    for expectedPath in expectedPaths {
        let exists = FileManager.default.fileExists(
            atPath: packageRoot.appendingPathComponent(expectedPath).path
        )
        expect(exists, "Codex+ project path exists: \(expectedPath)")
    }

    let packageText = (try? String(contentsOf: packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)) ?? ""
    expect(packageText.contains(#"name: "codex-plus""#), "Swift package uses codex-plus slug name")
    expect(packageText.contains(#".executable(name: "CodexPlusApp""#), "Swift package exposes CodexPlusApp executable product")
    expect(!packageText.contains(#".library(name: "CodexPlusCore""#), "Swift package does not expose CodexPlusCore as a library product")
    expect(!packageText.contains(#".executable(name: "CodexPlusCoreTests""#), "Swift package does not expose CodexPlusCoreTests as a product")

    let coreBatteryText = (try? String(
        contentsOf: packageRoot.appendingPathComponent("Sources/CodexPlusCore/BatteryStatus.swift"),
        encoding: .utf8
    )) ?? ""
    expect(!coreBatteryText.contains("IOKit"), "CodexPlusCore battery model does not import IOKit")

    let appBatteryProviderExists = FileManager.default.fileExists(
        atPath: packageRoot.appendingPathComponent("Sources/CodexPlusApp/IOKitBatteryStatusProvider.swift").path
    )
    expect(appBatteryProviderExists, "CodexPlusApp owns the IOKit battery provider")

    let legacyFragments = [
        "Quick" + "AIDashboard",
        "Quick" + " AI " + "Dashboard",
        "quick" + "-ai-" + "dashboard"
    ]
    let filesToScan = [
        packageRoot.appendingPathComponent("Package.swift"),
        packageRoot.appendingPathComponent("Sources/CodexPlusCore/CodexUsageMonitor.swift"),
        packageRoot.appendingPathComponent("Sources/CodexPlusApp/AppDelegate.swift")
    ]

    for fileURL in filesToScan {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        for fragment in legacyFragments {
            expect(!text.contains(fragment), "legacy project name '\(fragment)' is removed from \(fileURL.lastPathComponent)")
        }
    }
}
```

- [ ] **Step 2: Run the test harness and verify the new checks fail**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: the command exits nonzero. The output includes failures for exposed `CodexPlusCore` or `CodexPlusCoreTests` products, Core importing IOKit, and the missing App-owned IOKit provider file.

- [ ] **Step 3: Replace `Package.swift`**

Replace the full contents of `Package.swift` with:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "codex-plus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexPlusApp", targets: ["CodexPlusApp"])
    ],
    targets: [
        .target(
            name: "CodexPlusCore"
        ),
        .executableTarget(
            name: "CodexPlusApp",
            dependencies: ["CodexPlusCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "CodexPlusCoreTests",
            dependencies: ["CodexPlusCore"],
            path: "Tests/CodexPlusCoreTests"
        )
    ]
)
```

- [ ] **Step 4: Move the IOKit provider to the App target**

Replace the full contents of `Sources/CodexPlusCore/BatteryStatus.swift` with:

```swift
import Foundation

public enum BatteryChargingState: String, Equatable, Sendable {
    case charging
    case discharging
    case full
    case pluggedIn
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
        guard let currentCapacity, let maxCapacity, maxCapacity > 0 else {
            return .unknown
        }

        let rawPercentage = (Double(currentCapacity) / Double(maxCapacity)) * 100.0
        let percentage = max(0, min(100, Int(rawPercentage)))

        if percentage >= 100 {
            return BatteryStatus(percentage: percentage, state: .full)
        }

        if isCharging == true {
            return BatteryStatus(percentage: percentage, state: .charging)
        }

        if powerSourceState == "Battery Power" {
            return BatteryStatus(percentage: percentage, state: .discharging)
        }

        if powerSourceState == "AC Power" {
            return BatteryStatus(percentage: percentage, state: .pluggedIn)
        }

        return BatteryStatus(percentage: percentage, state: .unknown)
    }
}

public protocol BatteryStatusProviding: Sendable {
    func currentStatus() -> BatteryStatus
}
```

Create `Sources/CodexPlusApp/IOKitBatteryStatusProvider.swift`:

```swift
import CodexPlusCore
import Foundation
import IOKit.ps

struct IOKitBatteryStatusProvider: BatteryStatusProviding {
    func currentStatus() -> BatteryStatus {
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

- [ ] **Step 5: Run the internal test executable target**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: the build succeeds and the test executable prints `CodexPlusCoreTests passed:` with a passing assertion count.

- [ ] **Step 6: Verify Core no longer links IOKit through the manifest**

Run:

```bash
swift package dump-package
```

Expected: `CodexPlusCore` has no `linkerSettings` entry for `IOKit`. `CodexPlusApp` is the only explicit product in the `products` array.

- [ ] **Step 7: Commit package boundary changes**

Run:

```bash
git add Package.swift Sources/CodexPlusCore/BatteryStatus.swift Sources/CodexPlusApp/IOKitBatteryStatusProvider.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "refactor: make Core an internal target"
```

---

### Task 2: Replace Custom Geometry Types With CoreGraphics

**Files:**
- Modify: `Sources/CodexPlusCore/CompactEntryDismissPolicy.swift`
- Modify: `Sources/CodexPlusCore/CompactPanelSnapPolicy.swift`
- Modify: `Sources/CodexPlusCore/CompactDashboardTileDragPolicy.swift`
- Modify: `Sources/CodexPlusCore/ConversationPanelLayoutPolicy.swift`
- Modify: `Sources/CodexPlusApp/DraggableHostingView.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Update tests to use native geometry**

In `Tests/CodexPlusCoreTests/main.swift`, add this import after `import Foundation`:

```swift
import CoreGraphics
```

Replace every `ScreenRect(` call with `CGRect(` and every `ScreenPoint(` call with `CGPoint(`.

The compact panel test section should read like this after replacement:

```swift
let compactEntryBounds = CGRect(x: 0, y: 0, width: 420, height: 210)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 110, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact battery tile blocks window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 290, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact codex usage tile blocks window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 50, y: 64),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact dashboard row outside the cards blocks window dragging"
)
expect(
    CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 210, y: 152),
        panelBounds: compactEntryBounds,
        verticalOrigin: .top
    ),
    "compact prompt area allows window dragging"
)
expect(
    !CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 110, y: 146),
        panelBounds: compactEntryBounds,
        verticalOrigin: .bottom
    ),
    "compact tile drag policy supports bottom-left AppKit coordinates"
)
expect(
    CompactDashboardTileDragPolicy.shouldMoveWindowFromMouseDown(
        at: CGPoint(x: 210, y: 50),
        panelBounds: compactEntryBounds,
        verticalOrigin: .bottom
    ),
    "compact prompt drag policy supports bottom-left AppKit coordinates"
)
```

- [ ] **Step 2: Run tests and verify geometry API mismatch fails**

Run:

```bash
swift build --target CodexPlusCoreTests
```

Expected: the build fails with type mismatch errors because Core policies still expect `ScreenPoint` and `ScreenRect`.

- [ ] **Step 3: Replace compact dismiss and placement policy**

Replace `Sources/CodexPlusCore/CompactEntryDismissPolicy.swift` with:

```swift
import CoreGraphics

public enum CompactEntryDismissPolicy {
    public static let escapeKeyCode: UInt16 = 53

    public static func shouldDismissForKeyDown(keyCode: UInt16) -> Bool {
        keyCode == escapeKeyCode
    }

    public static func shouldDismissForMouseDown(at point: CGPoint, panelFrame: CGRect) -> Bool {
        !contains(point, in: panelFrame)
    }

    private static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        point.x >= rect.minX &&
            point.x <= rect.maxX &&
            point.y >= rect.minY &&
            point.y <= rect.maxY
    }
}

public enum PanelPlacement: Equatable, Sendable {
    case attached(SideAttachment)
    case free
}

public enum PanelPlacementPolicy {
    public static let defaultSnapDistance = 36.0

    public static func placement(
        for panelFrame: CGRect,
        in screenFrame: CGRect,
        snapDistance: Double = defaultSnapDistance
    ) -> PanelPlacement {
        if abs(panelFrame.minX - screenFrame.minX) <= snapDistance {
            return .attached(.left)
        }

        if abs(screenFrame.maxX - panelFrame.maxX) <= snapDistance {
            return .attached(.right)
        }

        return .free
    }
}
```

- [ ] **Step 4: Replace compact snap policy**

Replace `Sources/CodexPlusCore/CompactPanelSnapPolicy.swift` with:

```swift
import CoreGraphics

public enum CompactPanelSnapPolicy {
    public static let defaultSnapDistance = 24.0

    public static func snappedFrame(
        for panelFrame: CGRect,
        in screenFrame: CGRect,
        snapDistance: Double = defaultSnapDistance
    ) -> CGRect {
        let screenMidX = screenFrame.midX
        let panelMidX = panelFrame.midX

        guard abs(panelMidX - screenMidX) <= snapDistance else {
            return panelFrame
        }

        return CGRect(
            x: screenMidX - (panelFrame.width / 2),
            y: panelFrame.minY,
            width: panelFrame.width,
            height: panelFrame.height
        )
    }
}
```

- [ ] **Step 5: Replace dashboard drag policy**

Replace `Sources/CodexPlusCore/CompactDashboardTileDragPolicy.swift` with:

```swift
import CoreGraphics

public enum PanelCoordinateOrigin: Sendable {
    case top
    case bottom
}

public enum CompactDashboardTileDragPolicy {
    public static let horizontalPadding = 18.0
    public static let topPadding = 18.0
    public static let bottomPadding = 18.0
    public static let verticalSpacing = 14.0
    public static let tileStripHeight = 92.0
    public static let batteryTileWidth = 92.0
    public static let codexUsageTileWidth = 138.0
    public static let tileSpacing = 12.0
    public static let tileStripWidth = batteryTileWidth + codexUsageTileWidth + tileSpacing

    public static func shouldMoveWindowFromMouseDown(
        at point: CGPoint,
        panelBounds: CGRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> Bool {
        promptDragRect(in: panelBounds, verticalOrigin: verticalOrigin).contains(point)
    }

    public static func tileStripRect(
        in panelBounds: CGRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> CGRect {
        let contentWidth = max(0, panelBounds.width - (horizontalPadding * 2))
        let stripWidth = min(tileStripWidth, contentWidth)
        let stripHeight = min(tileStripHeight, max(0, panelBounds.height - topPadding))
        let x = panelBounds.minX + horizontalPadding + max(0, (contentWidth - stripWidth) / 2)

        let y: Double
        switch verticalOrigin {
        case .top:
            y = panelBounds.minY + topPadding
        case .bottom:
            y = panelBounds.minY + panelBounds.height - topPadding - stripHeight
        }

        return CGRect(x: x, y: y, width: stripWidth, height: stripHeight)
    }

    public static func promptDragRect(
        in panelBounds: CGRect,
        verticalOrigin: PanelCoordinateOrigin
    ) -> CGRect {
        let yFromTop = topPadding + tileStripHeight + verticalSpacing
        let height = max(0, panelBounds.height - yFromTop - bottomPadding)

        let y: Double
        switch verticalOrigin {
        case .top:
            y = panelBounds.minY + yFromTop
        case .bottom:
            y = panelBounds.minY + bottomPadding
        }

        return CGRect(
            x: panelBounds.minX + horizontalPadding,
            y: y,
            width: max(0, panelBounds.width - (horizontalPadding * 2)),
            height: height
        )
    }
}
```

- [ ] **Step 6: Replace conversation panel layout policy**

Replace `Sources/CodexPlusCore/ConversationPanelLayoutPolicy.swift` with:

```swift
import CoreGraphics

public enum ConversationPanelLayoutPolicy {
    public static let preferredWidthRatio = 0.56
    public static let preferredHeightRatio = 0.82
    public static let minWidth = 520.0
    public static let maxWidth = 860.0
    public static let minHeight = 560.0
    public static let maxHeight = 920.0
    public static let minimumMargin = 24.0

    public static func initialCenteredFrame(in screenFrame: CGRect) -> CGRect {
        let availableWidth = max(0, screenFrame.width - (minimumMargin * 2))
        let availableHeight = max(0, screenFrame.height - (minimumMargin * 2))
        let width = min(availableWidth, clamped(screenFrame.width * preferredWidthRatio, minWidth, maxWidth)).rounded()
        let height = min(availableHeight, clamped(screenFrame.height * preferredHeightRatio, minHeight, maxHeight)).rounded()

        return CGRect(
            x: (screenFrame.minX + ((screenFrame.width - width) / 2)).rounded(),
            y: (screenFrame.minY + ((screenFrame.height - height) / 2)).rounded(),
            width: width,
            height: height
        )
    }

    private static func clamped(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}
```

- [ ] **Step 7: Update App geometry call sites**

In `Sources/CodexPlusApp/DraggableHostingView.swift`, replace `localPoint(from:)` and `currentLocalBounds()` with:

```swift
private func localPoint(from event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
}

private func currentLocalBounds() -> CGRect {
    bounds
}
```

In the same file, replace the snap call in `compactPromptDragResult(for:window:)` with:

```swift
let snappedFrame = CompactPanelSnapPolicy.snappedFrame(
    for: proposedFrame,
    in: screenFrame
)
let frame = NSRect(snappedFrame)
return (frame, abs(frame.midX - screenFrame.midX) < 0.5)
```

Delete these private extensions from the bottom of `DraggableHostingView.swift`:

```swift
private extension ScreenRect {
    init(_ rect: NSRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }
}

private extension NSRect {
    init(_ rect: ScreenRect) {
        self.init(
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        )
    }
}
```

In `Sources/CodexPlusApp/WindowCoordinator.swift`, replace `prepareCenteredSidePanelFrame()` with:

```swift
private func prepareCenteredSidePanelFrame() {
    guard let screen = activeScreen() else {
        sidePanelCustomFrame = nil
        return
    }

    sidePanelCustomFrame = ConversationPanelLayoutPolicy.initialCenteredFrame(
        in: screen.visibleFrame
    )
}
```

In `dismissCompactPanelIfNeededForMouseDown(at:)`, replace the policy call with:

```swift
let shouldDismiss = CompactEntryDismissPolicy.shouldDismissForMouseDown(
    at: point,
    panelFrame: compactPanel.frame
)
```

In `updateSidePanelPlacement(afterMoving:)`, replace the placement call with:

```swift
switch PanelPlacementPolicy.placement(
    for: panel.frame,
    in: screen.visibleFrame
) {
case let .attached(side):
    sidePanelCustomFrame = nil
    setPreferredSide(side)
case .free:
    sidePanelCustomFrame = panel.frame
}
```

Delete `screenRect(from:)` and `nsRect(from:)` from `WindowCoordinator.swift`.

- [ ] **Step 8: Run tests and release build**

Run:

```bash
swift run CodexPlusCoreTests
swift build -c release
```

Expected: the test executable passes and the release app builds.

- [ ] **Step 9: Commit geometry refactor**

Run:

```bash
git add Sources/CodexPlusCore/CompactEntryDismissPolicy.swift Sources/CodexPlusCore/CompactPanelSnapPolicy.swift Sources/CodexPlusCore/CompactDashboardTileDragPolicy.swift Sources/CodexPlusCore/ConversationPanelLayoutPolicy.swift Sources/CodexPlusApp/DraggableHostingView.swift Sources/CodexPlusApp/WindowCoordinator.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "refactor: use native geometry types"
```

---

### Task 3: Remove Unused LineBuffer and Single-Implementation Run Handle Protocol

**Files:**
- Delete: `Sources/CodexPlusCore/LineBuffer.swift`
- Modify: `Sources/CodexPlusCore/ProcessCodexRunner.swift`
- Modify: `Sources/CodexPlusCore/CodexRunController.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Add compile coverage for concrete process handles**

In `Tests/CodexPlusCoreTests/main.swift`, change the start-failure handle declaration to:

```swift
let startFailureHandle: ProcessCodexRunHandle = startFailureRunner.run(
    prompt: "ignored",
    permissionMode: .semiAutomatic,
    onEvent: { event in
        startFailureCapture.appendEvent(event)
    },
    onFinish: { result in
        startFailureCapture.appendResult(result)
        startFailureFinish.signal()
    }
)
```

- [ ] **Step 2: Run the target build and verify the compile failure**

Run:

```bash
swift build --target CodexPlusCoreTests
```

Expected: the build fails because `ProcessCodexRunner.run` still returns `any CodexRunHandle`.

- [ ] **Step 3: Remove the protocol and return the concrete handle**

In `Sources/CodexPlusCore/ProcessCodexRunner.swift`, delete:

```swift
public protocol CodexRunHandle: Sendable {
    func stop()
}
```

Change the handle type declaration to:

```swift
public final class ProcessCodexRunHandle: Sendable {
    private let process: LockedProcess

    public init(process: Process) {
        self.process = LockedProcess(process)
    }

    public func stop() {
        process.terminateIfRunning()
    }
}
```

Change the `run` return type to:

```swift
) -> ProcessCodexRunHandle {
```

In `Sources/CodexPlusCore/CodexRunController.swift`, change the stored handle to:

```swift
private var activeRunHandle: ProcessCodexRunHandle?
```

- [ ] **Step 4: Remove unused LineBuffer tests and file**

Delete the `LineBuffer` assertion block from `Tests/CodexPlusCoreTests/main.swift`:

```swift
var splitLineBuffer = LineBuffer()
expect(splitLineBuffer.append("one\ntw") == ["one"], "line buffer returns complete first line")
expect(splitLineBuffer.append("o\nthree\n") == ["two", "three"], "line buffer completes partial and next line")
expect(splitLineBuffer.flush() == nil, "line buffer flush returns nil when empty")

var partialLineBuffer = LineBuffer()
expect(partialLineBuffer.append("partial").isEmpty, "line buffer keeps trailing partial line")
expect(partialLineBuffer.flush() == "partial", "line buffer flush returns partial line")
expect(partialLineBuffer.flush() == nil, "line buffer flush clears partial line")
```

Delete `Sources/CodexPlusCore/LineBuffer.swift`.

- [ ] **Step 5: Verify no LineBuffer references remain**

Run:

```bash
rg 'LineBuffer|CodexRunHandle' Sources Tests
```

Expected: no matches.

- [ ] **Step 6: Run tests**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: the test executable passes.

- [ ] **Step 7: Commit the shrink**

Run:

```bash
git add Sources/CodexPlusCore/ProcessCodexRunner.swift Sources/CodexPlusCore/CodexRunController.swift Tests/CodexPlusCoreTests/main.swift
git add -u Sources/CodexPlusCore/LineBuffer.swift
git commit -m "refactor: remove unused Core abstractions"
```

---

### Task 4: Add PanelFactory and ActiveScreenProvider

**Files:**
- Create: `Sources/CodexPlusApp/PanelFactory.swift`
- Create: `Sources/CodexPlusApp/ActiveScreenProvider.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`

- [ ] **Step 1: Create `PanelFactory`**

Create `Sources/CodexPlusApp/PanelFactory.swift`:

```swift
import AppKit

@MainActor
struct PanelFactory {
    func makePanel(frame: NSRect, delegate: NSWindowDelegate?) -> GlassPanel {
        let panel = GlassPanel(contentRect: frame)
        panel.acceptsMouseMovedEvents = true
        panel.delegate = delegate
        return panel
    }
}
```

- [ ] **Step 2: Create `ActiveScreenProvider`**

Create `Sources/CodexPlusApp/ActiveScreenProvider.swift`:

```swift
import AppKit

@MainActor
struct ActiveScreenProvider {
    func activeScreen() -> NSScreen? {
        if let screen = NSApp.keyWindow?.screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
```

- [ ] **Step 3: Wire helpers into `WindowCoordinator`**

Add these properties near the top of `WindowCoordinator`:

```swift
private let panelFactory = PanelFactory()
private let screenProvider = ActiveScreenProvider()
```

Replace `makePanel(frame:)` with:

```swift
private func makePanel(frame: NSRect) -> GlassPanel {
    panelFactory.makePanel(frame: frame, delegate: self)
}
```

Replace `activeScreen()` with:

```swift
private func activeScreen() -> NSScreen? {
    screenProvider.activeScreen()
}
```

- [ ] **Step 4: Run app build**

Run:

```bash
swift build -c release
```

Expected: release build succeeds with no behavior changes.

- [ ] **Step 5: Commit panel helper extraction**

Run:

```bash
git add Sources/CodexPlusApp/PanelFactory.swift Sources/CodexPlusApp/ActiveScreenProvider.swift Sources/CodexPlusApp/WindowCoordinator.swift
git commit -m "refactor: extract AppKit window helpers"
```

---

### Task 5: Extract CompactPanelController

**Files:**
- Create: `Sources/CodexPlusApp/CompactPanelController.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`

- [ ] **Step 1: Create `CompactPanelController`**

Create `Sources/CodexPlusApp/CompactPanelController.swift`:

```swift
import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class CompactPanelController {
    private let panelFactory: PanelFactory
    private let screenProvider: ActiveScreenProvider
    private let batteryMonitor: BatteryStatusMonitor
    private let codexUsageMonitor: CodexUsageMonitor
    private weak var panelDelegate: NSWindowDelegate?

    private var panel: GlassPanel?
    private var storedFrame: NSRect?
    private let dismissMonitors = EventMonitorStore()

    init(
        panelFactory: PanelFactory,
        screenProvider: ActiveScreenProvider,
        batteryMonitor: BatteryStatusMonitor,
        codexUsageMonitor: CodexUsageMonitor,
        panelDelegate: NSWindowDelegate?
    ) {
        self.panelFactory = panelFactory
        self.screenProvider = screenProvider
        self.batteryMonitor = batteryMonitor
        self.codexUsageMonitor = codexUsageMonitor
        self.panelDelegate = panelDelegate
    }

    deinit {
        dismissMonitors.removeAll()
    }

    func show(onSubmit: @escaping (String) -> Void) {
        guard let screen = screenProvider.activeScreen() else {
            return
        }

        let frame = storedFrame ?? Self.defaultFrame(on: screen)
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)

        batteryMonitor.start()
        panel.isMovableByWindowBackground = false
        panel.setFrame(frame, display: true)

        let contentView = DraggableHostingView(
            rootView: CompactEntryHostView(
                batteryMonitor: batteryMonitor,
                codexUsageMonitor: codexUsageMonitor,
                onSubmit: onSubmit
            )
        )
        contentView.windowDragMode = .compactPrompt
        panel.contentView = contentView
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installDismissMonitorsIfNeeded()
    }

    func dismiss() {
        panel?.orderOut(nil)
        batteryMonitor.stop()
        dismissMonitors.removeAll()
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        guard movedPanel === panel else {
            return false
        }

        storedFrame = movedPanel.frame
        return true
    }

    private static func defaultFrame(on screen: NSScreen) -> NSRect {
        let size = NSSize(width: 420, height: 210)
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - (visibleFrame.height / 3) - (size.height / 2)
        )

        return NSRect(origin: origin, size: size)
    }

    private func installDismissMonitorsIfNeeded() {
        guard dismissMonitors.isEmpty else {
            return
        }

        if let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard let self else {
                return event
            }

            guard
                self.panel?.isVisible == true,
                CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode: event.keyCode)
            else {
                return event
            }

            self.dismiss()
            return nil
        }) {
            dismissMonitors.append(keyMonitor)
        }

        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] event in
            self?.dismissIfNeededForMouseDown(at: NSEvent.mouseLocation)
            return event
        }) {
            dismissMonitors.append(localMouseMonitor)
        }

        if let globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask, handler: { [weak self] _ in
            Task { @MainActor in
                self?.dismissIfNeededForMouseDown(at: NSEvent.mouseLocation)
            }
        }) {
            dismissMonitors.append(globalMouseMonitor)
        }
    }

    private func dismissIfNeededForMouseDown(at point: NSPoint) {
        guard let panel, panel.isVisible else {
            return
        }

        if CompactEntryDismissPolicy.shouldDismissForMouseDown(at: point, panelFrame: panel.frame) {
            dismiss()
        }
    }
}
```

- [ ] **Step 2: Replace compact panel state in `WindowCoordinator`**

Delete these properties from `WindowCoordinator`:

```swift
private var compactPanel: GlassPanel?
private var compactPanelFrame: NSRect?
private let compactDismissMonitors = EventMonitorStore()
```

Add this lazy property after monitor initialization properties:

```swift
private lazy var compactPanelController = CompactPanelController(
    panelFactory: panelFactory,
    screenProvider: screenProvider,
    batteryMonitor: batteryMonitor,
    codexUsageMonitor: codexUsageMonitor,
    panelDelegate: self
)
```

Delete this line from `deinit`:

```swift
compactDismissMonitors.removeAll()
```

- [ ] **Step 3: Replace compact show and dismiss methods**

Replace `showCompactPanel()` in `WindowCoordinator` with:

```swift
private func showCompactPanel() {
    sidePanel?.orderOut(nil)
    edgeAffordancePanel?.orderOut(nil)

    compactPanelController.show { [weak self] prompt in
        Task { @MainActor in
            self?.startConversation(prompt: prompt)
        }
    }
}
```

Replace `dismissCompactPanel()` in `WindowCoordinator` with:

```swift
private func dismissCompactPanel() {
    compactPanelController.dismiss()
}
```

Delete `defaultCompactPanelFrame(on:)`, `installCompactDismissMonitorsIfNeeded()`, and `dismissCompactPanelIfNeededForMouseDown(at:)` from `WindowCoordinator`.

- [ ] **Step 4: Route compact move events to the controller**

In `windowDidMove(_:)`, replace the compact panel branch with:

```swift
if compactPanelController.recordMove(of: panel) {
    return
}
```

- [ ] **Step 5: Run app build and core tests**

Run:

```bash
swift run CodexPlusCoreTests
swift build -c release
```

Expected: tests pass and release build succeeds.

- [ ] **Step 6: Commit compact panel extraction**

Run:

```bash
git add Sources/CodexPlusApp/CompactPanelController.swift Sources/CodexPlusApp/WindowCoordinator.swift
git commit -m "refactor: extract compact panel controller"
```

---

### Task 6: Extract SidePanelController

**Files:**
- Create: `Sources/CodexPlusApp/SidePanelController.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`

- [ ] **Step 1: Create side panel actions and controller**

Create `Sources/CodexPlusApp/SidePanelController.swift`:

```swift
import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
struct SidePanelActions {
    let onFollowUp: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onToggleSide: () -> Void
    let onToggleFullAccess: () -> Void
}

@MainActor
final class SidePanelController {
    private let panelFactory: PanelFactory
    private let screenProvider: ActiveScreenProvider
    private weak var panelDelegate: NSWindowDelegate?
    private let preferredSide: () -> SideAttachment
    private let setPreferredSide: (SideAttachment) -> Void
    private let hasActiveConversation: () -> Bool
    private let isPinned: () -> Bool
    private let showSidePanel: () -> Void

    private var panel: GlassPanel?
    private var customFrame: NSRect?
    private var edgeAffordancePanel: GlassPanel?
    private var model: ConversationPanelModel?
    private var isContentInstalled = false
    private let mouseExitMonitors = EventMonitorStore()
    private var hasMouseEnteredPanel = false

    init(
        panelFactory: PanelFactory,
        screenProvider: ActiveScreenProvider,
        panelDelegate: NSWindowDelegate?,
        preferredSide: @escaping () -> SideAttachment,
        setPreferredSide: @escaping (SideAttachment) -> Void,
        hasActiveConversation: @escaping () -> Bool,
        isPinned: @escaping () -> Bool,
        showSidePanel: @escaping () -> Void
    ) {
        self.panelFactory = panelFactory
        self.screenProvider = screenProvider
        self.panelDelegate = panelDelegate
        self.preferredSide = preferredSide
        self.setPreferredSide = setPreferredSide
        self.hasActiveConversation = hasActiveConversation
        self.isPinned = isPinned
        self.showSidePanel = showSidePanel
    }

    deinit {
        mouseExitMonitors.removeAll()
    }

    func prepareCenteredFrame() {
        guard let screen = screenProvider.activeScreen() else {
            customFrame = nil
            return
        }

        customFrame = ConversationPanelLayoutPolicy.initialCenteredFrame(in: screen.visibleFrame)
    }

    func show(session: ConversationSession, actions: SidePanelActions) {
        edgeAffordancePanel?.orderOut(nil)

        guard let screen = screenProvider.activeScreen() else {
            return
        }

        let frame = sidePanelFrame(on: screen)
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)

        panel.setFrame(frame, display: true)
        hasMouseEnteredPanel = false
        refresh(session: session, actions: actions, on: panel)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installMouseExitMonitorIfNeeded()
    }

    func refresh(session: ConversationSession, actions: SidePanelActions) {
        refresh(session: session, actions: actions, on: panel)
    }

    func orderOutAll() {
        panel?.orderOut(nil)
        edgeAffordancePanel?.orderOut(nil)
    }

    func closeAndReset() {
        orderOutAll()
        model = nil
        isContentInstalled = false
        hasMouseEnteredPanel = false
    }

    func clearCustomFrame() {
        customFrame = nil
    }

    func moveToPreferredSide(session: ConversationSession, actions: SidePanelActions) {
        guard let screen = screenProvider.activeScreen(), let panel else {
            return
        }

        panel.setFrame(sidePanelFrame(on: screen), display: true, animate: true)
        refresh(session: session, actions: actions, on: panel)
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        guard movedPanel === panel else {
            return false
        }

        updatePlacement(afterMoving: movedPanel)
        return true
    }

    private func refresh(session: ConversationSession, actions: SidePanelActions, on targetPanel: GlassPanel?) {
        let panelModel: ConversationPanelModel

        if let model {
            model.session = session
            panelModel = model
        } else {
            panelModel = ConversationPanelModel(session: session)
            model = panelModel
        }

        if let targetPanel, !isContentInstalled {
            installContent(in: targetPanel, model: panelModel, actions: actions)
        }
    }

    private func installContent(in panel: GlassPanel, model: ConversationPanelModel, actions: SidePanelActions) {
        panel.contentView = DraggableHostingView(
            rootView: ConversationPanelHostView(
                model: model,
                onFollowUp: actions.onFollowUp,
                onStop: actions.onStop,
                onClose: actions.onClose,
                onTogglePin: actions.onTogglePin,
                onToggleSide: actions.onToggleSide,
                onToggleFullAccess: actions.onToggleFullAccess
            )
        )
        isContentInstalled = true
    }

    private func sidePanelFrame(on screen: NSScreen) -> NSRect {
        if let customFrame {
            return customFrame
        }

        let visibleFrame = screen.visibleFrame
        let width = min(CGFloat(460), visibleFrame.width)
        let x: CGFloat

        switch preferredSide() {
        case .left:
            x = visibleFrame.minX
        case .right:
            x = visibleFrame.maxX - width
        }

        return NSRect(
            x: x,
            y: visibleFrame.minY,
            width: width,
            height: visibleFrame.height
        )
    }

    private func edgeAffordanceFrame(on screen: NSScreen) -> NSRect {
        let visibleFrame = screen.visibleFrame
        let size = NSSize(width: 12, height: 96)
        let x: CGFloat

        switch preferredSide() {
        case .left:
            x = visibleFrame.minX
        case .right:
            x = visibleFrame.maxX - size.width
        }

        return NSRect(
            x: x,
            y: visibleFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private func showEdgeAffordance(on screen: NSScreen?) {
        guard
            hasActiveConversation(),
            !isPinned(),
            customFrame == nil,
            let screen = screen ?? screenProvider.activeScreen()
        else {
            return
        }

        let frame = edgeAffordanceFrame(on: screen)
        let panel = edgeAffordancePanel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(
            rootView: SideEdgeAffordanceView { [weak self] in
                Task { @MainActor in
                    self?.showSidePanel()
                }
            }
        )
        panel.orderFrontRegardless()
        edgeAffordancePanel = panel
    }

    private func installMouseExitMonitorIfNeeded() {
        guard mouseExitMonitors.isEmpty else {
            return
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.hideIfMouseExited()
            return event
        }

        if let localMonitor {
            mouseExitMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            Task { @MainActor in
                self?.hideIfMouseExited()
            }
        }) {
            mouseExitMonitors.append(globalMonitor)
        }
    }

    private func hideIfMouseExited() {
        if
            let edgeAffordancePanel,
            edgeAffordancePanel.isVisible,
            NSMouseInRect(NSEvent.mouseLocation, edgeAffordancePanel.frame.insetBy(dx: -8, dy: -8), false) {
            showSidePanel()
            return
        }

        guard
            let panel,
            panel.isVisible,
            customFrame == nil,
            !isPinned()
        else {
            return
        }

        let panelHitFrame = panel.frame.insetBy(dx: -8, dy: -8)
        if NSMouseInRect(NSEvent.mouseLocation, panelHitFrame, false) {
            hasMouseEnteredPanel = true
            return
        }

        if hasMouseEnteredPanel {
            let screen = panel.screen ?? screenProvider.activeScreen()
            panel.orderOut(nil)
            showEdgeAffordance(on: screen)
        }
    }

    private func updatePlacement(afterMoving panel: GlassPanel) {
        guard let screen = panel.screen ?? screenProvider.activeScreen() else {
            customFrame = panel.frame
            return
        }

        switch PanelPlacementPolicy.placement(
            for: panel.frame,
            in: screen.visibleFrame
        ) {
        case let .attached(side):
            customFrame = nil
            setPreferredSide(side)
        case .free:
            customFrame = panel.frame
        }
    }
}
```

- [ ] **Step 2: Add side controller to `WindowCoordinator`**

Delete these properties from `WindowCoordinator`:

```swift
private var sidePanel: GlassPanel?
private var sidePanelCustomFrame: NSRect?
private var edgeAffordancePanel: GlassPanel?
private var sidePanelModel: ConversationPanelModel?
private var isSidePanelContentInstalled = false
private let mouseExitMonitors = EventMonitorStore()
private var hasMouseEnteredSidePanel = false
```

Add this lazy property:

```swift
private lazy var sidePanelController = SidePanelController(
    panelFactory: panelFactory,
    screenProvider: screenProvider,
    panelDelegate: self,
    preferredSide: { [conversationCoordinator] in
        conversationCoordinator.preferredSide
    },
    setPreferredSide: { [conversationCoordinator] side in
        guard conversationCoordinator.preferredSide != side else {
            return
        }

        conversationCoordinator.togglePreferredSide()
    },
    hasActiveConversation: { [conversationCoordinator] in
        conversationCoordinator.activeConversation != nil
    },
    isPinned: { [conversationCoordinator] in
        conversationCoordinator.activeConversation?.isPinned == true
    },
    showSidePanel: { [weak self] in
        self?.showSidePanel()
    }
)
```

Delete this line from `deinit`:

```swift
mouseExitMonitors.removeAll()
```

- [ ] **Step 3: Add a reusable side action builder**

Add this helper to `WindowCoordinator`:

```swift
private func sidePanelActions() -> SidePanelActions {
    SidePanelActions(
        onFollowUp: { [weak self] prompt in
            Task { @MainActor in
                self?.handleFollowUp(prompt)
            }
        },
        onStop: { [weak self] in
            Task { @MainActor in
                self?.stopActiveRun()
            }
        },
        onClose: { [weak self] in
            Task { @MainActor in
                self?.closeSidePanel()
            }
        },
        onTogglePin: { [weak self] in
            Task { @MainActor in
                self?.togglePin()
            }
        },
        onToggleSide: { [weak self] in
            Task { @MainActor in
                self?.togglePreferredSide()
            }
        },
        onToggleFullAccess: { [weak self] in
            Task { @MainActor in
                self?.toggleFullAccess()
            }
        }
    )
}
```

- [ ] **Step 4: Route side panel lifecycle through the controller**

Replace `showCompactPanel()` with:

```swift
private func showCompactPanel() {
    sidePanelController.orderOutAll()

    compactPanelController.show { [weak self] prompt in
        Task { @MainActor in
            self?.startConversation(prompt: prompt)
        }
    }
}
```

Replace `showSidePanel()` with:

```swift
private func showSidePanel() {
    dismissCompactPanel()

    guard let session = conversationCoordinator.activeConversation else {
        showCompactPanel()
        return
    }

    sidePanelController.show(session: session, actions: sidePanelActions())
}
```

Replace `prepareCenteredSidePanelFrame()` with:

```swift
private func prepareCenteredSidePanelFrame() {
    sidePanelController.prepareCenteredFrame()
}
```

Replace `refreshSidePanelContent(on:)` and `installSidePanelContent(in:model:)` with:

```swift
private func refreshSidePanelContent() {
    guard let session = conversationCoordinator.activeConversation else {
        return
    }

    sidePanelController.refresh(session: session, actions: sidePanelActions())
}
```

Update call sites from `refreshSidePanelContent(on: panel)` to:

```swift
refreshSidePanelContent()
```

- [ ] **Step 5: Route close, side toggle, and move behavior**

In `closeSidePanel()`, replace direct panel cleanup with:

```swift
guard let session = conversationCoordinator.activeConversation else {
    sidePanelController.orderOutAll()
    return
}
```

After `conversationCoordinator.closeConversation(session.id)`, call:

```swift
sidePanelController.closeAndReset()
```

Replace `togglePreferredSide()` with:

```swift
private func togglePreferredSide() {
    sidePanelController.clearCustomFrame()
    conversationCoordinator.togglePreferredSide()

    if let session = conversationCoordinator.activeConversation {
        sidePanelController.moveToPreferredSide(session: session, actions: sidePanelActions())
        refreshSidePanelContent()
    }
}
```

In `windowDidMove(_:)`, replace the side panel branch with:

```swift
if sidePanelController.recordMove(of: panel) {
    return
}
```

Delete these methods from `WindowCoordinator`:

```swift
private func sidePanelFrame(on screen: NSScreen) -> NSRect
private func edgeAffordanceFrame(on screen: NSScreen) -> NSRect
private func showEdgeAffordance(on screen: NSScreen?)
private func installMouseExitMonitorIfNeeded()
private func hideSidePanelIfMouseExited()
private func updateSidePanelPlacement(afterMoving panel: GlassPanel)
private func setPreferredSide(_ side: SideAttachment)
```

- [ ] **Step 6: Run tests and release build**

Run:

```bash
swift run CodexPlusCoreTests
swift build -c release
```

Expected: tests pass and release build succeeds.

- [ ] **Step 7: Commit side panel extraction**

Run:

```bash
git add Sources/CodexPlusApp/SidePanelController.swift Sources/CodexPlusApp/WindowCoordinator.swift
git commit -m "refactor: extract side panel controller"
```

---

### Task 7: Reuse Timestamp Formatters in LocalCodexUsageProvider

**Files:**
- Modify: `Sources/CodexPlusCore/LocalCodexUsageProvider.swift`
- Modify: `Tests/CodexPlusCoreTests/main.swift`

- [ ] **Step 1: Keep existing timestamp behavior tests**

Confirm `Tests/CodexPlusCoreTests/main.swift` still contains these assertions:

```swift
expect(
    fractionalUsageStatus.fiveHourPercent == 74,
    "codex usage provider lets fractional-second timestamp win"
)
expect(
    fractionalUsageStatus.observedAt == fractionalTimestampFormatter.date(from: "2026-07-03T02:00:00.123Z"),
    "codex usage provider parses fractional-second timestamp"
)
```

- [ ] **Step 2: Add locked static timestamp parser**

In `Sources/CodexPlusCore/LocalCodexUsageProvider.swift`, add this private type near `FileStatusCache`:

```swift
private final class TimestampParser: @unchecked Sendable {
    static let shared = TimestampParser()

    private let lock = NSLock()
    private let wholeSecondFormatter = ISO8601DateFormatter()
    private let fractionalSecondFormatter: ISO8601DateFormatter

    private init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalSecondFormatter = formatter
    }

    func date(from value: String) -> Date? {
        lock.lock()
        defer {
            lock.unlock()
        }

        return wholeSecondFormatter.date(from: value) ??
            fractionalSecondFormatter.date(from: value)
    }
}
```

Replace `timestamp(from:)` with:

```swift
private static func timestamp(from value: String?) -> Date? {
    guard let value else {
        return nil
    }

    return TimestampParser.shared.date(from: value)
}
```

- [ ] **Step 3: Run usage tests through the full harness**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: usage provider tests still pass, including whole-second and fractional-second timestamp selection.

- [ ] **Step 4: Commit usage parser optimization**

Run:

```bash
git add Sources/CodexPlusCore/LocalCodexUsageProvider.swift Tests/CodexPlusCoreTests/main.swift
git commit -m "perf: reuse usage timestamp formatters"
```

---

### Task 8: Final Verification and Size Record

**Files:**
- No source edits.

- [ ] **Step 1: Run the internal test harness**

Run:

```bash
swift run CodexPlusCoreTests
```

Expected: the executable exits 0 and prints `CodexPlusCoreTests passed:`.

- [ ] **Step 2: Run release build**

Run:

```bash
swift build -c release
```

Expected: release build completes successfully.

- [ ] **Step 3: Record release app size**

Run:

```bash
ls -lh .build/release/CodexPlusApp
```

Expected: output includes `.build/release/CodexPlusApp`; compare the size to the pre-refactor 1.1 MB baseline in the design spec.

- [ ] **Step 4: Verify product boundary**

Run:

```bash
swift package dump-package
```

Expected: the explicit `products` array contains only `CodexPlusApp`. `CodexPlusCore` and `CodexPlusCoreTests` appear only under `targets`.

- [ ] **Step 5: Verify no stale abstractions remain**

Run:

```bash
rg 'ScreenPoint|ScreenRect|LineBuffer|CodexRunHandle|IOKit' Sources/CodexPlusCore Tests/CodexPlusCoreTests/main.swift
```

Expected: no matches for `ScreenPoint`, `ScreenRect`, `LineBuffer`, or `CodexRunHandle`. `IOKit` has no matches under `Sources/CodexPlusCore`.

- [ ] **Step 6: Verify working tree state**

Run:

```bash
git status --short
```

Expected: no output.
