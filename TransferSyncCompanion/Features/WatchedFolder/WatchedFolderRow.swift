import SwiftUI

struct WatchedFolderRow: View {
    let folder: WatchedFolder
    let syncStatuses: [SyncFileStatus]
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void
    let onChangeSource: () -> Void
    let onChangeDestination: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: folder icon + name + toggle + menu
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.companionMutedText)

                Text(folder.projectName)
                    .font(Font.companion(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { folder.enabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                DarkMenu {
                    DarkMenuItem(title: "Delete",
                                 icon: "trash",
                                 isDestructive: true) {
                        onRemove()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.companionMutedText)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
            }

            // Bottom row: source pill -> arrow -> destination pill
            HStack(spacing: 0) {
                // Source pill
                Button(action: onChangeSource) {
                    HStack(spacing: 4) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.companionMutedText)
                        Text(abbreviatedPath)
                            .font(Font.companion(size: 10))
                            .foregroundStyle(Color.companionMutedText)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.companionPill)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Image(systemName: "arrow.forward.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.companionMutedText)
                    .padding(.horizontal, 4)

                // Destination pill
                Button(action: onChangeDestination) {
                    HStack(spacing: 4) {
                        Image(systemName: syncIconName)
                            .font(.system(size: 11))
                            .foregroundStyle(syncIconColor)
                        Text(folder.destinationFolderName ?? "Set destination")
                            .font(Font.companion(size: 10))
                            .foregroundStyle(Color.companionMutedText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.companionPill)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if !folder.isPathValid {
                Text("Folder not found. Re-assign the folder path.")
                    .font(Font.companion(size: 10))
                    .foregroundStyle(Color.companionStatusRed)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.companionCard)
        .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.cardCornerRadius))
        .opacity(folder.enabled ? 1.0 : 0.6)
    }

    // MARK: - Sync Status

    private var aggregateSyncStatus: SyncBadge? {
        guard !syncStatuses.isEmpty else { return nil }
        if syncStatuses.contains(where: { $0.status == .uploading }) {
            return .uploading
        }
        if syncStatuses.contains(where: { $0.status == .failed }) {
            return .failed
        }
        return .complete
    }

    private var syncIconName: String {
        switch aggregateSyncStatus {
        case .uploading:
            return "arrow.trianglehead.2.clockwise.rotate.90.icloud.fill"
        case .complete:
            return "checkmark.icloud.fill"
        case .failed:
            return "xmark.icloud.fill"
        case nil:
            if folder.destinationFolderId != nil {
                return "checkmark.icloud.fill"
            }
            return "icloud"
        }
    }

    private var syncIconColor: Color {
        switch aggregateSyncStatus {
        case .uploading:
            return Color.companionStatusBlue
        case .complete:
            return Color.companionStatusGreen
        case .failed:
            return Color.companionStatusAmber
        case nil:
            if folder.destinationFolderId != nil {
                return Color.companionStatusGreen
            }
            return Color.companionMutedText
        }
    }

    // MARK: - Path

    private var abbreviatedPath: String {
        let path = folder.localPath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let displayPath: String
        if path.hasPrefix(home) {
            displayPath = "~" + path.dropFirst(home.count)
        } else {
            displayPath = path
        }
        if displayPath.count > 22 {
            return "..." + displayPath.suffix(19)
        }
        return displayPath
    }
}
