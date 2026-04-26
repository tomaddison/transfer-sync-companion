import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "WatchedFolderManager")

@Observable
@MainActor
final class WatchedFolderManager {
 let store: WatchedFolderStore
 let historyStore: UploadHistoryStore
 var whitelist: FileExtensionWhitelist

 private let uploadManager: UploadManager
 private let settingsStore: SettingsStore
 private let syncStatusStore = SyncStatusStore()

 /// Active FSEventStream instances keyed by watched folder localPath.
 private var activeStreams: [String: FSEventStreamWrapper] = [:]
 /// Task handles for the event processing loops, keyed by localPath.
 private var watcherTasks: [String: Task<Void, Never>] = [:]
 private var pendingStabilityChecks: Set<String> = []
 private var accessedURLs: [String: URL] = [:]
 private(set) var syncStatuses: [String: [SyncFileStatus]] = [:]
 private var pendingBadgeUpdates: [String: (inode: UInt64, fileName: String, folderPath: String)] = [:]
 /// Grace cycles before concluding a missing item was dismissed vs. mid-retry. Keyed by old mediaId.
 private var pendingRetryGrace: [String: Int] = [:]
 private var badgeObserverTask: Task<Void, Never>?

 init(uploadManager: UploadManager, store: WatchedFolderStore, historyStore: UploadHistoryStore, settingsStore: SettingsStore) {
 self.uploadManager = uploadManager
 self.store = store
 self.historyStore = historyStore
 self.settingsStore = settingsStore
 self.whitelist = FileExtensionWhitelist.load()
 }

 // MARK: - Lifecycle

 /// Start watching all enabled folders. Called on login.
 func startAll() {
 store.load()
 historyStore.load()
 logger.info("startAll: \(self.store.folders.count) watched folder(s), \(self.store.folders.filter(\.enabled).count) enabled")
 for folder in store.folders where folder.enabled {
 startWatching(folder)
 }
 syncWatchedPathsToExtension()
 }

 /// Stop all watchers. Called on logout.
 func stopAll() {
 let paths = Array(activeStreams.keys)
 for path in paths {
 stopWatching(localPath: path)
 }

 badgeObserverTask?.cancel()
 badgeObserverTask = nil
 pendingBadgeUpdates.removeAll()
 pendingRetryGrace.removeAll()
 syncStatuses.removeAll()
 }

 func startWatching(_ folder: WatchedFolder) {
 guard activeStreams[folder.localPath] == nil else { return }

 // Resolve security-scoped bookmark
 guard let resolvedURL = resolveBookmark(folder) else {
 logger.error("Failed to resolve bookmark for: \(folder.localPath)")
 var updated = folder
 updated.enabled = false
 store.update(updated)
 return
 }

 guard resolvedURL.startAccessingSecurityScopedResource() else {
 logger.error("Failed to start accessing security-scoped resource: \(folder.localPath)")
 return
 }
 accessedURLs[folder.localPath] = resolvedURL

 // Check path validity
 guard folder.isPathValid else {
 logger.warning("Watched folder path no longer exists: \(folder.localPath)")
 resolvedURL.stopAccessingSecurityScopedResource()
 accessedURLs.removeValue(forKey: folder.localPath)
 return
 }

 let stream = FSEventStreamWrapper(path: folder.localPath)
 activeStreams[folder.localPath] = stream

 let folderPath = folder.localPath
 let task = Task { [weak self] in
 stream.start()
 logger.info("Event loop started for: \(folderPath)")
 for await event in stream.events {
 guard let self else { break }
 await self.handleFSEvent(event, forFolderPath: folderPath)
 }
 logger.info("Event loop ended for: \(folderPath)")
 }
 watcherTasks[folder.localPath] = task
 logger.info("Started watching: \(folder.localPath)")

 // Scan for files that arrived while the folder was disabled or the app was closed
 if folder.isReadyForUpload {
 let missed = MissedFileScanner.scan(folder: folder, whitelist: whitelist, historyStore: historyStore)
 for fileURL in missed {
 Task { await processFile(at: fileURL, for: folder) }
 }
 }
 }

