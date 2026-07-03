# Native Liquid Glass Design

## Goal

Upgrade the app's glass surfaces from a custom `.ultraThinMaterial` treatment to Apple's native macOS 26 Liquid Glass APIs.

The project will intentionally require macOS 26 or newer. There is no compatibility fallback for macOS 14 or 15 in this change.

## Current State

Most visible panels and tiles use `LiquidGlassContainer`, which currently draws a rounded rectangle filled with `.ultraThinMaterial` and a white stroke. `SideEdgeAffordanceView` repeats the same material-and-stroke pattern directly.

The local SDK exposes SwiftUI's macOS 26 glass APIs:

- `View.glassEffect(_:in:)`
- `Glass`
- `GlassEffectContainer`

AppKit also exposes `NSGlassEffectView` and `NSGlassEffectContainerView`, but the current app surfaces are already SwiftUI-first, so the SwiftUI path is the narrowest native integration.

## Approach

Use SwiftUI native Liquid Glass as the primary implementation.

Update `Package.swift` to require macOS 26. Then update `LiquidGlassContainer` so it keeps the existing project-level abstraction while replacing the custom material background with:

- `.glassEffect(.regular, in: RoundedRectangle(cornerRadius:style:))`

This preserves existing call sites while changing the underlying rendering to the system glass effect.

Wrap the compact dashboard tile row in `GlassEffectContainer` so the system can batch and merge nearby glass surfaces. Convert the side edge affordance capsule to `glassEffect` as well.

## Components

- `Package.swift`: raise the platform minimum to macOS 26.
- `LiquidGlassContainer`: use SwiftUI `glassEffect` with the existing rounded rectangle shape.
- `CompactEntryView`: wrap the dashboard tile row with `GlassEffectContainer`.
- `SideEdgeAffordanceView`: replace the direct `.ultraThinMaterial` capsule fill with `glassEffect`.

## Out of Scope

- Bridging SwiftUI content into AppKit `NSGlassEffectView`.
- Runtime fallback for older macOS versions.
- Redesigning tile layout, sizing, colors, copy, or conversation behavior.
- Reworking buttons to `.buttonStyle(.glass)` unless a later pass needs control-specific glass styling.

## Testing

Run `swift build` to verify the macOS 26 APIs compile with the package settings.

Run the existing core test executable to confirm unrelated dashboard ordering and drag behavior still passes.

If the GUI can be run locally, do a visual smoke test that the compact dashboard, prompt entry, conversation surfaces, and side edge affordance render with native glass and remain readable.
