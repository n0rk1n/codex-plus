# Button Hit Area Design

## Goal

Make Codex Plus self-drawn SwiftUI buttons respond across their full visible control area, not only on the icon or text inside the label.

## Problem

Many app controls use `Button` with `.buttonStyle(.plain)` and custom glass, padding, or background styling. In SwiftUI, a plain button's interactive area often follows the rendered label content unless a `contentShape` is applied at the right level. This creates repeated bugs where users must click the icon or text instead of the visual button surface.

## Scope

This change should cover app-owned self-drawn controls:

- toolbar buttons in `TopProjectStripView`
- composer send, stop, workspace picker, and clear controls
- prompt template manager sidebar, row, header, and footer controls
- archive rows and other custom plain buttons that visually present as rows, capsules, cards, or icon buttons
- dashboard tile buttons such as the Codex Desktop tile

This change should not alter system-owned controls:

- `Alert` buttons
- `Menu` and `Picker` controls
- `Toggle` controls using system styles
- AppKit `NSAlert` buttons

## Architecture

Add a small SwiftUI helper in the app layer, not the core layer. The helper exposes semantic modifiers for the common button shapes used by the app:

- circular icon buttons
- capsule text/icon buttons
- rectangular or rounded row/card buttons

Call sites keep their existing action ownership and visual layout. The shared helper only defines hit testing shape and keeps behavior local to SwiftUI views.

## Components

`ButtonHitAreaModifier.swift`

- Defines a generic modifier that applies `.contentShape(shape)`.
- Provides app-specific convenience methods such as `codexCircularButtonHitArea()`, `codexCapsuleButtonHitArea()`, and `codexRoundedButtonHitArea(cornerRadius:)`.
- Keeps names explicit so future buttons declare their visual hit target shape instead of relying on scattered ad hoc `.contentShape(...)` calls.

Existing view files

- Replace one-off hit area fixes with the shared modifier where the control is a custom plain button.
- Preserve existing visual styling, layout sizes, accessibility labels, help text, disabled states, and actions.

## Testing

Because this is SwiftUI view code, automated coverage should focus on source-level guardrails already used in this repository:

- add tests that assert important app-owned plain buttons opt into the shared hit area modifiers
- verify the project builds and test suite runs after the source changes

Manual verification after implementation should cover:

- clicking inside the empty/padded area of top strip buttons
- clicking the circular settings and pin buttons away from the icon glyph
- clicking the composer send/stop circular area away from the arrow/stop glyph
- clicking prompt template rows and header/footer capsules across their visual bounds

## Risks

Applying a shape too broadly can steal clicks from nested controls, especially project cards that contain menus. Those cases should use the smallest shape that matches the visual button and avoid changing `Menu`, `Picker`, `Toggle`, and alert controls.

Disabled-state behavior must remain unchanged: the hit area can be larger, but disabled buttons must still not perform their actions.
