import CodexPlusCore
import SwiftUI

struct CompressionHistoryInspectorView: View {
    let presentation: ConversationTimelineCompressionPresentation
    let selectedRoundID: UUID?
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

                    versionList
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
        }
    }

    private var emptySelection: some View {
        Text("选择时间线中的压缩标记查看这一段的历史。")
            .font(CodexTypography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var versionList: some View {
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

    private var selectedRound: ConversationRoundPresentation? {
        guard let selectedRoundID else {
            return nil
        }
        return presentation.rounds.first { $0.roundID == selectedRoundID }
    }

    private var markedRounds: [ConversationRoundPresentation] {
        presentation.rounds.filter { $0.status != nil || $0.boundary != nil || $0.joinedRelationship != nil }
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
}
