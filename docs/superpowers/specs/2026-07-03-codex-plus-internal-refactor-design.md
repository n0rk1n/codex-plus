# Codex+ Internal Refactor Design

Date: 2026-07-03

## Goal

Refactor Codex+ as a local macOS app, not as a reusable Swift library. The work should reduce architectural weight, remove unused or premature abstractions, keep the app's behavior unchanged, and preserve the pure-core test boundary that makes AppKit and SwiftUI behavior safer to evolve.

The release baseline before this design is:

- `swift build -c release` passes.
- `swift run CodexPlusCoreTests` passes with 207 assertions.
- `.build/release/CodexPlusApp` is about 1.1 MB.
- The package has no third-party dependencies.

## Product Boundary

Codex+ ships only as `CodexPlusApp`, a local Mac app. `CodexPlusCore` remains an internal target for testable non-UI logic, but it is not a public product and should not be designed as an external SDK. This means future changes should prefer a small internal API over broad public flexibility.

## Recommended Approach

Use the internal-core refactor:

- Keep two targets: `CodexPlusApp` and `CodexPlusCore`.
- Expose only the app product from SwiftPM.
- Keep `CodexPlusCoreTests` as an internal executable target for the existing test harness.
- Move platform integration that belongs to the app, such as the IOKit battery provider, out of Core.
- Split AppKit window management helpers out of `WindowCoordinator` while keeping the conversation run flow centralized.

This keeps the useful test seam without pretending Core is a separately published package.

## Package Structure

`Package.swift` should expose only `CodexPlusApp` as a product. `CodexPlusCore` and `CodexPlusCoreTests` remain targets but are not products. The app target continues to depend on Core.

`CodexPlusCore` should not link AppKit, SwiftUI, Carbon, or IOKit. It should contain:

- Conversation models and coordinator.
- Codex command and event parsing.
- Process runner and run controller.
- Usage status models and local usage provider.
- Battery model and `BatteryStatusProviding` protocol.
- Pure geometry, layout, drag, snap, dismiss, and timeline policies.

`CodexPlusApp` should contain:

- App lifecycle, hot key registration, panels, and monitors.
- SwiftUI views.
- IOKit battery provider.
- AppKit geometry conversion helpers.
- Panel creation and active-screen lookup.

## Deletion And Shrink List

Delete `LineBuffer.swift` because production code no longer uses it. Remove only its direct tests; keep the process runner tests that exercise real stdout buffering.

Replace custom `ScreenPoint` and `ScreenRect` with `CGPoint` and `CGRect`. This removes local geometry duplication and lets Core policies use platform-native geometry types already available through Foundation/CoreGraphics.

Remove the single-implementation `CodexRunHandle` protocol. `ProcessCodexRunner.run` should return `ProcessCodexRunHandle` directly. The protocol can come back when a second run handle exists.

Do not split Core into additional targets. The package is already small, and extra targets would increase build and navigation overhead without reducing the shipped app's meaningful complexity.

Do not remove the provider protocols used by monitors. They are small, directly tested, and make the battery and usage monitors deterministic without AppKit or IOKit.

## App Layer Design

`WindowCoordinator` should remain the main orchestration entry point for:

- Global shortcut behavior.
- Starting a conversation.
- Sending follow-ups.
- Stopping a run.
- Handling Codex events and finish results.
- Permission mode toggles.
- Pin and side toggles.

Move AppKit support details into small collaborators:

- `PanelFactory`: creates and configures `GlassPanel` instances.
- `ActiveScreenProvider`: finds the best screen from the key window, mouse location, main screen, or first available screen.
- `CompactPanelController`: owns compact panel display, stored compact frame, battery monitor lifetime, and compact dismiss event monitors.
- `SidePanelController`: owns side panel display, custom frame, edge affordance panel, mouse-exit monitors, and side placement updates.

These helpers should avoid owning conversation business state. They can accept closures for UI actions such as submit, close, stop, pin, side toggle, and full-access toggle.

The conversation run chain should stay in `WindowCoordinator` for now. Splitting it at the same time would add closure plumbing without reducing the highest-risk AppKit complexity.

## Performance Design

`LocalCodexUsageProvider.timestamp(from:)` should reuse static ISO8601 formatters instead of creating new formatters per parsed line. This preserves parsing behavior for whole-second and fractional-second timestamps while reducing scan-time allocation.

Do not change candidate file discovery, archive scanning, cache invalidation, or newest-status selection in this refactor. Those changes could affect observable usage behavior and should be separate if needed later.

## Error Handling

Existing error behavior should remain unchanged:

- Usage status returns `.unknown` when no usable data is available.
- Battery status returns `.unknown` when IOKit cannot provide usable values.
- Codex process start failures still emit an error event and finish with exit code 127.
- Failed Codex runs still surface stderr when available.
- Closing a running conversation still asks before stopping it.

## Testing

Update the existing core harness instead of replacing it.

Required coverage:

- Existing 207 assertions should remain equivalent, except direct `LineBuffer` assertions are removed with the unused type.
- Layout, drag, snap, dismiss, and placement tests should use `CGPoint` and `CGRect`.
- `ProcessCodexRunner` stop behavior should still be covered after returning the concrete handle.
- Usage timestamp parsing should still cover whole-second and fractional-second timestamps.
- Package naming checks should be updated for the app-only product boundary.

Verification commands:

- `swift run CodexPlusCoreTests`
- `swift build -c release`
- `ls -lh .build/release/CodexPlusApp`

Success means tests and release build pass, the app product remains the only exposed SwiftPM product, Core no longer links IOKit, and release size is recorded against the 1.1 MB baseline.

## Out Of Scope

- Changing user-facing behavior.
- Changing Codex command arguments or permission semantics.
- Replacing the custom test harness with XCTest or Swift Testing.
- Persisting conversations.
- Optimizing usage file discovery beyond formatter reuse.
- Creating more SwiftPM targets.
