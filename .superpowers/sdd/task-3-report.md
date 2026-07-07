## Task 3 Report

### Files changed
- `Sources/CodexPlusApp/Settings/PromptTemplateSettingsStore.swift`

### Behavior
- Added `@MainActor final class PromptTemplateSettingsStore: ObservableObject` with published template state, filters, selection, draft, dirty flag, validation error, and local error message.
- Wired the store to `PromptTemplateLibrary` validation, sorting, filtering, and copy-draft helpers.
- Supported create, copy, update, discard, save, delete, and type-filter toggling in a way that keeps system templates read-only and user templates editable.
- Kept the store isolated from runtime prompt execution and archive/composer flows.

### Verification
- `env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/codex-swift-cache swift build`
  - Passed after rerunning outside the SwiftPM sandbox restriction.
- `git diff --check`
  - Passed.

### Commit hash
- `6f5e480`

### Concerns
- The sandboxed build path is still blocked by `sandbox_apply: Operation not permitted`, but the same build command passes when run with external permission.
