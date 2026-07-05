# Legacy Pre-V1 Archive

This folder preserves the Codex Plus project state before the V1 rebuild work starts.

- Archive date: 2026-07-05
- Source commit: `adb4a2ffd9611f613ee7fba1040b3079dfa7e9b4`
- Archive file: `codex-plus-pre-v1-source.tar.gz`

The archive intentionally excludes transient local folders:

- `.git/`
- `.build/`
- `.swiftpm/`
- `.worktrees/`
- `.superpowers/`
- `archives/`

The V1 implementation should happen in an isolated worktree created after this archive commit.
