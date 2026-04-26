import Foundation

extension APIClient {
    func initUploads(_ body: UploadInitRequest) async throws -> UploadInitResponse {
        try await request(path: "uploads/init", method: "POST", body: body)
    }

    func presignUploads(_ body: PresignRequest) async throws -> [PresignResult] {
        try await request(path: "uploads/presign", method: "POST", body: body)
    }

    func updateUploadStatus(_ body: UpdateStatusRequest) async throws {
        try await requestVoid(path: "uploads/status", method: "PATCH", body: body)
    }

    func completeMultipart(_ body: CompleteMultipartRequest) async throws {
        try await requestVoid(path: "uploads/complete-multipart", method: "POST", body: body)
    }

    func abortMultipart(_ body: AbortMultipartRequest) async throws {
        try await requestVoid(path: "uploads/abort-multipart", method: "POST", body: body)
    }

    func failUploads(_ body: FailUploadRequest) async throws {
        try await requestVoid(path: "uploads/fail", method: "POST", body: body)
    }
}
