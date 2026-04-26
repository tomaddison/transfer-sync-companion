import SwiftUI

/// A dismissible error banner that slides in from the top.
/// Use with an optional error string binding - the banner shows when non-nil.
struct ErrorBanner: View {
 let message: String
 var onDismiss: (() -> Void)?

 var body: some View {
 HStack(spacing: 8) {
 Image(systemName: "exclamationmark.triangle.fill")
 .foregroundStyle(.white)
 .font(.subheadline)

 Text(message)
 .font(.caption)
 .foregroundStyle(.white)
 .lineLimit(2)

 Spacer()

 if let onDismiss {
 Button(action: onDismiss) {
 Image(systemName: "xmark")
 .font(.caption2)
 .foregroundStyle(.white.opacity(0.8))
 }
 .buttonStyle(.ghostIcon(size: 22))
 }
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 8)
 .background(.red.gradient, in: RoundedRectangle(cornerRadius: 8))
 .padding(.horizontal, 12)
 .padding(.vertical, 4)
 .transition(.move(edge: .top).combined(with: .opacity))
 }
}
