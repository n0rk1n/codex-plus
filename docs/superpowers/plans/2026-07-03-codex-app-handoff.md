# Codex App Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Send the compact `Ask Codex` prompt into a projectless Codex App thread and open that thread in the Codex desktop app.

**Architecture:** Add a small Core JSON-RPC protocol layer plus a process runner for `codex app-server`. The App target keeps each handoff process alive until the started turn completes, and opens `codex://threads/<sessionId>` after `turn/start` is accepted.

**Tech Stack:** Swift 6, Foundation `Process`, JSON-RPC over JSONL, AppKit `NSWorkspace`.

---

### Task 1: Protocol And Runner

**Files:**
- Create: `Sources/CodexPlusCore/CodexAppServerProtocol.swift`
- Create: `Sources/CodexPlusCore/ProcessCodexAppServerHandoffRunner.swift`
- Test: `Tests/CodexPlusCoreTests/main.swift`

- [ ] Write tests for JSON-RPC messages: `initialize`, `thread/start`, `turn/start`, and request-denial responses.
- [ ] Run `swift run CodexPlusCoreTests` and confirm the new tests fail because the new types do not exist.
- [ ] Implement protocol helpers and a process runner that starts `codex app-server`, creates a projectless thread, starts a turn, emits a deep link, and keeps the process alive until `turn/completed` or failure.
- [ ] Run `swift run CodexPlusCoreTests` and confirm the new runner tests pass.

### Task 2: App Integration

**Files:**
- Modify: `Sources/CodexPlusApp/AppDelegate.swift`
- Modify: `Sources/CodexPlusApp/WindowCoordinator.swift`

- [ ] Replace compact prompt submission with the Codex App handoff runner.
- [ ] Keep multiple active handoff handles keyed by UUID so one prompt does not cancel another.
- [ ] Open the returned deep link with `NSWorkspace`; if URL opening fails, launch `codex app` as a fallback and surface an internal error conversation.
- [ ] Run `swift build` and `swift run CodexPlusCoreTests`.

### Task 3: Verification

**Files:**
- No new files.

- [ ] Review `git diff --check`.
- [ ] Run the app and submit a small prompt from `Ask Codex`.
- [ ] Confirm Codex App opens to the created thread and the turn starts executing.
