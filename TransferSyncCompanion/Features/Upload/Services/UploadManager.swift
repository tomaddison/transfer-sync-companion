import Foundation
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "UploadManager")

@Observable
@MainActor
final class UploadManager {
 var items: [UploadItem] = []
 var isUploading = false
 var error: String?

 let apiClient: any UploadAPIClient
 private let configManager: ConfigManager
 private let realtimeManager: RealtimeManager
 private let connectivityManager: ConnectivityManager?
 private let notificationManager: NotificationManager?
 private var uploadTasks: [String: Task<Void, Never>] = [:]

 init(
 apiClient: any UploadAPIClient,
 configManager: ConfigManager,
 realtimeManager: RealtimeManager,
 connectivityManager: ConnectivityManager? = nil,
 notificationManager: NotificationManager? = nil
 ) {
 self.apiClient = apiClient
 self.configManager = configManager
 self.realtimeManager = realtimeManager
 self.connectivityManager = connectivityManager
 self.notificationManager = notificationManager
 loadLog()
 }

 // MARK: - Persistence

 private var logFileURL: URL {
 let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
 let dir = appSupport.appendingPathComponent("TransferSyncCompanion", isDirectory: true)
 try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
 return dir.appendingPathComponent("uploadLog.json")
 }

 private func saveLog() {
 guard let data = try? JSONEncoder().encode(items) else { return }
 try? data.write(to: logFileURL, options: .atomic)
 }

 private func loadLog() {
 guard let data = try? Data(contentsOf: logFileURL),
 var saved = try? JSONDecoder().decode([UploadItem].self, from: data)
 else { return }
 // Items that were in-flight during a previous session can't be resumed - mark them failed
 for i in saved.indices where !saved[i].status.isTerminal {
 saved[i].status = .failed
 }
 items = saved
 }

 // MARK: - Upload Pipeline

 func uploadFiles(
 fileURLs: [URL],
 projectId: String,
 workspaceId: String,
 parentFolderId: String?
 ) async {
 error = nil

 let filesData = buildFileMetadata(fileURLs: fileURLs, projectId: projectId)
 guard !filesData.isEmpty else { return }

 let initResponse: UploadInitResponse
 do {
 initResponse = try await apiClient.initUploads(UploadInitRequest(
 files: filesData,
 parentId: parentFolderId,
 projectId: projectId,
 workspaceId: workspaceId
 ))
 } catch {
 logger.error("Upload init failed: \(error.localizedDescription)")
 self.error = "Failed to initialize upload: \(error.localizedDescription)"
 return
 }

 await processInitResponse(
 fileURLs: fileURLs,
 mediaPairs: initResponse.mediaPairs,
 batchId: initResponse.batchId,
 projectId: projectId,
 workspaceId: workspaceId,
 parentFolderId: parentFolderId
 )
 }

 func uploadFileWithAutoStack(
 fileURL: URL,
 projectId: String,
 workspaceId: String,
 parentFolderId: String?,
 targetId: String,
 targetType: String
 ) async {
 error = nil

 let filesData = buildFileMetadata(fileURLs: [fileURL], projectId: projectId)
 guard !filesData.isEmpty else { return }

 let response: AutoStackResponse
 do {
 response = try await apiClient.autoStack(AutoStackRequest(
 files: filesData,
 parentId: parentFolderId,
 projectId: projectId,
 targetId: targetId,
 targetType: targetType,
 workspaceId: workspaceId
 ))
 } catch {
 logger.error("Auto-stack failed: \(error.localizedDescription)")
 self.error = "Auto-stack failed: \(error.localizedDescription)"
 return
 }

 let mediaPairs = response.mediaPairs.map { MediaPair(mediaId: $0.mediaId, assetId: $0.assetId) }
 let versionName = response.mediaPairs.first?.versionName

 await processInitResponse(
 fileURLs: [fileURL],
 mediaPairs: mediaPairs,
 batchId: response.batchId,
 projectId: projectId,
 workspaceId: workspaceId,
 parentFolderId: parentFolderId,
 versionOf: versionName
 )
 }

 // MARK: - Shared Upload Pipeline

 private func buildFileMetadata(fileURLs: [URL], projectId: String) -> [FileInitData] {
 fileURLs.compactMap { url in
 let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
 let size = (attrs?[.size] as? Int) ?? 0
 let modified = (attrs?[.modificationDate] as? Date) ?? Date()
 let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
 return FileInitData(
 name: url.lastPathComponent,
 fileSize: size,
 fileType: mimeType,
 srcModified: ISO8601DateFormatter().string(from: modified),
 projectId: projectId
 )
 }
 }

