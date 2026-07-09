import CodexPlusCore
import SwiftUI

struct CompressionHistoryInspectorView: View {
    let presentation: ConversationTimelineCompressionPresentation
    let selectedRoundID: UUID?
    let onRestoreOriginal: (UUID) -> Void
    let onRollback: (UUID) -> Void
    let onContinueCompression: ([UUID]) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(CodexColors.surfaceDivider)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let selectedRound {
                        selectedSummary(selectedRound)
                    } else {
                        emptySelection
                    }

                    markerList
                    historyList
                }
                .padding(14)
            }
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, maxHeight: .infinity)
        .background(CodexColors.surfaceSubtleWeak)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(CodexTypography.menuPrimary)
                .foregroundStyle(.secondary)

            Text("压缩历史")
                .font(CodexTypography.sectionTitle)

            Spacer(minLength: 8)

            CodexButton(rule: .toolbarIconCircle, help: "关闭历史", action: onClose) {
                Image(systemName: "sidebar.right")
                    .font(CodexTypography.tinyControlLabel)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func selectedSummary(_ round: ConversationRoundPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(round.status?.label ?? "原文发送", systemImage: symbolName(for: round.boundary?.kind))
                .font(CodexTypography.statusBar)

            if let joinedRelationship = round.joinedRelationship, joinedRelationship.relatedRoundIDs.count > 1 {
                Text("这段内容和相邻 \(joinedRelationship.relatedRoundIDs.count - 1) 轮一起形成当前拼接压缩版本。")
                    .font(CodexTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("当前窗口仍显示原文；发送给模型时使用最后一个活动版本。")
                    .font(CodexTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            selectedActionGroup(for: round)
        }
    }

    private func selectedActionGroup(for round: ConversationRoundPresentation) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                selectedActionButtons(for: round)
            }

            VStack(alignment: .leading, spacing: 8) {
                selectedActionButtons(for: round)
            }
        }
    }

    @ViewBuilder
    private func selectedActionButtons(for round: ConversationRoundPresentation) -> some View {
        CodexButton(rule: .formHeaderCapsule, help: "恢复这一轮的原文版本", action: {
            onRestoreOriginal(round.roundID)
        }) {
            Label("恢复原文", systemImage: "arrow.uturn.backward")
                .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        CodexButton(rule: .formHeaderCapsule, help: "继续压缩当前活动内容", action: {
            onContinueCompression(continueCompressionRoundIDs(for: round))
        }) {
            Label("继续压缩", systemImage: "arrow.down.right.and.arrow.up.left.circle")
                .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptySelection: some View {
        Text("选择时间线中的压缩标记查看这一段的历史。")
            .font(CodexTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var markerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前活动标记")
                .font(CodexTypography.captionStrong)
                .foregroundStyle(.secondary)

            ForEach(markedRounds) { round in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(round.id == selectedRoundID ? Color.accentColor : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(round.status?.label ?? "原文发送")
                            .font(CodexTypography.statusBar)

                        Text(detailText(for: round))
                            .font(CodexTypography.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("版本记录")
                .font(CodexTypography.captionStrong)
                .foregroundStyle(.secondary)

            if selectedVersionHistory.isEmpty {
                Text("这一轮还没有压缩、修改、失败或回滚记录。")
                    .font(CodexTypography.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(selectedVersionHistory) { item in
                    versionHistoryRow(item)
                }
            }
        }
    }

    private func versionHistoryRow(_ item: CompressionVersionHistoryPresentation) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(historyColor(for: item))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.label)
                        .font(CodexTypography.statusBar)

                    Text(item.statusLabel)
                        .font(CodexTypography.caption2)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)
                }

                Text(item.operationLabel)
                    .font(CodexTypography.caption2)
                    .foregroundStyle(.secondary)

                if let providerSummary = item.providerSummary {
                    Label(providerSummary, systemImage: "cpu")
                        .font(CodexTypography.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let inputSummary = item.inputSummary {
                    Text(inputSummary)
                        .font(CodexTypography.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(CodexTypography.caption2)
                        .foregroundStyle(CodexColors.stateFailed)
                        .lineLimit(3)
                }

                rollbackAction(for: item)
            }
        }
        .padding(.vertical, 6)
    }

    private func rollbackAction(for item: CompressionVersionHistoryPresentation) -> some View {
        CodexButton(
            rule: .formHeaderCapsule,
            isDisabled: item.isActive || item.isFailed || item.isTombstoned,
            help: "回滚到此版本",
            action: { onRollback(item.id) }
        ) {
            Label("回滚到此版本", systemImage: "clock.arrow.circlepath")
                .labelStyle(.titleAndIcon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedRound: ConversationRoundPresentation? {
        guard let selectedRoundID else {
            return nil
        }
        return presentation.rounds.first { $0.roundID == selectedRoundID }
    }

    private var markedRounds: [ConversationRoundPresentation] {
        presentation.rounds.filter { $0.status != nil || $0.boundary != nil || $0.joinedRelationship != nil }
    }

    private var selectedVersionHistory: [CompressionVersionHistoryPresentation] {
        guard let selectedRoundID else {
            return presentation.versionHistory
        }
        return presentation.versionHistoryByRoundID[selectedRoundID] ?? []
    }

    private func detailText(for round: ConversationRoundPresentation) -> String {
        if let joinedRelationship = round.joinedRelationship, joinedRelationship.relatedRoundIDs.count > 1 {
            return "拼接 \(joinedRelationship.relatedRoundIDs.count) 轮"
        }
        if round.isDimmed {
            return "原文淡化显示，不参与模型输入"
        }
        return "原文可见，活动版本参与模型输入"
    }

    private func symbolName(for kind: CompressionBoundaryPresentation.Kind?) -> String {
        switch kind {
        case .edited:
            return "pencil.line"
        case .compressed:
            return "arrow.down.right.and.arrow.up.left"
        case .joined:
            return "point.3.connected.trianglepath.dotted"
        case .excluded:
            return "eye.slash"
        case .failed:
            return "exclamationmark.triangle"
        case nil:
            return "text.bubble"
        }
    }

    private func historyColor(for item: CompressionVersionHistoryPresentation) -> Color {
        if item.isFailed {
            return CodexColors.stateFailed
        }
        if item.isTombstoned {
            return Color.secondary.opacity(0.45)
        }
        if item.isActive {
            return Color.accentColor
        }
        return Color.secondary.opacity(0.35)
    }

    private func continueCompressionRoundIDs(for round: ConversationRoundPresentation) -> [UUID] {
        if let joinedRelationship = round.joinedRelationship, !joinedRelationship.relatedRoundIDs.isEmpty {
            return joinedRelationship.relatedRoundIDs
        }
        return [round.roundID]
    }
}
