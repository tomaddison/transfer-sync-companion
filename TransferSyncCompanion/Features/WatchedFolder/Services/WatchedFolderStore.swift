import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "WatchedFolderStore")

@Observable
@MainActor
final class WatchedFolderStore {
    private(set) var folders: [WatchedFolder] = []

    private let userDefaultsKey = "watchedFolders"
    private let syncStatusStore = SyncStatusStore()

    func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            logger.info("No watched folders stored")
            return
        }
        do {
            folders = try JSONDecoder().decode([WatchedFolder].self, from: data)
            logger.info("Loaded \(self.folders.count) watched folder(s)")
        } catch {
            logger.error("Failed to decode watched folders: \(error.localizedDescription)")
            folders = []
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(folders)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            logger.error("Failed to encode watched folders: \(error.localizedDescription)")
        }
        syncWatchedPathsToExtension()
    }

    private func syncWatchedPathsToExtension() {
        let enabledPaths = folders.filter(\.enabled).map(\.localPath)
        syncStatusStore.writeWatchedPaths(enabledPaths)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(SyncConstants.statusChangedNotification as CFString),
            nil, nil, true
        )
    }

    func add(_ folder: WatchedFolder) {
        guard !folders.contains(where: { $0.localPath == folder.localPath }) else {
            logger.warning("Watched folder already exists: \(folder.localPath)")
            return
        }
        folders.append(folder)
        save()
        logger.info("Added watched folder: \(folder.localPath) -> \(folder.projectName)")
    }

    func remove(localPath: String) {
        folders.removeAll { $0.localPath == localPath }
        save()
        logger.info("Removed watched folder: \(localPath)")
    }

    func update(_ folder: WatchedFolder) {
        guard let idx = folders.firstIndex(where: { $0.localPath == folder.localPath }) else { return }
        folders[idx] = folder
        save()
    }

    func folder(forPath path: String) -> WatchedFolder? {
        folders.first { $0.localPath == path }
    }
}
