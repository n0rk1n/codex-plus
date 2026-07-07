import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class SettingsPanelController {
    private let panelFactory: PanelFactory
    private weak var panelDelegate: NSWindowDelegate?
    private let repository: any PromptTemplateRepository

    private var panel: GlassPanel?

    init(
        panelFactory: PanelFactory,
        panelDelegate: NSWindowDelegate?,
        repository: any PromptTemplateRepository
    ) {
        self.panelFactory = panelFactory
        self.panelDelegate = panelDelegate
        self.repository = repository
    }

    func show() {
        let frame = panel?.frame ?? Self.defaultFrame()
        let panel = panel ?? panelFactory.makePanel(frame: frame, delegate: panelDelegate)
        panel.hasShadow = false
        panel.setFrame(frame, display: true)
        panel.contentView = SettingsHostingView(
            rootView: PromptTemplateManagerView(repository: repository)
        )
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        movedPanel === panel
    }

    static func defaultFrame() -> NSRect {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSRect(x: 120, y: 120, width: 980, height: 620)
        }

        let width = min(CGFloat(1100), visibleFrame.width > 96 ? visibleFrame.width - 96 : visibleFrame.width)
        let height = min(CGFloat(700), visibleFrame.height > 96 ? visibleFrame.height - 96 : visibleFrame.height)

        return NSRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2),
            width: width,
            height: height
        )
    }
}

private final class SettingsHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparentBacking()
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureTransparentBacking() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.shadowOpacity = 0
        layer?.shadowColor = NSColor.clear.cgColor
    }
}
