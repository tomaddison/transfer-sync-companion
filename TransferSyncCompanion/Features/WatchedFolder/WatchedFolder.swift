import Foundation

struct WatchedFolder: Codable, Identifiable {
    var id: String { localPath }

    let localPath: String
    let transfersyncProjectId: String
    let projectName: String
    let workspaceId: String
    var destinationFolderId: String?
    var destinationFolderName: String?
    let watchingSince: Date
    var enabled: Bool
    var bookmarkData: Data

    /// Whether this folder's local path still exists on disk.
    var isPathValid: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: localPath, isDirectory: &isDir) && isDir.boolValue
    }

    /// Whether uploads can proceed (destination must be set).
    var isReadyForUpload: Bool {
        enabled && destinationFolderId != nil
    }
}
