import Foundation
@testable import TransferSyncCompanion

@MainActor
final class MockAPIClient: UploadAPIClient, @unchecked Sendable {

    // MARK: - Call tracking

    var initUploadsCalled = false
    var presignUploadsCalled = false
    var updateUploadStatusCalls: [UpdateStatusRequest] = []
    var completeMultipartCalled = false
    var failUploadsCalls: [FailUploadRequest] = []
    var abortMultipartCalled = false
    var fetchUnresolvedCountsCalled = false
    var autoStackCalled = false
    var fetchConfigCalled = false

    // MARK: - Stubbed responses / errors

    var initUploadsResult: Result<UploadInitResponse, Error> = .failure(MockError.notStubbed)
    var presignUploadsResult: Result<[PresignResult], Error> = .failure(MockError.notStubbed)
    var updateUploadStatusError: Error?
    var completeMultipartError: Error?
    var failUploadsError: Error?
    var abortMultipartError: Error?
    var fetchUnresolvedCountsResult: Result<[String: Int], Error> = .success([:])
    var autoStackResult: Result<AutoStackResponse, Error> = .failure(MockError.notStubbed)
    var fetchConfigResult: Result<CompanionConfig, Error> = .success(CompanionConfig(multipartThresholdBytes: 100 * 1024 * 1024))

    // MARK: - Protocol conformance

    nonisolated func initUploads(_ body: UploadInitRequest) async throws -> UploadInitResponse {
        await MainActor.run { initUploadsCalled = true }
        return try await MainActor.run { try initUploadsResult.get() }
    }

    nonisolated func presignUploads(_ body: PresignRequest) async throws -> [PresignResult] {
        await MainActor.run { presignUploadsCalled = true }
        return try await MainActor.run { try presignUploadsResult.get() }
    }

    nonisolated func updateUploadStatus(_ body: UpdateStatusRequest) async throws {
        await MainActor.run { updateUploadStatusCalls.append(body) }
        if let error = await MainActor.run(body: { updateUploadStatusError }) { throw error }
    }

    nonisolated func completeMultipart(_ body: CompleteMultipartRequest) async throws {
        await MainActor.run { completeMultipartCalled = true }
        if let error = await MainActor.run(body: { completeMultipartError }) { throw error }
    }

    nonisolated func abortMultipart(_ body: AbortMultipartRequest) async throws {
        await MainActor.run { abortMultipartCalled = true }
        if let error = await MainActor.run(body: { abortMultipartError }) { throw error }
    }

    nonisolated func failUploads(_ body: FailUploadRequest) async throws {
        await MainActor.run { failUploadsCalls.append(body) }
        if let error = await MainActor.run(body: { failUploadsError }) { throw error }
    }

    nonisolated func fetchUnresolvedCounts(assetIds: [String]) async throws -> [String: Int] {
        await MainActor.run { fetchUnresolvedCountsCalled = true }
        return try await MainActor.run { try fetchUnresolvedCountsResult.get() }
    }

    nonisolated func autoStack(_ body: AutoStackRequest) async throws -> AutoStackResponse {
        await MainActor.run { autoStackCalled = true }
        return try await MainActor.run { try autoStackResult.get() }
    }

    nonisolated func fetchConfig() async throws -> CompanionConfig {
        await MainActor.run { fetchConfigCalled = true }
        return try await MainActor.run { try fetchConfigResult.get() }
    }

    nonisolated func fetchWorkspaces() async throws -> [Workspace] {
        []
    }

    nonisolated func fetchProjects(workspaceId: String) async throws -> [Project] {
        []
    }

    nonisolated func fetchFolders(projectId: String, parentId: String?) async throws -> [Folder] {
        []
    }

    nonisolated func fetchFolderAssets(projectId: String, parentId: String?) async throws -> [FolderAsset] {
        []
    }
}

enum MockError: Error {
    case notStubbed
    case simulated
}
