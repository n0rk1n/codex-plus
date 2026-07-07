import SwiftUI

struct AppMultilineTextField: View {
    let placeholder: String
    @Binding var text: String
    var fontSize: CGFloat = 14
    var foregroundColor: Color = .primary
    var placeholderColor: Color = .secondary
    var lineLimit: ClosedRange<Int>
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(text: $text, axis: .vertical) {
            Text(placeholder)
                .foregroundStyle(placeholderColor)
        }
        .textFieldStyle(.plain)
        .font(.system(size: fontSize))
        .foregroundStyle(foregroundColor)
        .lineLimit(lineLimit)
        .onSubmit(onSubmit)
    }
}
