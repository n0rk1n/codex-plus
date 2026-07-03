# Task 3 Report: Parallel Run Registry And Working Directory

## Status

Implemented the scoped Task 3 changes in core only:

- `ProcessCodexRunner.run` now accepts `workingDirectoryURL` with a default value and applies it to the launched `Process`.
- `CodexRunController` now tracks active runs per session, exposes aggregate `isRunning` plus `isRunning(sessionID:)`, allows parallel runs across different session IDs, rejects duplicate starts for the same session ID, and stops runs per session.
- `CodexPlusCoreTests` now includes the working-directory runner test and the parallel controller registry test from the brief, plus an explicit `workingDirectoryURL: nil` call in the existing controller test.

No UI/App files were modified. No archive manager or persistence work was added.

## TDD Notes

Per the brief, I added the new tests first in `Tests/CodexPlusCoreTests/main.swift`.

I then attempted to run:

```bash
swift run CodexPlusCoreTests
```

The run did not reach feature-level RED/GREEN validation because the local environment is blocked before compilation. Exact output included:

- `warning: /Users/oriki/Library/... is not accessible or not writable, disabling user-level cache features.`
- `error: unable to open output file '/Users/oriki/.cache/clang/ModuleCache/.../SwiftShims-....pcm': 'Operation not permitted'`
- `error: failed to build module 'Swift'; this SDK is not supported by the compiler ... Please select a toolchain which matches the SDK.`

So the TDD sequence is:

1. Added failing tests from the brief.
2. Ran the required test command and captured the environment/toolchain failure.
3. Implemented the minimal code changes required by the brief.
4. Re-ran verification command; the same environment/toolchain blocker still prevents local execution.

## Files Changed

- `Sources/CodexPlusCore/ProcessCodexRunner.swift`
- `Sources/CodexPlusCore/CodexRunController.swift`
- `Tests/CodexPlusCoreTests/main.swift`

## Implementation Summary

### `ProcessCodexRunner`

- Added `workingDirectoryURL: URL? = nil` to the public `run` API.
- Set `process.currentDirectoryURL = workingDirectoryURL` before launch.
- Kept existing call sites source-compatible by using the default parameter value.

### `CodexRunController`

- Replaced single-active-run state with:
  - `activeRuns: [UUID: ActiveRun]`
  - `stoppedRunIDs: Set<UUID>`
- Added:
  - `public var isRunning: Bool { !activeRuns.isEmpty }`
  - `public func isRunning(sessionID: UUID) -> Bool`
- Updated `start(...)` to:
  - accept `workingDirectoryURL: URL? = nil`
  - reject duplicate runs only for the same session ID
  - allow parallel runs for different session IDs
  - forward the working directory through to `ProcessCodexRunner`
- Updated `stop(sessionID:)` and callback handling to operate per session/run pair.

### Tests

- Added runner test verifying `pwd` reflects the supplied working directory.
- Added controller test verifying:
  - two different session IDs can run in parallel
  - duplicate start on the same session ID is rejected
  - per-session running state is exposed
  - aggregate running state clears after both finishes

## Verification

Attempted twice:

```bash
swift run CodexPlusCoreTests
```

Result: blocked by local SwiftPM/module-cache permission limits and an SDK/compiler mismatch before the package can compile.

## Post-Fix Controller Verification

- Controller reran with escalated SwiftPM permissions after canonicalizing the working-directory path assertion:
  - `swift run CodexPlusCoreTests`
  - `CodexPlusCoreTests passed: 218 assertions`
  - Output was clean.

## Concerns

- The code changes are tightly aligned to the brief, but I could not obtain a local compile/test pass in this sandbox because of the environment errors above.
- Controller verification should be rerun in an environment with writable module cache access and a matching Swift toolchain/SDK pair.

### Post-fix verification (path canonicalization)

After switching to canonical path comparison in `Tests/CodexPlusCoreTests/main.swift`, I reran:

```bash
swift run CodexPlusCoreTests
```

in `/Users/oriki/Documents/codex-plus/.worktrees/conversation-management` and observed the same environment/toolchain failure prior to test execution.

Exact output excerpt:

```text
warning: /Users/oriki/Library/org.swift.swiftpm/configuration is not accessible or not writable, disabling user-level cache features.
warning: /Users/oriki/Library/org.swift.swiftpm/security is not accessible or not writable, disabling user-level cache features.
warning: /Users/oriki/Library/Caches/org.swift.swiftpm is not accessible or not writable, disabling user-level cache features.
error: unable to open output file '/Users/oriki/.cache/clang/ModuleCache/1H92U27Y5N1PO/SwiftShims-3DMJL40ENYFGZ.pcm': 'Operation not permitted'
/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface:1:1: error: failed to build module 'Swift'; this SDK is not supported by the compiler (the SDK is built with 'Apple Swift version 6.3.2 effective-5.10 (swiftlang-6.3.2.1.2 clang-2100.0.123.2)', while this compiler is 'Apple Swift version 6.3.2 effective-5.10 (swiftlang-6.3.2.1.108 clang-2100.1.1.101)'). Please select a toolchain which matches the SDK.
```

## Follow-up: Per-Session Stop Regression Coverage

I added a focused regression test in `Tests/CodexPlusCoreTests/main.swift` beside the existing parallel controller coverage. The new test proves:

- stopping one session via `CodexRunController.stop(sessionID:)` does not stop or clear the sibling session
- the stopped session never reaches its finish handler
- the sibling session continues running and finishes normally

Verification:

```bash
swift run CodexPlusCoreTests
```

Escalated run result:

- `CodexPlusCoreTests passed: 231 assertions`

Test authoring note:

- My first version used semaphores for the controller start signals and deadlocked the main queue. I replaced those waits with the repo's `waitUntil` polling helper so the main-queue callbacks could run deterministically.
