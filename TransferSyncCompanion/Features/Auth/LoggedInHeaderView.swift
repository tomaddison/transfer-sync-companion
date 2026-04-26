import SwiftUI
import AppKit

struct LoggedInHeaderView: View {
    let user: AuthUser
    let onSignOut: () -> Void
    var onSettings: (() -> Void)?

    @State private var isHoveringAvatar = false

    var body: some View {
        HStack(alignment: .center) {
            // Left Side: Logo
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Spacer()

            // Right Side: Action Items
            HStack(spacing: 8) {
                // Globe Button
                Button {
                    if let url = URL(string: "\(AppConstants.webBaseURL)/dashboard/projects") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.companionMutedText)
                }
                .buttonStyle(.ghostIcon)

                // Settings Button
                if let onSettings {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.companionMutedText)
                    }
                    .buttonStyle(.ghostIcon)
                }
                
                // User Menu
                DarkMenu {
                    DarkMenuText(text: user.displayName,
                                 font: Font.companion(size: 13))
                    .padding(.top, 6)
                    DarkMenuText(text: user.email,
                                 font: Font.companion(size: 11),
                                 color: Color.companionMutedText)
                    
                    DarkMenuDivider()
                    
                    DarkMenuItem(title: "Sign Out",
                                 icon: "rectangle.portrait.and.arrow.right",
                                 isDestructive: true) {
                        onSignOut()
                    }

                    DarkMenuDivider()

                    DarkMenuItem(title: "Quit TransferSync",
                                 icon: "power") {
                        NSApp.terminate(nil)
                    }
                } label: {
                    avatarView
                        .opacity(isHoveringAvatar ? 0.8 : 1.0)
                        .scaleEffect(isHoveringAvatar ? 1.05 : 1.0)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isHoveringAvatar = hovering
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL = user.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                initialsCircle
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            initialsCircle
        }
    }
    
    private var initialsCircle: some View {
        ZStack {
            Circle()
                .fill(Color.companionStatusGreen)
                .frame(width: 28, height: 28)
            Text(initials)
                .font(Font.companion(size: 14, weight: .regular))
                .foregroundStyle(.black).opacity(0.5)
        }
    }
    
    private var initials: String {
        let name = user.displayName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