 private func processInitResponse(
 fileURLs: [URL],
 mediaPairs: [MediaPair],
 batchId: String,
 projectId: String,
 workspaceId: String,
 parentFolderId: String?,
 versionOf: String? = nil
 ) async {
 // 1. Build presign inputs
 let threshold = configManager.multipartThresholdBytes
 var presignInputs: [PresignInput] = []

 for (url, pair) in zip(fileURLs, mediaPairs) {
 let key = S3UploadService.rawS3Key(mediaId: pair.mediaId, fileName: url.lastPathComponent)
 let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
 let contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
 let metadata = UploadMetadata(mediaId: pair.mediaId, assetId: pair.assetId)

 if size < threshold {
 presignInputs.append(.simple(key: key, contentType: contentType, metadata: metadata))
 } else {
 let totalParts = Int(ceil(Double(size) / Double(S3UploadService.partSize)))
 presignInputs.append(.multipart(key: key, contentType: contentType, totalParts: totalParts, metadata: metadata))
 }
 }

 // 2. Call /uploads/presign
 let presignResults: [PresignResult]
 do {
 presignResults = try await apiClient.presignUploads(PresignRequest(
 inputs: presignInputs,
 projectId: projectId
 ))
 } catch {
 logger.error("Presign failed: \(error.localizedDescription)")
 self.error = "Failed to get upload URLs: \(error.localizedDescription)"
 return
 }

 // 3. Create local queue items
 for (url, (pair, presignResult)) in zip(fileURLs, zip(mediaPairs, presignResults)) {
 let key = S3UploadService.rawS3Key(mediaId: pair.mediaId, fileName: url.lastPathComponent)
 let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
 let item = UploadItem(
 id: pair.mediaId,
 assetId: pair.assetId,
 fileName: url.lastPathComponent,
 fileSize: size,
 fileURL: url,
 s3Key: key,
 projectId: projectId,
 workspaceId: workspaceId,
 parentFolderId: parentFolderId,
 batchId: batchId,
 status: .pending,
 progress: 0,
 s3UploadId: presignResult.multipartUploadId,
 versionOf: versionOf
 )
 items.insert(item, at: 0)
 }

 saveLog()
 isUploading = true

 // 4. Subscribe to Realtime for this batch
 await realtimeManager.subscribeToBatch(batchId: batchId) { [weak self] mediaId, newStatus in
 self?.handleRealtimeUpdate(mediaId: mediaId, newStatus: newStatus)
 }

 // 5. Start uploads
 for (index, pair) in mediaPairs.enumerated() {
 let presignResult = presignResults[index]
 let fileURL = fileURLs[index]
 let mediaId = pair.mediaId
 let task = Task { [weak self] in
 guard let self else { return }
 await self.uploadSingleFile(mediaId: mediaId, fileURL: fileURL, presignResult: presignResult, projectId: projectId)
 }
 uploadTasks[mediaId] = task
 }
 }

 // MARK: - Single File Upload

 private static let maxRetries = 5
 private static let retryBaseDelay: TimeInterval = 2.0

