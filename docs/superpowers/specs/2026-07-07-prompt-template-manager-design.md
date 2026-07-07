# Prompt Template Manager Design

Date: 2026-07-07

## Summary

Codex+ will add an independent prompt template manager in Settings. The first version only manages prompt templates. It does not integrate with the composer, archive flow, prompt optimization button, Codex command construction, or any execution path.

The manager gives users a searchable list of prompt templates and a detail editor. Templates can be system built-in or user custom. System built-in templates are read-only and can be copied into user custom templates. User custom templates can be created, edited, copied, and deleted.

## Goals

- Provide a standalone Settings component for managing reusable prompt templates.
- Add a visible entry point from the main workbench into Settings.
- Support exactly two prompt template types in the first version:
  - 对归档对话进行总结
  - 优化用户对话输入框提示词
- Make system built-in templates visible but immutable.
- Let users manage their own custom templates without touching built-in defaults.
- Keep the model and storage independent so other features can use the manager later.

## Non-Goals

- Do not apply templates to the current composer input.
- Do not connect templates to archive summary generation.
- Do not connect templates to prompt optimization.
- Do not add template variables, version history, import/export, usage stats, sharing, or cloud sync.
- Do not change `codex exec` command construction.

## Template Model

Each prompt template has:

- `id`: stable identifier.
- `source`: system built-in or user custom.
- `type`: required single value.
- `name`: required display name.
- `systemPrompt`: required text.
- `userPrompt`: optional text.
- `note`: optional explanation of when to use the template.
- `createdAt`: automatic timestamp.
- `updatedAt`: automatic timestamp.

The `type` field must always be one of:

- `archiveConversationSummary`: 对归档对话进行总结
- `optimizeUserInputPrompt`: 优化用户对话输入框提示词

The `source` field must always be one of:

- `systemBuiltIn`: 系统内置提示词
- `userCustom`: 用户自定义提示词

## Built-In Templates

The first version ships with two system built-in templates:

1. `归档对话总结`
   - Type: 对归档对话进行总结
   - System prompt: asks Codex to summarize an archived conversation into reusable archive material, preserving goals, decisions, completed work, verification, risks, and next actions.
   - User prompt: optional default task instruction.

2. `优化输入框提示词`
   - Type: 优化用户对话输入框提示词
   - System prompt: asks Codex to rewrite user input into a clearer, more actionable Codex request.
   - User prompt: optional default task instruction.

System built-in templates:

- Cannot be created by the user.
- Cannot be modified.
- Cannot be deleted.
- Can be selected and viewed.
- Can be copied into a new user custom template.

When a built-in template is selected, every field in the detail pane is disabled and visually greyed out.

## User Custom Templates

User custom templates:

- Can be created.
- Can be edited.
- Can be copied.
- Can be deleted after confirmation.
- Must have a non-empty name.
- Must have exactly one type.
- Must have a non-empty system prompt.
- May have an empty user prompt.
- May have an empty note.

Creating a template starts a user custom draft with:

- Empty name.
- Required type defaulting to the currently selected type filter when exactly one type filter is active; otherwise default to 对归档对话进行总结.
- Empty system prompt.
- Empty user prompt.
- Empty note.

Copying any template creates a user custom draft with the same type, system prompt, user prompt, and note. The copied name should append a short suffix such as `副本`.

## UI Layout

The component uses a two-pane Settings layout.

## Entry Point

The first implementation must add a visible prompt manager entry instead of only creating an unreachable settings view.

Entry behavior:

- Add a gear-shaped Settings button to the main workbench top strip, near the existing pin control.
- The button opens a Settings window or panel.
- The Settings surface defaults to the prompt template manager page in the first version.
- The button uses the label `设置` and accessibility text such as `打开设置`.
- The entry does not apply any template, start a Codex run, or change the active conversation.

If a broader Settings navigation exists later, prompt templates should appear as a `提示词模板` Settings section. In the first version, it is acceptable for the Settings surface to contain only the prompt template manager.

Left pane:

- Title: `提示词模板`.
- Add button for creating a user custom template.
- Search field.
- Source filter.
- Type filter.
- Template list.

Right pane:

- Selected template title.
- Contextual action buttons.
- Detail fields.
- Save/discard footer for editable templates.

The detail pane must not show a `source` field. Source is list metadata only. If a selected template is editable, it is necessarily a user custom template. If a selected template is system built-in, the detail fields are disabled.

## Left Pane Behavior

### Search

Search matches:

- Name.
- Note.
- System prompt.
- User prompt.

Search filters the visible list only. It does not modify the selected template.

### Source Filter

The source filter is a single-select segmented control:

- 全部
- 系统内置
- 用户自定义

Selecting `全部` shows both system built-in and user custom templates.

### Type Filter

The type filter is a multi-select control. It contains two checkbox-style options:

- 归档总结
- 优化输入

Both can be selected at the same time. One can be selected alone. If neither type is selected, the list treats that as no type filter and shows all types.

### Template Rows

Each row shows:

