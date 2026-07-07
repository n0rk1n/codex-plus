# Multiline Input Components Design

## Goal

Codex Plus should have one default way to render multiline text inputs. Existing prompt, follow-up, note, and prompt-template editors currently repeat styling and behavior locally. This change introduces shared app-level components so future multiline inputs use the same handling unless a screen has a specific reason to opt out.

## Current State

The app has several independent multiline implementations:

- `CompactEntryView` uses `TextField(text:axis: .vertical)` with local font, color, focus, submit, and `lineLimit(1...3)`.
- `ConversationView` and `ConversationDraftView` use similar vertical text fields with local `lineLimit(1...4)`.
- `PromptTemplateManagerView` uses a vertical `TextField` for the note field.
- `PromptTemplateManagerView` also defines a private `PromptTemplateMultilineEditor` based on `NSTextView` for large prompt-template bodies.

These should be consolidated without changing the visible layout more than necessary.

## Design

Add two reusable components under `Sources/CodexPlusApp/Views/Components/`:

1. `AppMultilineTextField`
   - Wraps SwiftUI `TextField` with `axis: .vertical`.
   - Accepts text binding, placeholder, line limit, font size, foreground color, optional placeholder color, disabled state, focus from the caller, and submit action.
   - Owns default `.textFieldStyle(.plain)`, app font defaults, and vertical multiline behavior.
   - Does not own enclosing chrome such as `LiquidGlassContainer`, buttons, padding, or workspace-specific actions.

2. `AppMultilineTextEditor`
   - Moves the existing `NSTextView` wrapper out of `PromptTemplateManagerView`.
   - Accepts text binding, font size, inset, and enabled state through SwiftUI environment.
   - Keeps the current plain-text, transparent-background, undo-enabled behavior.
   - Remains suitable for long-form prompt-template bodies.

## Migration Scope

Replace local multiline fields in:

- `CompactEntryView`
- `ConversationView`
- `ConversationDraftView`
- `PromptTemplateManagerView`

Keep `WorkbenchComposerView` as a single-line input for now because it currently uses `TextField(activePlaceholder, text:)` with `lineLimit(1)` and no vertical axis. If that composer becomes multiline later, it should use `AppMultilineTextField`.

## Non-Goals

- Do not redesign the composer chrome, send buttons, or Liquid Glass containers.
- Do not change prompt submission semantics.
- Do not introduce a new text editing model.
- Do not force long-form `NSTextView` behavior onto compact prompt fields.

## Testing

Add focused Swift tests for any pure configuration policy if introduced. Since SwiftUI visual modifiers are difficult to assert directly, the main automated verification is a full package test/build run. Manual verification should confirm:

- Compact prompt still accepts multiple lines up to its existing limit.
- Draft and follow-up prompt fields still submit correctly.
- Prompt-template system and user prompt editors still edit and scroll.
- Disabled prompt-template fields are not editable.
