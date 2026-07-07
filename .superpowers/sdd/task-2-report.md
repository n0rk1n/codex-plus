## Task 2 Report

### Files changed
- `Sources/CodexPlusCore/Persistence/PromptTemplateRepository.swift`
- `Sources/CodexPlusCore/Persistence/CodexPlusSchema.swift`
- `Sources/CodexPlusCore/Persistence/CodexPlusRepository.swift`
- `Sources/CodexPlusCore/Persistence/SQLiteCodexPlusStore.swift`
- `Tests/CodexPlusCoreXCTests/PromptTemplatePersistenceTests.swift`
- `Tests/CodexPlusCoreTests/PromptTemplatePersistenceLegacyTests.swift`
- `Tests/CodexPlusCoreTests/main.swift`

### Behavior
- Added a dedicated `PromptTemplateRepository` protocol and wired it into `CodexPlusRepository`.
- Bumped `CodexPlusSchema.version` from `1` to `2` and added a new `prompt_templates` table without changing existing tables.
- Implemented SQLite save/load/delete support for prompt templates.
- Enforced persistence rules so only `.userCustom` templates can be stored; built-in templates remain read-only and non-persisted.
- Added XCTest and legacy-runner coverage for schema creation, round-trip persistence, updates, deletion, and built-in rejection.

### Verification commands and results
- `env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/codex-swift-cache swift test --filter PromptTemplatePersistenceTests`
  - Failed due existing baseline/toolchain issue: `no such module 'XCTest'` while compiling existing XCTest files such as `Tests/CodexPlusCoreXCTests/ArchitectureBoundaryTests.swift`.
- `env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/codex-swift-cache swift run CodexPlusCoreLegacyTests`
  - Passed: `CodexPlusCoreTests passed: 440 assertions`
- `env CLANG_MODULE_CACHE_PATH=/private/tmp/codex-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/codex-swift-cache swift build`
  - Passed
- `git diff --check`
  - Passed

### Implementation commit hash
- `1701424`

### Concerns
- XCTest verification remains blocked by the current environment's inability to import `XCTest`, so executable legacy coverage is the reliable signal for this task right now.
