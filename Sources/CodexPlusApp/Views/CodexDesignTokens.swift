import CodexPlusCore
import SwiftUI

enum CodexTypography {
    static let launcherSymbol = Font.system(size: 16, weight: .semibold)
    static let menuPrimary = Font.system(size: 13, weight: .semibold)
    static let menuPrimaryRegular = Font.system(size: 13, weight: .regular)
    static let caption = Font.caption
    static let caption2 = Font.caption2
    static let contentTitle = Font.system(size: 18, weight: .semibold)
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    static let microControl = Font.system(size: 12, weight: .semibold)
    static let statusBar = Font.caption.weight(.semibold)
    static let caption2Medium = Font.caption2.weight(.medium)
    static let statusBarValue = Font.system(size: 9, weight: .medium)
    static let usageMetricLabel = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let usageMetricValue = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let singleLineComposerInput = Font.system(size: 14)
    static let multilinePrompt = Font.system(size: 15)
    static let multilineNote = Font.system(size: 14)
    static let conversationFollowUpPrompt = Font.system(size: 14)
    static let multilineEditor = Font.system(size: 13)
    static let controlLabel = Font.system(size: 15, weight: .semibold)
    static let tinyControlLabel = Font.system(size: 14, weight: .semibold)
    static let compactBadge = Font.system(size: 11, weight: .semibold)
    static let compactTechnicalSummary = Font.system(size: 12)
    static let listEmptyStateTitle = Font.system(size: 22, weight: .medium)
    static let desktopTileFallbackSymbol = Font.system(size: 34, weight: .semibold)
    static let batteryPercentValue = Font.system(size: 27, weight: .semibold)
    static let batteryStateValue = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let restoreNoticeAction = Font.system(size: 13, weight: .medium)
    static let promptTemplateTitle = Font.system(size: 24, weight: .medium)
    static let promptTemplateMeta = Font.system(size: 16, weight: .semibold)
    static let messageBody = Font.system(size: 15)
    static let sectionHeader = Font.system(size: 20, weight: .semibold)
    static let panelHeader = Font.system(size: 28, weight: .medium)
    static let captionStrong = Font.caption.weight(.semibold)
}

enum CodexSpacing {
    static let contentInline: CGFloat = 12
    static let contentStack: CGFloat = 16
    static let compactInline: CGFloat = 14
    static let compactVertical: CGFloat = 7
    static let tightInline: CGFloat = 10
    static let compactField: CGFloat = 18
    static let tightVertical: CGFloat = 8
}

enum CodexRadius {
    static let card: CGFloat = 22
    static let panel: CGFloat = 24
    static let badge: CGFloat = 10
    static let dot: CGFloat = 7
}

enum CodexColors {
    static let secondaryText = Color.secondary
    static let launcherSymbol = Color.white
    static let launcherSurface = Color.white.opacity(0.06)
    static let usageNoData = Color.secondary
    static let stateIdle = Color.secondary
    static let stateRunning = Color.blue
    static let stateCompleted = Color.green
    static let stateFailed = Color.red
    static let stateStopped = Color.orange
    static let stateUnknown = Color.secondary
    static let statePrimary = Color.accentColor
    static let stateWarning = Color.yellow

    static let surfaceSelection = Color.accentColor.opacity(0.18)
    static let surfaceInactive = Color.primary.opacity(0.06)
    static let surfaceSubtle = Color.white.opacity(0.05)
    static let surfaceSubtleStrong = Color.white.opacity(0.10)
    static let surfaceSubtleWeak = Color.white.opacity(0.04)
    static let surfaceDivider = Color.white.opacity(0.08)
    static let surfaceStroke = Color.white.opacity(0.12)
    static let readOnlyOverlay = Color.black.opacity(0.9)

    static let compactEntryPromptIcon = Color.primary.opacity(0.78)
    static let compactEntryPromptForeground = Color.primary.opacity(0.86)
    static let compactEntryPromptPlaceholder = Color.secondary.opacity(0.88)
    static let compactEntryPlaceholderFill = Color.secondary.opacity(0.08)
    static let compactEntryPlaceholderStroke = Color.secondary.opacity(0.24)
    static let compactEntryPlaceholderOpacity = 0.9
}

enum CodexUsageColors {
    static let lowUsage = CodexUsageRingColor.lowUsageGreen.asColor
    static let midUsage = CodexUsageRingColor.midUsageYellow.asColor
    static let highUsage = CodexUsageRingColor.highUsageRed.asColor
    static let limitReached = CodexUsageRingColor.limitReachedGray.asColor
    static let inactive = CodexUsageRingColor.inactive.asColor
}

enum CodexPromptOptimizationVisuals {
    static func gradient(isOptimizing: Bool) -> [Color] {
        isOptimizing ? [.yellow, .cyan, .purple] : [.purple, .orange, .blue]
    }

    static func glowPrimaryOpacity(isOptimizing: Bool) -> Double {
        isOptimizing ? 0.45 : 0.15
    }

    static func glowSecondaryOpacity(isOptimizing: Bool) -> Double {
        isOptimizing ? 0.22 : 0.08
    }

    static var runningColor: Color {
        .yellow
    }

    static var glowSecondaryColor: Color {
        .cyan
    }
}

extension CodexUsageRingColor {
    var asColor: Color {
        Color(
            red: red,
            green: green,
            blue: blue,
            opacity: opacity
        )
    }
}

extension CodexUsageStatus {
    func color(for window: CodexUsageWindow) -> Color {
        guard percent(for: window) != nil else {
            return CodexColors.usageNoData
        }
        return ringColor(for: window).asColor
    }
}
