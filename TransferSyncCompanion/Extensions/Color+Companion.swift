import SwiftUI

extension Color {
    static let companionMain = Color(hex: 0x101012)
    static let companionCard = Color(hex: 0x1A191F)
    static let companionTabBar = Color(hex: 0x18171C)
    static let companionActiveTab = Color(hex: 0x302E38)
    static let companionPill = Color(hex: 0x25242C)
    static let companionMenu = Color(hex: 0x1A191F)

    static let companionMutedText = Color(hex: 0xB9B9BA)

    static let companionStatusGreen = Color(hex: 0x4ADE80)
    static let companionStatusRed = Color(hex: 0xEF4444)
    static let companionStatusAmber = Color(hex: 0xF59E0B)
    static let companionStatusBlue = Color(hex: 0x3B82F6)
    static let companionDestructive = Color(hex: 0xF87171)

    static let companionGhostHover = Color.white.opacity(0.08)
    static let companionGhostPressed = Color.white.opacity(0.05)

    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
