import AppKit

@MainActor
struct PanelFactory {
    func makePanel(frame: NSRect, delegate: NSWindowDelegate?) -> GlassPanel {
        let panel = GlassPanel(contentRect: frame)
        panel.acceptsMouseMovedEvents = true
        panel.delegate = delegate
        return panel
    }
}
