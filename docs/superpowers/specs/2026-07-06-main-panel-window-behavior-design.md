# Main Panel Window Behavior Design

## Goal

Add two focused behaviors to the side conversation panel, which is the app's main window in the current implementation:

- While the user drags the main panel, snap the panel center to the active screen's horizontal midline when it comes near that midline.
- When the main panel is the current key or main window, let the Escape key hide the main panel.

## Scope

This change applies to the `SidePanelController` panel only. The compact prompt panel keeps its existing drag and Escape behavior. This change does not alter conversation state, archiving, pinning, run cancellation, or the side-edge affordance.

## Approach

Reuse the existing compact-panel drag mechanics instead of adding a new window controller path. `DraggableHostingView` already supports manual window dragging for the compact prompt. It should gain a second manual drag mode for the side panel that uses the same `CompactPanelSnapPolicy.snappedFrame(for:in:)` midline behavior.

`SidePanelController.installContent` will set this new drag mode on the hosting view before installing it as the panel content view. Because manual dragging drives `window.setFrame(...)` during the drag, the user gets live snap feedback instead of a jump after mouse-up.

The Escape monitor in `SidePanelController` will keep using `CompactEntryDismissPolicy.shouldDismissForKeyDown(keyCode:)`, but it will also require the side panel to be visible and either `isKeyWindow` or `isMainWindow`. That makes Escape close only the active main panel instead of any visible side panel.

## Components

- `DraggableHostingView.WindowDragMode`: add a side-panel manual drag mode.
- `DraggableHostingView`: share the existing drag loop between compact prompt and side panel modes.
- `SidePanelController`: install the side-panel drag mode and tighten Escape dismissal to the current window.
- `CompactPanelSnapPolicy`: remain the single source of truth for center-line snapping.

## Data Flow

1. The user presses and drags on the side panel background.
2. `DraggableHostingView` calculates the proposed frame from the original frame and mouse delta.
3. The view chooses the visible screen that most overlaps the proposed frame.
4. `CompactPanelSnapPolicy` returns either the proposed frame or a frame centered on the screen midline.
5. The window frame updates immediately; crossing into the snap zone triggers one alignment haptic.
6. `WindowCoordinator.windowDidMove` still records the final custom or attached placement after AppKit posts movement notifications.

## Error Handling

If no window or screen is available during a drag, the drag path returns without changing placement. Existing panel visibility and close behavior stays unchanged. Escape dismissal remains non-destructive: it hides the panel and does not stop runs or archive conversations.

## Testing

Add the smallest checks that catch regressions:

- A Core geometry assertion showing a main-panel-sized frame snaps to the active screen midline.
- A text-level app smoke check confirming `SidePanelController` installs the side-panel drag mode.
- A text-level app smoke check confirming Escape dismissal requires `isKeyWindow` or `isMainWindow`.

Run:

- `swift run CodexPlusCoreTests`
- `swift build`
