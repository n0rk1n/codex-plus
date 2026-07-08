# Control Rules Design

## Goal

Codex Plus app-owned controls must be built through named control rules instead of page-local style and interaction code. A rule may have only one current caller, but it still must exist as a named abstraction before a view can use that visual or interaction behavior.

The first implementation covers buttons, text inputs, multiline editors, pickers, and toggle-style selectors in `Sources/CodexPlusApp`.

## Problem

The current app has useful shared pieces, such as `codexCircularButtonHitArea()` and `AppMultilineTextField`, but page views still compose styles and interactions directly. Examples include local button builders, direct `.buttonStyle(.plain)`, direct `.textFieldStyle(...)`, direct `.pickerStyle(...)`, local `readOnlyInputArea` overlays, and repeated `glassEffect`/padding/mask combinations.

That makes similar controls drift over time. It also lets new controls bypass decisions that should be consistent across the app: hit area shape, visual style, disabled behavior, read-only notices, and accessibility labels.

## Scope

Covered controls:

- App-owned SwiftUI `Button` controls.
- App-owned single-line `TextField` controls.
- App-owned multiline text inputs and editors.
- App-owned `Picker` controls.
- App-owned `Toggle` controls used as selectors.

Out of scope:

- Alert buttons declared inside `.alert`.
- AppKit `NSAlert` buttons.
- `Menu` menu items and system-owned picker menu rows.
- Core-layer models, persistence, command execution, and non-UI behavior.

## Required Rule

Page views may declare control intent, data, and actions. Page views may not own control styling or control-specific interaction mechanics.

Allowed in page views:

- Passing text, icons, bindings, disabled state, help text, accessibility labels, and action closures into a control abstraction.
- Choosing an existing named rule such as `.toolbarCapsule`, `.composerIcon`, `.searchField`, `.menuRequired`, or `.filterToggle`.
- Defining business behavior around a control, such as which action runs when a template is selected.

Not allowed in page views:

- Direct `.buttonStyle(.plain)` for app-owned buttons.
- Direct `.textFieldStyle(...)` for app-owned text inputs.
- Direct `.pickerStyle(...)` for app-owned pickers.
- Direct `.toggleStyle(...)` for app-owned toggle selectors.
- Direct `.glassEffect(...)`, `.mask(...)`, `.contentShape(...)`, or hit-area modifiers used to define an app control.
- Page-local control interaction wrappers such as `readOnlyInputArea`.

If a control needs unique behavior, add a named rule for it. The name should describe the UI contract, not only the current caller.

## Architecture

Add an app-layer control system under `Sources/CodexPlusApp/Views`. Keep it in the app target because it depends on SwiftUI and app-specific visual language.

The control system has two parts:

- Rule types: small enums or structs that define the supported visual and interaction contracts.
- Control wrappers: SwiftUI views that apply the rule and expose only the data/actions a page is allowed to provide.

The existing `ButtonHitAreaModifier` should be folded into the rule implementation or kept as a private implementation detail. Pages should no longer call hit-area helpers directly after migration.

## Components

`CodexControlRules.swift`

- Defines rule names for buttons, text fields, editors, pickers, and toggle selectors.
- Rule names are stable contracts used by view code and source guardrail tests.
- Rules encode hit area, base style, visual shape, sizing, and read-only interaction behavior where applicable.

`CodexButton.swift`

- Wraps app-owned buttons.
- Applies the selected button rule, including plain style, glass/background, padding, mask, hit area, help text, accessibility label, disabled opacity, and role styling when needed.
- Supports icon-only, label, row, capsule, card, and text-link variants that currently exist in the app.

`CodexTextField.swift`

- Wraps app-owned single-line text inputs.
- Applies search, inline composer, and form-field rules.
- Handles read-only notice behavior through a shared rule instead of page-local overlays.

`CodexMultilineTextField.swift` and `CodexMultilineTextEditor.swift`

- Keep the behavior of the existing `AppMultilineTextField` and `AppMultilineTextEditor`, but expose them as rule-based controls.
- Keep multiline limits in `MultilineInputDefaults`.
- Preserve AppKit text view behavior for long prompt-template fields.

`CodexPicker.swift`

- Wraps app-owned picker controls.
- Covers segmented filters and required menu pickers used in the prompt-template manager.
- Keeps labels hidden or visible according to the named rule instead of allowing page views to set that directly.

`CodexToggleSelector.swift`

