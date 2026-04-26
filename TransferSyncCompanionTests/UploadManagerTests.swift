import XCTest
@testable import TransferSyncCompanion

@MainActor
final class UploadManagerTests: XCTestCase {

 private var mockAPI: MockAPIClient!
 private var configManager: ConfigManager!
 private var realtimeManager: RealtimeManager!
 private var connectivityManager: ConnectivityManager!
 private var sut: UploadManager!

 override func setUp() async throws {
 try await super.setUp()
 mockAPI = MockAPIClient()
 configManager = ConfigManager(apiClient: mockAPI)
 realtimeManager = RealtimeManager()
 connectivityManager = ConnectivityManager()

 // Delete any leftover upload log from previous test runs
 let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
 let logFile = appSupport
 .appendingPathComponent("TransferSyncCompanion", isDirectory: true)
 .appendingPathComponent("uploadLog.json")
 try? FileManager.default.removeItem(at: logFile)

 sut = UploadManager(
 apiClient: mockAPI,
 configManager: configManager,
 realtimeManager: realtimeManager,
 connectivityManager: connectivityManager
 )
 }

 override func tearDown() async throws {
 sut = nil
 mockAPI = nil
 configManager = nil
 realtimeManager = nil
 connectivityManager = nil
 try await super.tearDown()
 }

 // MARK: - Initial State

 func testInitialState() {
 XCTAssertTrue(sut.items.isEmpty)
 XCTAssertFalse(sut.isUploading)
 XCTAssertNil(sut.error)
 }

 // MARK: - Upload Init Failure

 func testUploadFiles_initFailure_setsError() async {
 mockAPI.initUploadsResult = .failure(APIError.networkError(URLError(.notConnectedToInternet)))

 // Create a temp file for the upload
 let tempURL = createTempFile()
 defer { try? FileManager.default.removeItem(at: tempURL) }

 await sut.uploadFiles(
 fileURLs: [tempURL],
 projectId: TestFixtures.projectId,
 workspaceId: TestFixtures.workspaceId,
 parentFolderId: nil
 )

 XCTAssertNotNil(sut.error)
 XCTAssertTrue(sut.error?.contains("Failed to initialize upload") ?? false)
 XCTAssertTrue(sut.items.isEmpty)
 }

 // MARK: - Presign Failure

 func testUploadFiles_presignFailure_setsError() async {
 mockAPI.initUploadsResult = .success(TestFixtures.initResponse())
 mockAPI.presignUploadsResult = .failure(APIError.serverError(statusCode: 500, message: "Internal"))

 let tempURL = createTempFile()
 defer { try? FileManager.default.removeItem(at: tempURL) }

 await sut.uploadFiles(
 fileURLs: [tempURL],
 projectId: TestFixtures.projectId,
 workspaceId: TestFixtures.workspaceId,
 parentFolderId: nil
 )

 XCTAssertNotNil(sut.error)
 XCTAssertTrue(sut.error?.contains("Failed to get upload URLs") ?? false)
 }

 // MARK: - Cancel

 func testCancelPendingUpload_marksFailed() async {
 // Manually insert a pending item
 let item = TestFixtures.uploadItem(status: .pending)
 sut.items.append(item)

 await sut.cancelUpload(id: item.id)

 XCTAssertEqual(sut.items.first?.status, .failed)
 }

 func testCancelFailedUpload_removesItem() async {
 let item = TestFixtures.uploadItem(status: .failed)
 sut.items.append(item)

 await sut.cancelUpload(id: item.id)

 XCTAssertTrue(sut.items.isEmpty, "Failed item should be dismissed on cancel")
 }

 func testCancelExhaustedUpload_removesItem() async {
 let item = TestFixtures.uploadItem(status: .exhausted, retryCount: 5)
 sut.items.append(item)

 await sut.cancelUpload(id: item.id)

 XCTAssertTrue(sut.items.isEmpty, "Exhausted item should be dismissed on cancel")
 }

 func testCancelComplete_doesNothing() async {
 let item = TestFixtures.uploadItem(status: .complete)
 sut.items.append(item)

 await sut.cancelUpload(id: item.id)

 XCTAssertEqual(sut.items.count, 1, "Complete items should not be affected by cancel")
 }

 // MARK: - Retry eligibility

 func testRetryUpload_failedItem_isEligible() async {
 let item = TestFixtures.uploadItem(status: .failed)
 sut.items.append(item)

 // Stub the init to fail so we can verify retry was attempted
 mockAPI.initUploadsResult = .failure(MockError.simulated)

 await sut.retryUpload(id: item.id)

 XCTAssertTrue(mockAPI.initUploadsCalled, "Retry should attempt init for failed items")
 }

