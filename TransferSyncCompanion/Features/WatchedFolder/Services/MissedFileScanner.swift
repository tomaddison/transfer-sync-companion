import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "MissedFileScanner")

/// Scans a watched folder for files that arrived while the app was closed.
/// Compares file creation dates against `watchingSince` and filters out
/// files already present in the upload history (by inode).
enum MissedFileScanner {
    static func scan(
        folder: WatchedFolder,
        whitelist: FileExtensionWhitelist,
        historyStore: UploadHistoryStore
    ) -> [URL] {
        let fm = FileManager.default
        let folderURL = URL(fileURLWithPath: folder.localPath)

        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            logger.warning("Failed to enumerate watched folder: \(folder.localPath)")
            return []
        }

        var missed: [URL] = []

        for fileURL in contents {
            let path = fileURL.path

            // Must be a regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            // Must match whitelist
            guard whitelist.matches(fileURL.lastPathComponent) else { continue }

            // Must be created after watchingSince
            guard let creationDate = resourceValues.creationDate,
                  creationDate >= folder.watchingSince else {
                continue
            }

            // Must not already be in upload history (checked by inode)
            guard let inode = UploadHistoryStore.inode(atPath: path),
                  !historyStore.hasBeenQueued(inode: inode, forWatchedFolder: folder.localPath) else {
                continue
            }

            missed.append(fileURL)
        }

        if !missed.isEmpty {
            logger.info("Found \(missed.count) missed file(s) in \(folder.localPath)")
        }

        return missed
    }
}
