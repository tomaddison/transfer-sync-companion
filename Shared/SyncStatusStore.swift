import Foundation

struct SyncFileStatus: Codable {
    let inode: UInt64
    let status: SyncBadge
    let fileName: String
    let filePath: String
}

enum SyncBadge: String, Codable {
    case uploading
    case complete
    case failed
}

class SyncStatusStore {

    private let statusFileURL: URL
    private let watchedPathsFileURL: URL

    init() {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SyncConstants.appGroupId
        )!
        statusFileURL = container.appendingPathComponent(SyncConstants.statusFileName)
        watchedPathsFileURL = container.appendingPathComponent(SyncConstants.watchedPathsFileName)
    }

    func write(statuses: [String: [SyncFileStatus]]) {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        try? data.write(to: statusFileURL)
    }

    func read() -> [String: [SyncFileStatus]] {
        guard let data = try? Data(contentsOf: statusFileURL),
              let statuses = try? JSONDecoder().decode([String: [SyncFileStatus]].self, from: data)
        else { return [:] }
        return statuses
    }

    func writeWatchedPaths(_ paths: [String]) {
        guard let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: watchedPathsFileURL)
    }

    func readWatchedPaths() -> [String] {
        guard let data = try? Data(contentsOf: watchedPathsFileURL),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return paths
    }
}