- Wraps toggle-style filter chips.
- Covers the prompt-template type filter and any future selector chips that need the same interaction contract.

`CodexReadOnlyNotice.swift`

- Provides the shared read-only interaction used by system prompt-template fields.
- Shows one centered notice for three seconds.
- Prevents duplicate notices while one is already visible.
- Keeps exact copy: `系统内置提示词为只读内容。如需修改，请先创建用户自定义提示词。`

## Initial Rule Set

Button rules:

- `.toolbarCapsule`: top strip text/icon actions such as new conversation and archive.
- `.toolbarIconCircle`: top strip icon actions such as settings and pin.
- `.composerIconCircle`: composer send, stop, and prompt optimization icon buttons.
- `.workspaceCapsule`: composer workspace picker.
- `.workspaceClear`: composer workspace clear control.
- `.rowRectangle`: archived rows and technical event rows.
- `.rowRounded(cornerRadius: CGFloat)`: prompt-template rows and draft workspace rows.
- `.cardRounded(cornerRadius: CGFloat)`: project cards and dashboard tiles.
- `.formHeaderCapsule`: prompt-template header actions such as copy, set default, delete.
- `.formFooterCapsule`: prompt-template footer actions such as save and discard.
- `.inlineTextLink`: lightweight inline links such as the archive restore jump text.

Input rules:

- `.composerInline`: one-line composer input.
- `.searchField`: archive and prompt-template search inputs.
- `.formField`: prompt-template name input.
- `.multilinePrompt`: compact prompt and follow-up inputs.
- `.multilineNote`: prompt-template note input.
- `.longPromptEditor`: prompt-template system and user prompt editors.

Picker and selector rules:

- `.segmentedFilter`: source filter segmented picker.
- `.requiredMenu`: prompt-template type picker.
- `.filterToggle`: prompt-template type filter chips.

These are the only initial rules. New UI work adds a new rule only when an existing rule does not match the control contract.

## Migration Strategy

Migrate source files in focused groups:

1. Add source guardrail tests that fail on page-owned control style and interaction code.
2. Add the rule types and wrappers.
3. Migrate buttons while preserving existing layout, copy, disabled states, help text, and accessibility labels.
4. Migrate text inputs and editors while preserving line limits, focus behavior, submit behavior, and read-only behavior.
5. Migrate pickers and toggle selectors.
6. Remove now-obsolete page-local control helpers after their callers move to the rule layer.

Existing dirty changes in `PromptTemplateManagerView.swift` around read-only notices should be preserved and lifted into the shared read-only notice rule rather than reverted.

## Testing

Use source guardrail tests because this project already uses source-level tests for SwiftUI view constraints.

Guardrails should check:

- App-owned views outside the control-rule files do not contain direct `.buttonStyle(.plain)`.
- App-owned views outside the control-rule files do not contain direct `.textFieldStyle(`.
- App-owned views outside the control-rule files do not contain direct `.pickerStyle(`.
- App-owned views outside the control-rule files do not contain direct `.toggleStyle(`.
- App-owned views outside the control-rule files do not contain direct `.glassEffect(`, `.contentShape(`, or page-local read-only overlay helpers for controls.
- Alert and AppKit alert files remain exempt.
- The rule files define every initial rule name listed in this spec.
- Prompt-template read-only controls use the shared read-only notice rule and keep the exact Chinese copy.

Verification commands:

- `swift run CodexPlusCoreLegacyTests`
- `swift build`
- `git diff --check`

Manual verification remains useful after implementation:

- Launch the app with `swift run CodexPlusApp`.
- Inspect top strip actions, composer controls, prompt-template manager controls, archive rows, and read-only system template fields.
- Confirm controls still fit their containers and click across their visible bounds.

## Risks

Over-abstracting every control into separate one-off components would create noise. This design avoids that by naming rules, not creating a component per screen concept.

Wrapping system controls too aggressively can break native macOS behavior. This design keeps alert buttons, AppKit alert buttons, and menu rows outside the rule layer.

Source guardrails can be too broad if they scan generated strings or rule implementation files. Tests should use allowlists for rule files and documented system-control exceptions.

## Success Criteria

- Every app-owned control touched by this migration declares a named rule.
- Page views no longer assemble app control style or control-specific interaction behavior.
- Existing visual behavior and Chinese copy are preserved unless a rule explicitly changes them.
- Source guardrails fail when a page adds a new direct app-owned control style.
- Build and project-specific legacy tests pass after implementation.
