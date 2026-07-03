import AppKit

@MainActor
struct ActiveScreenProvider {
    func activeScreen() -> NSScreen? {
        if let screen = NSApp.keyWindow?.screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}
