import SwiftUI

struct CodexReadOnlyNoticeHandle {
    let isReadOnly: Bool
    let show: () -> Void
}

struct CodexReadOnlyNoticeHost<Content: View>: View {
    let isReadOnly: Bool
    let rule: CodexReadOnlyNoticeRule
    @ViewBuilder let content: (CodexReadOnlyNoticeHandle) -> Content

    @State private var isShowingNotice = false
    @State private var noticeID = UUID()

    var body: some View {
        ZStack {
            content(
                CodexReadOnlyNoticeHandle(
                    isReadOnly: isReadOnly,
                    show: showNotice
                )
            )

            if isShowingNotice {
                CodexReadOnlyNoticeView(rule: rule)
            }
        }
        .onChange(of: isReadOnly) {
            if !isReadOnly {
                isShowingNotice = false
            }
        }
    }

    private func showNotice() {
        guard isReadOnly else {
            return
        }
        guard !isShowingNotice else {
            return
        }

        let currentID = UUID()
        noticeID = currentID
        withAnimation(.easeOut(duration: 0.16)) {
            isShowingNotice = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard noticeID == currentID else {
                return
            }
            withAnimation(.easeIn(duration: 0.2)) {
                isShowingNotice = false
            }
        }
    }
}

private struct CodexReadOnlyNoticeView: View {
    let rule: CodexReadOnlyNoticeRule

    var body: some View {
        Text(rule.message)
            .font(CodexTypography.menuPrimary)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, CodexSpacing.compactField)
            .padding(.vertical, CodexSpacing.contentInline)
            .background(CodexColors.readOnlyOverlay, in: RoundedRectangle(cornerRadius: CodexRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CodexRadius.badge, style: .continuous)
                    .stroke(CodexColors.surfaceStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
