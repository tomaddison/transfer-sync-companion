import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "UploadHistoryStore")

/// Persists a record of which files have been queued for upload, keyed by watched folder path.
/// Files are identified by inode number (stable across renames) rather than path.
/// Files are recorded at queue time (not completion) to prevent duplicate uploads after crashes.
@MainActor
final class UploadHistoryStore {
    /// Key: watched folder localPath, Value: set of inode numbers (as strings) already queued.
    private var history: [String: Set<String>] = [:]
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TransferSyncCompanion")
        fileURL = appDir.appendingPathComponent("uploadHistory.json")
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.info("No upload history file found")
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            history = try JSONDecoder().decode([String: Set<String>].self, from: data)
            let totalFiles = history.values.reduce(0) { $0 + $1.count }
            logger.info("Loaded upload history: \(totalFiles) file(s) across \(self.history.count) folder(s)")
        } catch {
            logger.error("Failed to load upload history: \(error.localizedDescription)")
            history = [:]
        }
    }

    func save() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(history)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save upload history: \(error.localizedDescription)")
        }
    }

    /// Record a file's inode as queued. Saves immediately to disk for crash safety.
    func recordInode(_ inode: UInt64, forWatchedFolder folderPath: String) {
        history[folderPath, default: []].insert(String(inode))
        save()
    }

    func hasBeenQueued(inode: UInt64, forWatchedFolder folderPath: String) -> Bool {
        history[folderPath]?.contains(String(inode)) == true
    }

    func removeHistory(forWatchedFolder folderPath: String) {
        history.removeValue(forKey: folderPath)
        save()
    }

    // MARK: - Inode Helpers

    /// Returns the inode number for a file, or nil if the file doesn't exist.
    static func inode(atPath path: String) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let inode = attrs[.systemFileNumber] as? UInt64 else {
            return nil
        }
        return inode
    }
}
