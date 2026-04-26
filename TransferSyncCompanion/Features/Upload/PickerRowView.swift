import SwiftUI

struct PickerRowView: View {
    let icon: String
    let title: String
    let hasChevron: Bool

    init(icon: String, title: String, hasChevron: Bool = true) {
        self.icon = icon
        self.title = title
        self.hasChevron = hasChevron
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.companionMutedText)
                .frame(width: 24, height: 18)

            Text(title)
                .font(Font.companion(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.companionMutedText.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Color.clear)
    }
}
