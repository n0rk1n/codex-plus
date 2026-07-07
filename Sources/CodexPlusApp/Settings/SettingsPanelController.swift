import AppKit
import CodexPlusCore
import SwiftUI

@MainActor
final class SettingsPanelController {
    private let panelFactory: PanelFactory
    private weak var panelDelegate: NSWindowDelegate?
    private let repository: any PromptTemplateRepository

    private var panel: GlassPanel?
    private lazy var store = PromptTemplateSettingsStore(repository: repository)

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
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.setFrame(frame, display: true)
        if panel.contentView == nil {
            panel.contentView = SettingsHostingView(
                rootView: PromptTemplateManagerView(store: store)
            )
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func recordMove(of movedPanel: GlassPanel) -> Bool {
        movedPanel === panel
    }

    func shouldClose(_ closingPanel: GlassPanel) -> Bool {
        guard closingPanel === panel else {
            return true
        }

        return confirmDirtyCloseIfNeeded()
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

    private func confirmDirtyCloseIfNeeded() -> Bool {
        guard store.isDirty else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保存未完成的修改？"
        alert.informativeText = "当前提示词模板有未保存修改。关闭设置前请选择保存、放弃或取消。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "放弃修改")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return store.save()
        case .alertSecondButtonReturn:
            store.discardChanges()
            return true
        default:
            return false
        }
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
