import QuickAIDashboardCore
import SwiftUI

struct CompactEntryView: View {
    let batteryStatus: BatteryStatus
    let onSubmit: (String) -> Void

    @FocusState private var isPromptFocused: Bool
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                BatteryTileView(status: batteryStatus)
            }
            .frame(maxWidth: .infinity)

            LiquidGlassContainer(cornerRadius: 24) {
                TextField("Ask Codex...", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...3)
                    .focused($isPromptFocused)
                    .onSubmit(submitPrompt)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
        }
        .padding(18)
        .onAppear {
            isPromptFocused = true
        }
    }

    private func submitPrompt() {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        onSubmit(trimmedPrompt)
        prompt = ""
    }
}
