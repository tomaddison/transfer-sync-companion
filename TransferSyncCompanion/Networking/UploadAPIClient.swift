import Foundation

/// Protocol defining the API surface that UploadManager depends on.
/// Extracted for testability - `APIClient` conforms via its existing extension methods.
protocol UploadAPIClient: Sendable {
 func initUploads(_ body: UploadInitRequest) async throws -> UploadInitResponse
 func presignUploads(_ body: PresignRequest) async throws -> [PresignResult]
 func updateUploadStatus(_ body: UpdateStatusRequest) async throws
 func completeMultipart(_ body: CompleteMultipartRequest) async throws
 func abortMultipart(_ body: AbortMultipartRequest) async throws
 func failUploads(_ body: FailUploadRequest) async throws
 func fetchUnresolvedCounts(assetIds: [String]) async throws -> [String: Int]
 func autoStack(_ body: AutoStackRequest) async throws -> AutoStackResponse
 func fetchConfig() async throws -> CompanionConfig
 func fetchWorkspaces() async throws -> [Workspace]
 func fetchProjects(workspaceId: String) async throws -> [Project]
 func fetchFolders(projectId: String, parentId: String?) async throws -> [Folder]
 func fetchFolderAssets(projectId: String, parentId: String?) async throws -> [FolderAsset]
 func downloadPtx(assetId: String) async throws -> (data: Data, filename: String)
}

extension APIClient: UploadAPIClient {}