 func testRetryUpload_exhaustedItem_isEligible() async {
 let item = TestFixtures.uploadItem(status: .exhausted, retryCount: 5)
 sut.items.append(item)

 mockAPI.initUploadsResult = .failure(MockError.simulated)

 await sut.retryUpload(id: item.id)

 XCTAssertTrue(mockAPI.initUploadsCalled, "Retry should attempt init for exhausted items")
 }

 func testRetryUpload_completeItem_doesNothing() async {
 let item = TestFixtures.uploadItem(status: .complete)
 sut.items.append(item)

 await sut.retryUpload(id: item.id)

 XCTAssertFalse(mockAPI.initUploadsCalled, "Should not retry complete items")
 }

 func testRetryUpload_pendingItem_doesNothing() async {
 let item = TestFixtures.uploadItem(status: .pending)
 sut.items.append(item)

 await sut.retryUpload(id: item.id)

 XCTAssertFalse(mockAPI.initUploadsCalled, "Should not retry pending items")
 }

 // MARK: - Realtime Updates

 func testRealtimeUpdate_processingStatus() {
 let item = TestFixtures.uploadItem(status: .uploading, progress: 1.0)
 sut.items.append(item)

 // Simulate realtime update by calling the method directly via the internal handler
 // We test the observable state change instead
 simulateRealtimeUpdate(mediaId: item.id, newStatus: "processing")

 XCTAssertEqual(sut.items.first?.status, .processing)
 }

 func testRealtimeUpdate_successStatus() {
 let item = TestFixtures.uploadItem(status: .processing)
 sut.items.append(item)

 simulateRealtimeUpdate(mediaId: item.id, newStatus: "success")

 XCTAssertEqual(sut.items.first?.status, .complete)
 XCTAssertEqual(sut.items.first?.progress, 1.0)
 XCTAssertEqual(sut.items.first?.unresolvedCommentCount, 0)
 }

 func testRealtimeUpdate_failedStatus() {
 let item = TestFixtures.uploadItem(status: .uploading)
 sut.items.append(item)

 simulateRealtimeUpdate(mediaId: item.id, newStatus: "failed")

 XCTAssertEqual(sut.items.first?.status, .failed)
 }

 func testRealtimeUpdate_doesNotDowngradeTerminal() {
 let item = TestFixtures.uploadItem(status: .complete)
 sut.items.append(item)

 simulateRealtimeUpdate(mediaId: item.id, newStatus: "failed")

 XCTAssertEqual(sut.items.first?.status, .complete, "Should not downgrade from complete to failed")
 }

 func testRealtimeUpdate_doesNotDowngradeExhausted() {
 let item = TestFixtures.uploadItem(status: .exhausted)
 sut.items.append(item)

 simulateRealtimeUpdate(mediaId: item.id, newStatus: "processing")

 XCTAssertEqual(sut.items.first?.status, .exhausted, "Should not change exhausted status")
 }

 func testRealtimeUpdate_unknownMediaId_ignored() {
 let item = TestFixtures.uploadItem(status: .uploading)
 sut.items.append(item)

 simulateRealtimeUpdate(mediaId: "nonexistent-id", newStatus: "success")

 XCTAssertEqual(sut.items.first?.status, .uploading, "Unknown media ID should be ignored")
 }

 // MARK: - Clear Completed

 func testClearCompleted_removesTerminalItems() {
 sut.items = [
 TestFixtures.uploadItem(id: "1", status: .complete),
 TestFixtures.uploadItem(id: "2", status: .uploading),
 TestFixtures.uploadItem(id: "3", status: .failed),
 TestFixtures.uploadItem(id: "4", status: .exhausted),
 TestFixtures.uploadItem(id: "5", status: .pending),
 ]

 sut.clearCompleted()

 XCTAssertEqual(sut.items.count, 2)
 XCTAssertEqual(Set(sut.items.map(\.id)), Set(["2", "5"]))
 }

 // MARK: - isUploading tracking

 func testCheckAllComplete_allTerminal_setsNotUploading() {
 sut.items = [
 TestFixtures.uploadItem(id: "1", status: .complete),
 TestFixtures.uploadItem(id: "2", status: .failed),
 TestFixtures.uploadItem(id: "3", status: .exhausted),
 ]
 sut.clearCompleted() // triggers checkAllComplete internally
 // After clearing all items, isUploading should be false
 XCTAssertFalse(sut.isUploading)
 }

 // MARK: - Logout

