import SwiftUI

struct LoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