 private func uploadSingleFile(
 mediaId: String,
 fileURL: URL,
 presignResult: PresignResult,
 projectId: String
 ) async {
 updateItem(id: mediaId) { $0.status = .uploading }

 // Set status to "uploading" on server
 do {
 try await apiClient.updateUploadStatus(UpdateStatusRequest(
 mediaId: mediaId, projectId: projectId,
 status: "uploading", originalPath: nil, uploadCompletedAt: nil
 ))
 } catch {
 logger.warning("Failed to set uploading status: \(error.localizedDescription)")
 }

 let s3Key = items.first(where: { $0.id == mediaId })?.s3Key ?? ""
 var lastError: Error?

 for attempt in 0...Self.maxRetries {
 if attempt > 0 {
 let delay = Self.retryBaseDelay * pow(2.0, Double(attempt - 1))
 logger.info("Retry attempt \(attempt)/\(Self.maxRetries) for \(fileURL.lastPathComponent) after \(delay)s")
 do {
 try await Task.sleep(for: .seconds(delay))
 try Task.checkCancellation()
 } catch {
 logger.info("Upload cancelled during retry wait: \(fileURL.lastPathComponent)")
 uploadTasks.removeValue(forKey: mediaId)
 checkAllComplete()
 return
 }

 // Wait for connectivity before retrying
 await waitForConnectivity()

 updateItem(id: mediaId) {
 $0.retryCount = attempt
 $0.status = .uploading
 $0.progress = 0
 }
 }

 do {
 try Task.checkCancellation()

 switch presignResult {
 case .simple(_, let url):
 let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
 try await S3UploadService.uploadSimple(
 fileURL: fileURL,
 presignedURL: url,
 contentType: contentType,
 onProgress: { [weak self] pct in
 Task { @MainActor [weak self] in
 self?.updateItem(id: mediaId) { $0.progress = pct }
 }
 }
 )

 case .multipart(_, let uploadId, let urls):
 let parts = try await S3UploadService.uploadMultipart(
 fileURL: fileURL,
 partURLs: urls,
 onProgress: { [weak self] pct in
 Task { @MainActor [weak self] in
 self?.updateItem(id: mediaId) { $0.progress = pct }
 }
 }
 )

 try Task.checkCancellation()

 try await apiClient.completeMultipart(CompleteMultipartRequest(
 key: s3Key, uploadId: uploadId, parts: parts, projectId: projectId
 ))
 }

 // S3 upload done - only set uploadCompletedAt.
 // The Lambda will set upload_status to "processing" then "success",
 // which we receive via Realtime.
 try Task.checkCancellation()
 try await apiClient.updateUploadStatus(UpdateStatusRequest(
 mediaId: mediaId, projectId: projectId,
 status: nil,
 originalPath: nil,
 uploadCompletedAt: ISO8601DateFormatter().string(from: Date())
 ))

 updateItem(id: mediaId) { $0.progress = 1.0 }
 logger.info("S3 upload complete, awaiting processing: \(fileURL.lastPathComponent)")
 lastError = nil
 break

 } catch is CancellationError {
 logger.info("Upload cancelled: \(fileURL.lastPathComponent)")
 uploadTasks.removeValue(forKey: mediaId)
 checkAllComplete()
 return
 } catch {
 lastError = error
 logger.warning("Upload attempt \(attempt) failed for \(fileURL.lastPathComponent): \(error.localizedDescription)")
 continue
 }
 }

 if let lastError {
 logger.error("Upload exhausted after \(Self.maxRetries) retries for \(fileURL.lastPathComponent): \(lastError.localizedDescription)")
 updateItem(id: mediaId) { $0.status = .exhausted }
 try? await apiClient.failUploads(FailUploadRequest(
 mediaIds: [mediaId], projectId: projectId
 ))
 notificationManager?.notifyUploadFailed(fileName: fileURL.lastPathComponent)
 }

 uploadTasks.removeValue(forKey: mediaId)
 checkAllComplete()
 }

 /// Suspends until network connectivity is available. Returns immediately if already connected.
 private func waitForConnectivity() async {
 guard let connectivityManager else { return }
 while !connectivityManager.isConnected {
 logger.info("Waiting for network connectivity...")
 try? await Task.sleep(for: .seconds(1))
 if Task.isCancelled { return }
 }
 }

 // MARK: - Retry

 func retryUpload(id: String) async {
 guard let failedItem = items.first(where: { $0.id == id }),
 failedItem.status == .failed || failedItem.status == .exhausted else { return }

 let fileURL = failedItem.fileURL
 let projectId = failedItem.projectId
 let workspaceId = failedItem.workspaceId
 let parentFolderId = failedItem.parentFolderId

 let insertIndex = items.firstIndex(where: { $0.id == id }) ?? 0
 items.removeAll { $0.id == id }

 // Re-upload the single file through the normal pipeline
 let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
 let size = (attrs?[.size] as? Int) ?? 0
 let modified = (attrs?[.modificationDate] as? Date) ?? Date()
 let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType

 let fileData = FileInitData(
 name: fileURL.lastPathComponent,
 fileSize: size,
 fileType: mimeType,
 srcModified: ISO8601DateFormatter().string(from: modified),
 projectId: projectId
 )

 let initResponse: UploadInitResponse
 do {
 initResponse = try await apiClient.initUploads(UploadInitRequest(
 files: [fileData],
 parentId: parentFolderId,
 projectId: projectId,
 workspaceId: workspaceId
 ))
 } catch {
 logger.error("Retry init failed: \(error.localizedDescription)")
 self.error = "Retry failed: \(error.localizedDescription)"
 return
 }

 guard let pair = initResponse.mediaPairs.first else { return }

 let key = S3UploadService.rawS3Key(mediaId: pair.mediaId, fileName: fileURL.lastPathComponent)
 let contentType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
 let metadata = UploadMetadata(mediaId: pair.mediaId, assetId: pair.assetId)
 let threshold = configManager.multipartThresholdBytes

 let presignInput: PresignInput
 if size < threshold {
 presignInput = .simple(key: key, contentType: contentType, metadata: metadata)
 } else {
 let totalParts = Int(ceil(Double(size) / Double(S3UploadService.partSize)))
 presignInput = .multipart(key: key, contentType: contentType, totalParts: totalParts, metadata: metadata)
 }

 let presignResults: [PresignResult]
 do {
 presignResults = try await apiClient.presignUploads(PresignRequest(
 inputs: [presignInput],
 projectId: projectId
 ))
 } catch {
 logger.error("Retry presign failed: \(error.localizedDescription)")
 self.error = "Retry failed: \(error.localizedDescription)"
 return
 }

 guard let presignResult = presignResults.first else { return }

 let newItem = UploadItem(
 id: pair.mediaId,
 assetId: pair.assetId,
 fileName: fileURL.lastPathComponent,
 fileSize: size,
 fileURL: fileURL,
 s3Key: key,
 projectId: projectId,
 workspaceId: workspaceId,
 parentFolderId: parentFolderId,
 batchId: initResponse.batchId,
 status: .pending,
 progress: 0,
 s3UploadId: presignResult.multipartUploadId
 )

 items.insert(newItem, at: min(insertIndex, items.count))
 isUploading = true

 await realtimeManager.subscribeToBatch(batchId: initResponse.batchId) { [weak self] mediaId, newStatus in
 self?.handleRealtimeUpdate(mediaId: mediaId, newStatus: newStatus)
 }

 let task = Task { [weak self] in
 guard let self else { return }
 await self.uploadSingleFile(mediaId: pair.mediaId, fileURL: fileURL, presignResult: presignResult, projectId: projectId)
 }
 uploadTasks[pair.mediaId] = task
 }

