import SwiftUI

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)

            Text("Upload files to TransferSync\ndirectly from your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Sign in with TransferSync") {
                authManager.initiateLogin()
            }
            .buttonStyle(.cta)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
