# Deprecated Root Snapshot

This archive preserves the old root checkout before promoting the v1 workbench
implementation from `.worktrees/codex-plus-v1-workbench` into the repository
root on 2026-07-06.

## Contents

- `codex-plus-root-before-v1-workbench.tar.gz`: root source tree before the
  promotion, excluding `.git`, `.build`, `.swiftpm`, `.worktrees`, and
  `.DS_Store`.

## Restore

From a scratch directory:

```bash
tar -xzf codex-plus-root-before-v1-workbench.tar.gz
```