1. Template name.
2. Type line.
3. Source line.

The row order is:

1. System built-in templates first.
2. User custom templates after built-ins, ordered by `updatedAt` descending.

Within filtered results, the active selected row is visually highlighted.

## Right Pane Behavior

### Header

When a system built-in template is selected:

- Show a short read-only explanation.
- Show `复制为用户模板`.
- Do not allow direct editing.

When a user custom template is selected:

- Show editable state.
- Show `复制`.
- Show `删除`.

### Fields

The detail pane shows these fields in order:

1. 名称
   - Required text field.
2. 类型
   - Required dropdown single-select.
   - Options:
     - 对归档对话进行总结
     - 优化用户对话输入框提示词
   - Disabled for system built-in templates.
   - Enabled for user custom templates.
3. 系统提示词
   - Required multiline editor.
4. 用户提示词
   - Optional multiline editor.
5. 说明
   - Optional text field.

The right pane does not show source because source is not user-editable in this view.

### Save State

For system built-in templates:

- All fields are greyed out.
- Save and discard controls are visible but disabled.
- Copy is the only available transformation.

For user custom templates:

- Editing any field creates a dirty state.
- Save writes the template.
- Discard reverts the draft to the last saved state.
- Switching templates or closing Settings with unsaved changes prompts the user to save, discard, or cancel.

## Validation

Validation runs before save:

- Name cannot be empty after trimming whitespace.
- Type must be selected.
- System prompt cannot be empty after trimming whitespace.
- User prompt may be empty.
- Note may be empty.

Validation errors stay local to the prompt template manager. They should not create workbench conversation errors or execution events.

## Architecture

Core owns template models, validation, filtering, sorting, and persistence-facing repository protocols.

App owns Settings presentation, SwiftUI views, AppKit window integration, and user interaction state such as dirty drafts and confirmation prompts.

Proposed core units:

- `PromptTemplate`: persisted model.
- `PromptTemplateSource`: built-in or user custom.
- `PromptTemplateType`: archive summary or prompt optimization.
- `PromptTemplateDraft`: editable working copy.
- `PromptTemplateValidation`: pure validation rules.
- `PromptTemplateLibrary`: combines built-ins and persisted user templates, then applies search, source filter, type filters, and sorting.
- `PromptTemplateRepository`: persistence interface for user custom templates.

Built-in templates should be defined in code or a bundled resource and merged with persisted user custom templates at load time. Built-ins should not be stored as editable database rows.

Persistence should use a new SQLite table for user custom templates only. The table needs to store id, type, name, system prompt, user prompt, note, created timestamp, and updated timestamp. The schema migration must preserve existing project, conversation, archive, memory, and attachment data.

## Data Flow

1. Settings opens the prompt template manager.
2. App asks core for the prompt template library.
3. Core returns built-in templates plus persisted user custom templates.
4. App applies the current search, source filter, and type filters through core filtering logic.
5. User selects a template.
6. App creates a detail draft for the selected template.
7. If the template is built-in, the draft is read-only and fields are disabled.
8. If the template is user custom, fields are editable.
9. Save validates the draft.
10. Valid user custom drafts are persisted through `PromptTemplateRepository`.
11. The library reloads or updates in memory and the list refreshes.

## Error Handling

- Failed initial load: show a local error in Settings and keep the manager visible with an empty or stale list if available.
- Failed save: keep the dirty draft and show a local error.
- Failed delete: keep the template visible and show a local error.
- Failed copy: leave the source template selected and show a local error.
- Validation failure: keep focus in the editor and show field-level feedback.
- Empty search results: show an empty state in the list pane.
- Deleted selected template: select the next visible template, otherwise show an empty detail state.

## Testing Targets

Core tests:

- Built-in templates are present and read-only.
- User custom templates can be validated.
- Empty name fails validation.
- Missing type fails validation.
- Empty system prompt fails validation.
- Empty user prompt passes validation.
- Source filtering works for all, built-in, and user custom.
- Type filtering supports one selected type, both selected types, and no selected types.
- Search matches name, note, system prompt, and user prompt.
- Sorting places built-ins before user custom templates and sorts custom templates by updated time.
- Copying a built-in creates a user custom draft.

App-level smoke checks:

- The main workbench exposes a Settings entry button.
- Opening Settings from the entry shows the prompt template manager.
- The Settings pane renders a two-pane layout.
- Left type filter is multi-select.
- Right type field is a required dropdown single-select.
- System built-in selection greys out all detail fields.
- User custom selection enables detail fields.
- Unsaved edits prompt before switching or closing.
- Delete requires confirmation.

## Success Criteria

- A user can inspect built-in prompt templates without accidentally editing them.
- A user can create, edit, copy, and delete custom prompt templates.
- The system prompt is always required.
- The user prompt is optional.
- Type filtering in the list supports multi-select.
- The template type field in the detail pane is a required dropdown single-select.
- The user can reach the manager from the main workbench Settings entry.
- The manager remains independent from all runtime Codex flows.
