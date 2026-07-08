import SwiftUI

enum CodexButtonRule {
    case toolbarCapsule
    case toolbarIconCircle
    case composerIconCircle
    case workspaceCapsule
    case workspaceClear
    case rowRectangle
    case rowRounded(cornerRadius: CGFloat)
    case cardRounded(cornerRadius: CGFloat)
    case formHeaderCapsule
    case formFooterCapsule
    case inlineTextLink
}

enum CodexTextFieldRule {
    case composerInline
    case searchField
    case formField
}

enum CodexMultilineTextRule {
    case multilinePrompt
    case multilineNote
    case longPromptEditor
}

enum CodexPickerRule {
    case segmentedFilter
    case requiredMenu
}

enum CodexToggleSelectorRule {
    case filterToggle
}

enum CodexReadOnlyNoticeRule {
    case promptTemplateSystemTemplate

    var message: String {
        switch self {
        case .promptTemplateSystemTemplate:
            return "系统内置提示词为只读内容。如需修改，请先创建用户自定义提示词。"
        }
    }
}

enum CodexControlHitShape {
    case rectangle
    case capsule
    case circle
    case rounded(cornerRadius: CGFloat)
}

extension View {
    @ViewBuilder
    func codexControlHitArea(_ shape: CodexControlHitShape) -> some View {
        switch shape {
        case .rectangle:
            contentShape(Rectangle())
        case .capsule:
            contentShape(Capsule(style: .continuous))
        case .circle:
            contentShape(Circle())
        case let .rounded(cornerRadius):
            contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func codexOptionalHelp(_ help: String?) -> some View {
        if let help {
            self.help(help)
        } else {
            self
        }
    }

    @ViewBuilder
    func codexOptionalAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            self.accessibilityLabel(label)
        } else {
            self
        }
    }

    @ViewBuilder
    func codexReadOnlyControlOverlay(_ handle: CodexReadOnlyNoticeHandle?) -> some View {
        overlay {
            if let handle, handle.isReadOnly {
                Color.clear
                    .codexControlHitArea(.rectangle)
                    .onTapGesture(perform: handle.show)
            }
        }
    }
}
