import SwiftUI

struct GhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var iconSize: CGFloat? = nil
    var padding: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            iconSize: iconSize,
            padding: padding
        ) {
            configuration.label
        }
    }
}

private struct GhostButtonBody<Label: View>: View {
    let isPressed: Bool
    let isEnabled: Bool
    let iconSize: CGFloat?
    let padding: CGFloat
    @ViewBuilder var label: () -> Label

    @State private var isHovering = false

    var body: some View {
        sizedLabel
            .background {
                RoundedRectangle(cornerRadius: CompanionTheme.ghostCornerRadius, style: .continuous)
                    .fill(backgroundColor)
            }
            .contentShape(RoundedRectangle(cornerRadius: CompanionTheme.ghostCornerRadius, style: .continuous))
            .opacity(isEnabled ? 1.0 : 0.5)
            .onHover { hovering in
                isHovering = hovering
            }
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
    }

    @ViewBuilder
    private var sizedLabel: some View {
        if let iconSize {
            label()
                .frame(width: iconSize, height: iconSize)
        } else {
            label()
                .padding(padding)
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .clear }
        if isPressed { return Color.companionGhostPressed }
        if isHovering { return Color.companionGhostHover }
        return .clear
    }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { GhostButtonStyle() }

    static func ghost(padding: CGFloat) -> GhostButtonStyle {
        GhostButtonStyle(padding: padding)
    }

    static var ghostIcon: GhostButtonStyle {
        GhostButtonStyle(iconSize: CompanionTheme.ghostIconSize)
    }

    static func ghostIcon(size: CGFloat) -> GhostButtonStyle {
        GhostButtonStyle(iconSize: size)
    }
}
