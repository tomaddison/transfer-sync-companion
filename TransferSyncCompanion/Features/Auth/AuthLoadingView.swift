import SwiftUI

struct AuthLoadingView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Waiting for sign in...")
                .font(.headline)

            Text("Complete sign in in your browser,\nthen return here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Cancel") {
                authManager.cancelLogin()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