 // MARK: - Cancel

 func cancelUpload(id: String) async {
 guard let item = items.first(where: { $0.id == id }) else { return }

 switch item.status {
 case .pending:
 updateItem(id: id) { $0.status = .failed }
 saveLog()

 case .uploading:
 uploadTasks[id]?.cancel()
 uploadTasks.removeValue(forKey: id)

 if let s3UploadId = item.s3UploadId {
 try? await apiClient.abortMultipart(AbortMultipartRequest(
 key: item.s3Key, uploadId: s3UploadId, projectId: item.projectId
 ))
 }

 try? await apiClient.failUploads(FailUploadRequest(
 mediaIds: [id], projectId: item.projectId
 ))

 updateItem(id: id) { $0.status = .failed }
 checkAllComplete()
 saveLog()

 case .failed, .exhausted:
 // X button on a failed/exhausted item dismisses it
 removeItem(id: id)
 saveLog()

 default:
 break
 }
 }

 // MARK: - Realtime

 private func handleRealtimeUpdate(mediaId: String, newStatus: String) {
 guard let idx = items.firstIndex(where: { $0.id == mediaId }) else { return }
 let current = items[idx].status

 // Only apply forward-progress updates
 switch newStatus {
 case "processing" where current == .uploading || current == .complete:
 items[idx].status = .processing
 case "success":
 items[idx].status = .complete
 items[idx].progress = 1.0
 items[idx].unresolvedCommentCount = 0
 notificationManager?.notifyUploadComplete(
 fileName: items[idx].fileName,
 versionOf: items[idx].versionOf
 )
 case "failed" where !current.isTerminal:
 items[idx].status = .failed
 notificationManager?.notifyUploadFailed(fileName: items[idx].fileName)
 default:
 break
 }

 checkAllComplete()
 saveLog()
 }

 func dismissError() {
 error = nil
 }

 // MARK: - Cleanup

 func clearCompleted() {
 items.removeAll { $0.status.isTerminal }
 saveLog()
 }

 func onLogout() async {
 for (id, task) in uploadTasks {
 task.cancel()
 uploadTasks.removeValue(forKey: id)
 }
 // Mark any interrupted in-flight items as failed so the log is accurate
 for i in items.indices where !items[i].status.isTerminal {
 items[i].status = .failed
 }
 isUploading = false
 saveLog()
 await realtimeManager.unsubscribeAll()
 }

 // MARK: - Comment Counts

 func fetchUnresolvedCommentCounts() async {
 let completedAssetIds = items
 .filter { $0.status == .complete }
 .map(\.assetId)

 guard !completedAssetIds.isEmpty else { return }

 do {
 let counts: [String: Int] = try await apiClient.fetchUnresolvedCounts(assetIds: completedAssetIds)
 for i in items.indices where items[i].status == .complete {
 items[i].unresolvedCommentCount = counts[items[i].assetId] ?? 0
 }
 } catch {
 logger.warning("Failed to fetch comment counts: \(error.localizedDescription)")
 }
 }

 // MARK: - Helpers

 private func updateItem(id: String, mutation: (inout UploadItem) -> Void) {
 guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
 mutation(&items[idx])
 }

 private func removeItem(id: String) {
 items.removeAll { $0.id == id }
 checkAllComplete()
 }

 private func checkAllComplete() {
 if items.isEmpty || items.allSatisfy({ $0.status.isTerminal }) {
 isUploading = false
 }
 }
}
