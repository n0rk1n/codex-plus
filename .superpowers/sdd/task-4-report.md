# Task 4 Report

## files changed
- `Sources/CodexPlusApp/Settings/PromptTemplateManagerView.swift`
- `Sources/CodexPlusApp/Workbench/WorkbenchMetrics.swift`

## behavior
- Added a standalone SwiftUI prompt template manager built with `LiquidGlassScene` and `LiquidGlassContainer`.
- Sidebar includes search, source filter, and multi-select type filters. Template cards show `类型` above `来源`, and `来源` only appears in the left card list.
- Detail form keeps `类型` as a required single-select menu, keeps `系统提示词` required, and allows `用户提示词` to be empty.
- Built-in system templates render as read-only in the detail pane, hide destructive editing actions, and can only be copied into a user template.
- User templates can be created, edited, saved, discarded, deleted, and copied.
- The manager remains independent and does not connect prompt templates into runtime prompt usage.

## verification
- `env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/codex-swift-cache swift build`
  - Result: blocked by sandbox during SwiftPM manifest compilation with `sandbox-exec: sandbox_apply: Operation not permitted`.
- `git diff --check`
  - Result: pass.

## commit hash
- `8c0304e`

## concerns
- Required `swift build` verification could not complete in the managed sandbox. The environment rejected an unsandboxed retry, so compile success is not confirmed in this run.