 func stopWatching(localPath: String) {
 watcherTasks[localPath]?.cancel()
 watcherTasks.removeValue(forKey: localPath)

 activeStreams[localPath]?.stop()
 activeStreams.removeValue(forKey: localPath)

 if let url = accessedURLs.removeValue(forKey: localPath) {
 url.stopAccessingSecurityScopedResource()
 }

 logger.info("Stopped watching: \(localPath)")
 }

 // MARK: - Missed File Scan

 /// Scan all watched folders for files that arrived while the app was closed.
 func scanForMissedFiles() {
 for folder in store.folders where folder.enabled && folder.isReadyForUpload {
 let missed = MissedFileScanner.scan(
 folder: folder,
 whitelist: whitelist,
 historyStore: historyStore
 )
 for fileURL in missed {
 Task { await processFile(at: fileURL, for: folder) }
 }
 }
 }

 // MARK: - Event Handling

 private func handleFSEvent(_ event: FSEvent, forFolderPath folderPath: String) async {
 logger.debug("Received FSEvent for: \(event.path) (isFile=\(event.isFile), created=\(event.isCreated), renamed=\(event.isRenamed))")

 // Handle file creation and rename/move events.
 // Renames fire when a file is moved or copied into the folder (e.g. Save As, Finder copy).
 // The inode-based history check in processFile prevents actual renames from re-uploading.
 guard event.isFile && (event.isCreated || event.isRenamed) else {
 logger.debug("Skipping event: not a file creation or move")
 return
 }

 // Root changed means the watched folder itself was moved/deleted
 if event.isRootChanged {
 logger.warning("Root changed for watched folder: \(folderPath)")
 return
 }

 guard let folder = store.folder(forPath: folderPath) else {
 logger.warning("No watched folder found for path: \(folderPath)")
 return
 }

 logger.info("New file detected: \(event.path)")
 let fileURL = URL(fileURLWithPath: event.path)
 await processFile(at: fileURL, for: folder)
 }

 private func processFile(at fileURL: URL, for folder: WatchedFolder) async {
 let path = fileURL.path

 // Prevent duplicate processing
 guard !pendingStabilityChecks.contains(path) else {
 logger.debug("Skipping (already processing): \(fileURL.lastPathComponent)")
 return
 }

 // Check extension whitelist
 guard whitelist.matches(fileURL.lastPathComponent) else {
 logger.debug("Skipping (extension not in whitelist): \(fileURL.lastPathComponent)")
 return
 }

 // Read file attributes (need creation date and inode)
 guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
 logger.debug("Skipping (cannot read attributes): \(fileURL.lastPathComponent)")
 return
 }

 // Check creation date against watchingSince
 guard let creationDate = attrs[.creationDate] as? Date,
 creationDate >= folder.watchingSince else {
 logger.debug("Skipping (older than watchingSince): \(fileURL.lastPathComponent)")
 return
 }

 // Check upload history by inode (stable across renames)
 guard let inode = attrs[.systemFileNumber] as? UInt64 else {
 logger.debug("Skipping (no inode): \(fileURL.lastPathComponent)")
 return
 }
 guard !historyStore.hasBeenQueued(inode: inode, forWatchedFolder: folder.localPath) else {
 logger.debug("Skipping (inode already queued): \(fileURL.lastPathComponent)")
 return
 }

 // Check destination is set
 guard folder.isReadyForUpload else {
 logger.warning("Skipping file (no destination set): \(fileURL.lastPathComponent)")
 return
 }

 pendingStabilityChecks.insert(path)
 defer { pendingStabilityChecks.remove(path) }

 // Wait for file to finish writing
 do {
 _ = try await FileStabilityChecker.waitForStableSize(at: path)
 } catch {
 logger.warning("File stability check failed for \(fileURL.lastPathComponent): \(error.localizedDescription)")
 return
 }

 // Record inode in history BEFORE uploading (crash safety)
 historyStore.recordInode(inode, forWatchedFolder: folder.localPath)

