## Task 3 Report

### Files changed
- `Sources/CodexPlusApp/Settings/PromptTemplateSettingsStore.swift`
- `Tests/CodexPlusCoreTests/PromptTemplateSettingsStoreLegacyTests.swift`
- `Tests/CodexPlusCoreTests/main.swift`
- `Package.swift`

### Behavior
- Added `@MainActor final class PromptTemplateSettingsStore: ObservableObject` with published template state, filters, selection, draft, dirty flag, validation error, and local error message.
- Wired the store to `PromptTemplateLibrary` validation, sorting, filtering, and copy-draft helpers.
- Supported create, copy, update, discard, save, delete, and type-filter toggling in a way that keeps system templates read-only and user templates editable.
- Hardened `save()` so it returns early for non-editable state and system-built-in selections.
- Changed discard/reload selection fallback to respect `visibleTemplates` and clear selection when no visible template remains.
- Added legacy runner coverage for the guarded save path and filtered fallback selection paths.
- Kept the store isolated from runtime prompt execution and archive/composer flows.

### Verification
- `env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/codex-swift-cache swift build`
  - Blocked by sandbox with `sandbox_apply: Operation not permitted` while compiling the manifest.
- `env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/codex-swift-cache swift run CodexPlusCoreLegacyTests`
  - Blocked by the same sandbox manifest restriction.
- `git diff --check`
  - Passed.

### Commit hash
- `d9bce26`

### Concerns
- Full SwiftPM verification is blocked by the sandbox manifest restriction in this environment.
