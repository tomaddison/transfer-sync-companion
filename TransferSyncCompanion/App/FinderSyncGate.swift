import SwiftUI
import FinderSync
import AppKit

/// Blocks `content` until the user enables the Finder Sync extension in System Settings.
struct FinderSyncGate<Content: View>: View {
    @State private var isEnabled = FIFinderSyncController.isExtensionEnabled
    @State private var pollTimer: Timer?

    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if isEnabled {
                content()
            } else {
                gate
            }
        }
        .onAppear {
            refresh()
            startPolling()
        }
        .onDisappear { stopPolling() }
    }

    private var gate: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color.companionStatusAmber)

            Text("Enable Finder badges")
                .font(Font.companion(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text("TransferSync needs its Finder extension turned on to show upload status badges in Finder.")
                .font(Font.companion(size: 12))
                .foregroundStyle(Color.companionMutedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings") {
                FIFinderSyncController.showExtensionManagementInterface()
            }
            .buttonStyle(.ghost)
            .font(Font.companion(size: 12, weight: .medium))

            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() {
        isEnabled = FIFinderSyncController.isExtensionEnabled
    }

    // No notification fires when the user toggles the extension, so poll while mounted.
    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
