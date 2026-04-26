import Foundation
@testable import TransferSyncCompanion

enum TestFixtures {

    static let projectId = "project-123"
    static let workspaceId = "workspace-456"
    static let batchId = "batch-789"
    static let mediaId = "media-001"
    static let assetId = "asset-001"

    static func uploadItem(
        id: String = mediaId,
        assetId: String = TestFixtures.assetId,
        fileName: String = "test-audio.wav",
        fileSize: Int = 1024,
        s3Key: String = "assets/media-001/media-001.wav",
        projectId: String = TestFixtures.projectId,
        workspaceId: String = TestFixtures.workspaceId,
        parentFolderId: String? = nil,
        batchId: String = TestFixtures.batchId,
        status: UploadItemStatus = .pending,
        progress: Double = 0,
        s3UploadId: String? = nil,
        unresolvedCommentCount: Int? = nil,
        versionOf: String? = nil,
        retryCount: Int = 0
    ) -> UploadItem {
        UploadItem(
            id: id, assetId: assetId, fileName: fileName, fileSize: fileSize,
            fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
            s3Key: s3Key, projectId: projectId, workspaceId: workspaceId,
            parentFolderId: parentFolderId, batchId: batchId,
            status: status, progress: progress, s3UploadId: s3UploadId,
            unresolvedCommentCount: unresolvedCommentCount, versionOf: versionOf,
            retryCount: retryCount
        )
    }

    static func initResponse(
        mediaId: String = TestFixtures.mediaId,
        assetId: String = TestFixtures.assetId,
        batchId: String = TestFixtures.batchId
    ) -> UploadInitResponse {
        UploadInitResponse(
            mediaPairs: [MediaPair(mediaId: mediaId, assetId: assetId)],
            batchId: batchId
        )
    }

    static func simplePresignResult(
        key: String = "assets/media-001/media-001.wav",
        url: String = "https://s3.example.com/presigned"
    ) -> PresignResult {
        .simple(key: key, url: url)
    }
}
