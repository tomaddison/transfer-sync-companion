import SwiftUI

/// A dark-themed dropdown menu that matches the app's UI.
/// Uses a popover instead of native NSMenu for full styling control.
struct DarkMenu<Label: View, Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.vertical, 6)
            .frame(minWidth: 180)
            .background(Color.companionCard)
        }
    }
}

/// A menu item row for use inside DarkMenu.
struct DarkMenuItem: View {
    let title: String
    let icon: String?
    var iconColor: Color = .white
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(isDestructive ? Color.companionDestructive : iconColor)
                        .frame(width: 16)
                }
                Text(title)
                    .font(Font.companion(size: 13))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A non-interactive text row for use inside DarkMenu (e.g. user info).
struct DarkMenuText: View {
    let text: String
    var font: Font = Font.companion(size: 13)
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
    }
}

struct DarkMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
    }
}
