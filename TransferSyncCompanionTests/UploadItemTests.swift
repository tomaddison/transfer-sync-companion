import XCTest
@testable import TransferSyncCompanion

final class UploadItemStatusTests: XCTestCase {

    // MARK: - isTerminal

    func testIsTerminal() {
        let terminal: Set<UploadItemStatus> = [.complete, .failed, .exhausted]
        for status in UploadItemStatus.allCases {
            XCTAssertEqual(status.isTerminal, terminal.contains(status),
                           "\(status) isTerminal should be \(terminal.contains(status))")
        }
    }

    // MARK: - isCancellable

    func testIsCancellable() {
        let cancellable: Set<UploadItemStatus> = [.pending, .uploading, .failed]
        for status in UploadItemStatus.allCases {
            XCTAssertEqual(status.isCancellable, cancellable.contains(status),
                           "\(status) isCancellable should be \(cancellable.contains(status))")
        }
    }

    // MARK: - displayLabel

    func testDisplayLabel() {
        let expected: [UploadItemStatus: String] = [
            .pending: "Pending",
            .uploading: "Uploading",
            .processing: "Processing",
            .complete: "Complete",
            .failed: "Failed",
            .exhausted: "Upload Failed",
        ]
        for (status, label) in expected {
            XCTAssertEqual(status.displayLabel, label)
        }
    }

    // MARK: - Comparable ordering

    func testOrdering() {
        let ordered: [UploadItemStatus] = [.pending, .uploading, .processing, .complete, .failed, .exhausted]
        for i in 0..<ordered.count - 1 {
            XCTAssertTrue(ordered[i] < ordered[i + 1],
                          "\(ordered[i]) should sort before \(ordered[i + 1])")
        }
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip_allStatuses() throws {
        let statuses: [UploadItemStatus] = [.pending, .uploading, .processing, .complete, .failed, .exhausted]
        for status in statuses {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(UploadItemStatus.self, from: data)
            XCTAssertEqual(decoded, status, "Round-trip failed for \(status)")
        }
    }

    func testCodableRawValue_exhausted() throws {
        let data = try JSONEncoder().encode(UploadItemStatus.exhausted)
        let string = String(data: data, encoding: .utf8)
        XCTAssertEqual(string, "\"exhausted\"")
    }
}

final class UploadItemTests: XCTestCase {

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let item = TestFixtures.uploadItem(
            status: .uploading,
            progress: 0.5,
            versionOf: "v3",
            retryCount: 2
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(UploadItem.self, from: data)

        XCTAssertEqual(decoded.id, item.id)
        XCTAssertEqual(decoded.fileName, item.fileName)
        XCTAssertEqual(decoded.status, UploadItemStatus.uploading)
        XCTAssertEqual(decoded.progress, 0.5)
        XCTAssertEqual(decoded.retryCount, 2)
        XCTAssertEqual(decoded.versionOf, "v3")
    }

    func testDecodingBackwardCompat_missingRetryCount() throws {
        // Simulate JSON from before retryCount was added
        let json = """
        {
            "id": "media-001",
            "assetId": "asset-001",
            "fileName": "test.wav",
            "fileSize": 1024,
            "fileURL": "file:///tmp/test.wav",
            "s3Key": "assets/media-001/media-001.wav",
            "projectId": "project-123",
            "workspaceId": "workspace-456",
            "batchId": "batch-789",
            "status": "pending",
            "progress": 0
        }
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UploadItem.self, from: data)

        XCTAssertEqual(decoded.retryCount, 0, "retryCount should default to 0 for old JSON")
        XCTAssertNil(decoded.parentFolderId)
        XCTAssertNil(decoded.s3UploadId)
        XCTAssertNil(decoded.unresolvedCommentCount)
        XCTAssertNil(decoded.versionOf)
    }

    func testDecodingBackwardCompat_exhaustedStatus() throws {
        let json = """
        {
            "id": "media-001",
            "assetId": "asset-001",
            "fileName": "test.wav",
            "fileSize": 1024,
            "fileURL": "file:///tmp/test.wav",
            "s3Key": "assets/media-001/media-001.wav",
            "projectId": "project-123",
            "workspaceId": "workspace-456",
            "batchId": "batch-789",
            "status": "exhausted",
            "progress": 0.0,
            "retryCount": 5
        }
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UploadItem.self, from: data)

        XCTAssertEqual(decoded.status, .exhausted)
        XCTAssertEqual(decoded.retryCount, 5)
        XCTAssertTrue(decoded.status.isTerminal)
    }

    // MARK: - Default init values

    func testDefaultRetryCount() {
        let item = TestFixtures.uploadItem()
        XCTAssertEqual(item.retryCount, 0)
    }

    func testDefaultOptionals() {
        let item = TestFixtures.uploadItem()
        XCTAssertNil(item.s3UploadId)
        XCTAssertNil(item.unresolvedCommentCount)
        XCTAssertNil(item.versionOf)
    }
}
