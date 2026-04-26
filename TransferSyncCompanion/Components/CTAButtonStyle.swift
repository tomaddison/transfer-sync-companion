import SwiftUI

struct CTAButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.companion(size: 14, weight: .regular))
            .foregroundStyle(CompanionTheme.ctaForeground)
            .frame(maxWidth: .infinity)
            .frame(height: CompanionTheme.ctaHeight)
            .padding(.horizontal, CompanionTheme.ctaHorizontalPadding)
            .background(CompanionTheme.ctaBackground, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1.0) : 0.5)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == CTAButtonStyle {
    static var cta: CTAButtonStyle { CTAButtonStyle() }
}