 // Set Finder badge to uploading
 setSyncBadge(.uploading, inode: inode, fileName: fileURL.lastPathComponent, folderPath: folder.localPath)

 logger.info("Queuing auto-upload: \(fileURL.lastPathComponent) -> \(folder.projectName)")

 // Try auto-stacking if enabled, otherwise use the normal upload pipeline
 if settingsStore.autoStackEnabled {
 await uploadWithAutoStack(fileURL: fileURL, folder: folder)
 } else {
 await uploadManager.uploadFiles(
 fileURLs: [fileURL],
 projectId: folder.transfersyncProjectId,
 workspaceId: folder.workspaceId,
 parentFolderId: folder.destinationFolderId
 )
 }

 // Track this upload so the badge observer can update it when the status changes
 if let item = uploadManager.items.first(where: { $0.fileName == fileURL.lastPathComponent }) {
 pendingBadgeUpdates[item.id] = (inode: inode, fileName: fileURL.lastPathComponent, folderPath: folder.localPath)
 startBadgeObserverIfNeeded()
 }
 }

 // MARK: - Auto-Stack

 private func uploadWithAutoStack(fileURL: URL, folder: WatchedFolder) async {
 do {
 let assets = try await uploadManager.apiClient.fetchFolderAssets(
 projectId: folder.transfersyncProjectId,
 parentId: folder.destinationFolderId
 )

 if let match = AutoStackMatcher.findBestMatch(
 fileName: fileURL.lastPathComponent,
 candidates: assets
 ) {
 logger.info("Auto-stacking \(fileURL.lastPathComponent) with \(match.assetName)")
 await uploadManager.uploadFileWithAutoStack(
 fileURL: fileURL,
 projectId: folder.transfersyncProjectId,
 workspaceId: folder.workspaceId,
 parentFolderId: folder.destinationFolderId,
 targetId: match.assetId,
 targetType: match.assetType
 )
 } else {
 await uploadManager.uploadFiles(
 fileURLs: [fileURL],
 projectId: folder.transfersyncProjectId,
 workspaceId: folder.workspaceId,
 parentFolderId: folder.destinationFolderId
 )
 }
 } catch {
 logger.warning("Auto-stack asset fetch failed, falling back to normal upload: \(error.localizedDescription)")
 await uploadManager.uploadFiles(
 fileURLs: [fileURL],
 projectId: folder.transfersyncProjectId,
 workspaceId: folder.workspaceId,
 parentFolderId: folder.destinationFolderId
 )
 }
 }

 // MARK: - Badge Observer

 /// Polls uploadManager.items to update Finder badges when uploads reach a terminal state.
 private func startBadgeObserverIfNeeded() {
 guard badgeObserverTask == nil else { return }
 badgeObserverTask = Task { [weak self] in
 while let self, !Task.isCancelled, !self.pendingBadgeUpdates.isEmpty {
 try? await Task.sleep(for: .seconds(1))
 self.checkPendingBadges()
 }
 self?.badgeObserverTask = nil
 }
 }

 private func checkPendingBadges() {
 var resolved: [String] = []
 var toAdd: [(id: String, info: (inode: UInt64, fileName: String, folderPath: String))] = []

 for (mediaId, info) in pendingBadgeUpdates {
 guard let item = uploadManager.items.first(where: { $0.id == mediaId }) else {
 // Item gone - could be mid-retry (async gap) or dismissed by the user.
 // First, check if a new item appeared for the same physical file (inode match = retry).
 if let retryItem = uploadManager.items.first(where: { newItem in
 newItem.id != mediaId &&
 ((try? FileManager.default.attributesOfItem(atPath: newItem.fileURL.path)[.systemFileNumber] as? UInt64) == info.inode)
 }) {
 setSyncBadge(.uploading, inode: info.inode, fileName: info.fileName, folderPath: info.folderPath)
 toAdd.append((id: retryItem.id, info: info))
 pendingRetryGrace.removeValue(forKey: mediaId)
 resolved.append(mediaId)
 continue
 }

 // No retry item yet - apply a grace period before concluding it was dismissed.
 // This covers the async gap in retryUpload between old item removal and new item insertion.
 let remaining = pendingRetryGrace[mediaId] ?? 5
 if remaining > 0 {
 pendingRetryGrace[mediaId] = remaining - 1
 continue
 }

 // Grace period elapsed - must be a dismissal, not a retry.
 pendingRetryGrace.removeValue(forKey: mediaId)
 let currentBadge = syncStatuses[info.folderPath]?.first(where: { $0.inode == info.inode })?.status
 if currentBadge == .failed {
 clearSyncBadge(inode: info.inode, folderPath: info.folderPath)
 } else {
 setSyncBadge(.complete, inode: info.inode, fileName: info.fileName, folderPath: info.folderPath)
 }
 resolved.append(mediaId)
 continue
 }

 pendingRetryGrace.removeValue(forKey: mediaId)

 switch item.status {
 case .complete:
 setSyncBadge(.complete, inode: info.inode, fileName: info.fileName, folderPath: info.folderPath)
 resolved.append(mediaId)
 case .failed, .exhausted:
 setSyncBadge(.failed, inode: info.inode, fileName: info.fileName, folderPath: info.folderPath)
 // Keep tracking - waiting for retry (new item) or dismissal (item removed)
 default:
 break
 }
 }

 for id in resolved {
 pendingBadgeUpdates.removeValue(forKey: id)
 }
 for entry in toAdd {
 pendingBadgeUpdates[entry.id] = entry.info
 }
 }

 // MARK: - Finder Sync Extension

 /// Write current watched folder paths to the shared App Group container
 /// so the Finder Sync Extension knows which directories to badge.
 func syncWatchedPathsToExtension() {
 let enabledPaths = store.folders.filter(\.enabled).map(\.localPath)
 syncStatusStore.writeWatchedPaths(enabledPaths)
 postSyncNotification()
 logger.info("Synced \(enabledPaths.count) watched path(s) to Finder extension")
 }

 /// Update the sync badge for a file and write to the shared container.
 func setSyncBadge(_ badge: SyncBadge, inode: UInt64, fileName: String, folderPath: String) {
 let filePath = (folderPath as NSString).appendingPathComponent(fileName)
 let status = SyncFileStatus(inode: inode, status: badge, fileName: fileName, filePath: filePath)

 var folderStatuses = syncStatuses[folderPath] ?? []
 folderStatuses.removeAll { $0.inode == inode }
 folderStatuses.append(status)
 syncStatuses[folderPath] = folderStatuses

 syncStatusStore.write(statuses: syncStatuses)
 postSyncNotification()
 }

 /// Remove a file's sync badge entirely (e.g. after a dismissed failure).
 private func clearSyncBadge(inode: UInt64, folderPath: String) {
 var folderStatuses = syncStatuses[folderPath] ?? []
 folderStatuses.removeAll { $0.inode == inode }
 syncStatuses[folderPath] = folderStatuses
 syncStatusStore.write(statuses: syncStatuses)
 postSyncNotification()
 }

 private func postSyncNotification() {
 CFNotificationCenterPostNotification(
 CFNotificationCenterGetDarwinNotifyCenter(),
 CFNotificationName(SyncConstants.statusChangedNotification as CFString),
 nil, nil, true
 )
 }

 // MARK: - Bookmark Resolution

 private func resolveBookmark(_ folder: WatchedFolder) -> URL? {
 var isStale = false
 guard let url = try? URL(
 resolvingBookmarkData: folder.bookmarkData,
 options: .withSecurityScope,
 relativeTo: nil,
 bookmarkDataIsStale: &isStale
 ) else {
 return nil
 }
 if isStale {
 logger.warning("Bookmark is stale for: \(folder.localPath). Attempting to refresh.")
 if let newBookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
 var updated = folder
 updated.bookmarkData = newBookmark
 store.update(updated)
 }
 }
 return url
 }
}
