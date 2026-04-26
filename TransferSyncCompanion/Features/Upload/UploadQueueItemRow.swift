import AppKit
import SwiftUI

struct UploadQueueItemRow: View {
    let item: UploadItem
    let onCancel: () -> Void
    var onRetry: (() -> Void)?
    var onExportPtx: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Audio waveform icon
            Image(systemName: fileIcon)
                .font(.system(size: 15))
                .foregroundStyle(Color.companionMutedText)
                .frame(width: 20)

            // File name + status
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.fileName)
                        .font(Font.companion(size: 13))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let versionName = item.versionOf {
                        Text(versionName)
                            .font(Font.companion(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.companionStatusBlue.opacity(0.3)))
                            .layoutPriority(1)
                            .fixedSize()
                    }
                }

                statusView
            }

            Spacer()

            // Export + comments (completed uploads only)
            if item.status == .complete {
                exportMenu
                commentsButton
            }

            // Right-side status indicators
            statusIndicator
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.companionCard)
        .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.cardCornerRadius))
    }

    // MARK: - Status Text

    @ViewBuilder
    private var statusView: some View {
        if item.status == .uploading && item.progress < 1.0 {
            ProgressView(value: item.progress)
                .progressViewStyle(.linear)
                .tint(Color.companionStatusBlue)
        } else if item.status == .complete {
            Text("Complete")
                .font(Font.companion(size: 11))
                .foregroundStyle(Color.companionStatusGreen)
        } else if item.status == .failed {
            Text("Failed")
                .font(Font.companion(size: 11))
                .foregroundStyle(Color.companionStatusRed)
        } else if item.status == .exhausted {
            Text("Upload Failed")
                .font(Font.companion(size: 11))
                .foregroundStyle(Color.companionStatusRed)
        } else if item.status == .processing || item.status == .pending || (item.status == .uploading && item.progress >= 1.0) {
            HStack(spacing: 5) {
                Text(item.status == .processing ? "Processing" : "Pending")
                    .font(Font.companion(size: 11))
                    .foregroundStyle(Color.companionMutedText)
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                    .frame(width: 10, height: 10)
            }
        } else {
            Text(item.status.displayLabel)
                .font(Font.companion(size: 11))
                .foregroundStyle(Color.companionMutedText)
        }
    }

    // MARK: - Export Menu

    private var exportMenu: some View {
        Menu {
            Button(action: { onExportPtx?() }) {
                Label("Pro Tools Session (.ptx)", systemImage: "waveform")
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 13))
                .foregroundStyle(Color.companionMutedText)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Comments Button

    private var commentsButton: some View {
        Button(action: openInBrowser) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.companionMutedText)

                if let count = item.unresolvedCommentCount, count > 0 {
                    Text("\(count)")
                        .font(Font.companion(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(Circle().fill(.red))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.ghostIcon)
    }

    // MARK: - Status Indicator Icons

    @ViewBuilder
    private var statusIndicator: some View {
        if item.status == .uploading && item.progress < 1.0 {
            Text(progressLabel)
                .font(Font.companion(size: 10))
                .foregroundStyle(Color.companionMutedText)
                .monospacedDigit()
        }

        if item.status == .complete {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: CompanionTheme.statusIconSize))
                .foregroundStyle(Color.companionStatusGreen)
        } else if item.status == .failed || item.status == .exhausted {
            if let onRetry {
                Button(action: onRetry) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: CompanionTheme.statusIconSize))
                        .foregroundStyle(Color.companionMutedText)
                }
                .buttonStyle(.ghostIcon)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: CompanionTheme.statusIconSize))
                    .foregroundStyle(Color.companionMutedText)
            }
            .buttonStyle(.ghostIcon)
        } else if item.status == .pending || item.status == .uploading {
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: CompanionTheme.statusIconSize))
                    .foregroundStyle(Color.companionMutedText)
            }
            .buttonStyle(.ghostIcon)
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: "\(AppConstants.webBaseURL)/dashboard/projects/\(item.projectId)/asset/\(item.assetId)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var fileIcon: String {
        let ext = (item.fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "wav", "aiff", "aif", "flac", "caf",
             "mp3", "m4a", "ogg", "opus":
            return "waveform"
        default:
            return "doc"
        }
    }

    private var progressLabel: String {
        "\(Int(item.progress * 100))%"
    }
}