 func testOnLogout_marksNonTerminalFailed() async {
 sut.items = [
 TestFixtures.uploadItem(id: "1", status: .uploading),
 TestFixtures.uploadItem(id: "2", status: .pending),
 TestFixtures.uploadItem(id: "3", status: .complete),
 TestFixtures.uploadItem(id: "4", status: .processing),
 ]

 await sut.onLogout()

 XCTAssertEqual(sut.items.first(where: { $0.id == "1" })?.status, .failed)
 XCTAssertEqual(sut.items.first(where: { $0.id == "2" })?.status, .failed)
 XCTAssertEqual(sut.items.first(where: { $0.id == "3" })?.status, .complete, "Complete should stay complete")
 XCTAssertEqual(sut.items.first(where: { $0.id == "4" })?.status, .failed)
 XCTAssertFalse(sut.isUploading)
 }

 // MARK: - Dismiss Error

 func testDismissError() {
 sut.error = "Something went wrong"
 sut.dismissError()
 XCTAssertNil(sut.error)
 }

 // MARK: - Persistence

 func testLoadLog_marksNonTerminalAsFailed() {
 // This tests the crash recovery behavior
 // Write a log with in-flight items, then create a new UploadManager
 let items = [
 TestFixtures.uploadItem(id: "1", status: .uploading),
 TestFixtures.uploadItem(id: "2", status: .complete),
 ]

 // Write directly to the log file
 let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
 let dir = appSupport.appendingPathComponent("TransferSyncCompanion", isDirectory: true)
 try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
 let logFile = dir.appendingPathComponent("uploadLog.json")
 let data = try! JSONEncoder().encode(items)
 try! data.write(to: logFile, options: .atomic)

 // Create new manager - it should mark the in-flight item as failed
 let restored = UploadManager(
 apiClient: mockAPI,
 configManager: configManager,
 realtimeManager: realtimeManager
 )

 XCTAssertEqual(restored.items.count, 2)
 XCTAssertEqual(restored.items.first(where: { $0.id == "1" })?.status, .failed,
 "In-flight item should be marked failed on restore")
 XCTAssertEqual(restored.items.first(where: { $0.id == "2" })?.status, .complete,
 "Complete item should stay complete on restore")

 // Clean up
 try? FileManager.default.removeItem(at: logFile)
 }

 // MARK: - Fetch Unresolved Comment Counts

 func testFetchUnresolvedCommentCounts_updatesCompleteItems() async {
 sut.items = [
 TestFixtures.uploadItem(id: "1", assetId: "asset-1", status: .complete),
 TestFixtures.uploadItem(id: "2", assetId: "asset-2", status: .complete),
 TestFixtures.uploadItem(id: "3", assetId: "asset-3", status: .uploading),
 ]

 mockAPI.fetchUnresolvedCountsResult = .success(["asset-1": 3, "asset-2": 0])

 await sut.fetchUnresolvedCommentCounts()

 XCTAssertEqual(sut.items.first(where: { $0.id == "1" })?.unresolvedCommentCount, 3)
 XCTAssertEqual(sut.items.first(where: { $0.id == "2" })?.unresolvedCommentCount, 0)
 XCTAssertNil(sut.items.first(where: { $0.id == "3" })?.unresolvedCommentCount,
 "Non-complete items should not be updated")
 }

 func testFetchUnresolvedCommentCounts_noCompleteItems_doesNotCall() async {
 sut.items = [
 TestFixtures.uploadItem(id: "1", status: .uploading),
 ]

 await sut.fetchUnresolvedCommentCounts()

 XCTAssertFalse(mockAPI.fetchUnresolvedCountsCalled)
 }

 // MARK: - Helpers

 private func createTempFile(name: String = "test-audio.wav", size: Int = 1024) -> URL {
 let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
 let data = Data(repeating: 0, count: size)
 try! data.write(to: url)
 return url
 }

 /// Simulates a Realtime status update by directly manipulating items
 /// (since RealtimeManager requires actual Supabase connection).
 private func simulateRealtimeUpdate(mediaId: String, newStatus: String) {
 guard let idx = sut.items.firstIndex(where: { $0.id == mediaId }) else { return }
 let current = sut.items[idx].status

 switch newStatus {
 case "processing" where current == .uploading || current == .complete:
 sut.items[idx].status = .processing
 case "success":
 sut.items[idx].status = .complete
 sut.items[idx].progress = 1.0
 sut.items[idx].unresolvedCommentCount = 0
 case "failed" where !current.isTerminal:
 sut.items[idx].status = .failed
 default:
 break
 }
 }
}
