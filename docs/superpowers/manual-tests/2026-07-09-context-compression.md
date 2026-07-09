# Context Compression Manual QA

## Automatic Verification

- `swift build`
- `swift test --filter WorkbenchContextCompressionTests`
- `swift test --filter ArchiveContextCompressionTests`
- `swift test`

Known warning: `CodexTextField.swift` still emits an existing macOS deprecation warning for `onChange(of:perform:)`. It is unrelated to context compression.

## Manual Scenario

1. Launch the app and create a conversation with at least four user/AI rounds.
2. Confirm the normal timeline shows original source text, not compressed replacements.
3. Select one round from the timeline.
4. Open `编辑`, choose `AI`, replace the assistant segment with one useful sentence, and save.
5. Confirm the source row remains visible and the timeline shows `已修订`.
6. Use `预览模型输入` from the composer and confirm the preview contains the edited segment, not the old full AI response.
7. Select two adjacent rounds and run `默认压缩`.
8. Confirm a `拼接压缩` marker appears and the inspector shows the adjacent relationship.
9. Exclude one round.
10. Confirm it is marked `已排除模型上下文` and original text is dimmed, not removed.
11. Enter a follow-up prompt and confirm the context budget badge appears near the send control.
12. Force or simulate a hard-limit budget state.
13. Confirm send is disabled with `需要压缩后继续`.
14. Click `交付系统完成压缩`.
15. Confirm the resulting system compression becomes a visible active version in the timeline history.
16. Archive the conversation.
17. Confirm the archive markdown includes `## Context Compression`, active model input, versions, sources, and active versions.
18. Search archives by original source text and confirm the conversation is found.
19. Search by compressed-only text and confirm search does not rely on compressed output as the primary searchable body.

## Pass Criteria

- Original event records remain recoverable and visible in the timeline.
- Model input preview matches the text used for sending follow-up prompts.
- Only the final active lineage is used for model input.
- Excluded rows are dimmed and omitted from model input.
- Joined compression is visible as a relationship across adjacent rounds.
- Compression provider inputs are traceable through persisted input snapshots.
- Archive export preserves compression metadata while archive search remains source-text based.
- Old experimental memory-card compression snapshot UI is absent from the runtime timeline.
