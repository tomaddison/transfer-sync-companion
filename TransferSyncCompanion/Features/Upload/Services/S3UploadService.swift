import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "S3Upload")

enum S3UploadError: LocalizedError {
    case uploadFailed(statusCode: Int)
    case partUploadFailed(partIndex: Int, statusCode: Int)
    case missingETag(partIndex: Int)

    var errorDescription: String? {
        switch self {
        case .uploadFailed(let code): "S3 upload failed with status \(code)"
        case .partUploadFailed(let idx, let code): "S3 part \(idx) upload failed with status \(code)"
        case .missingETag(let idx): "Missing ETag in S3 response for part \(idx)"
        }
    }
}

enum S3UploadService {
    static let partSize = 10 * 1024 * 1024 // 10 MB
    static let maxConcurrentChunks = 3

    // MARK: - S3 Key Construction

    /// Mirrors `getRawS3Key()` from the web app: `assets/{mediaId}/{mediaId}.{ext}`
    static func rawS3Key(mediaId: String, fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "" : ".\(ext)"
        return "assets/\(mediaId)/\(mediaId)\(safeExt)"
    }

    // MARK: - Simple Upload

    static func uploadSimple(
        fileURL: URL,
        presignedURL: String,
        contentType: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let url = URL(string: presignedURL) else {
            throw S3UploadError.uploadFailed(statusCode: 0)
        }

        let fileData = try Data(contentsOf: fileURL)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate { sent, total in
            let pct = total > 0 ? Double(sent) / Double(total) : 0
            onProgress(min(pct, 1.0))
        }

        let (_, response) = try await URLSession.shared.upload(
            for: request, from: fileData, delegate: delegate
        )

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw S3UploadError.uploadFailed(statusCode: code)
        }

        onProgress(1.0)
        logger.info("Simple upload complete for \(fileURL.lastPathComponent)")
    }

    // MARK: - Multipart Upload

    static func uploadMultipart(
        fileURL: URL,
        partURLs: [String],
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [CompletedPart] {
        let fileData = try Data(contentsOf: fileURL)
        let totalParts = partURLs.count
        let tracker = MultipartProgressTracker(totalParts: totalParts, fileSize: fileData.count)

        return try await withThrowingTaskGroup(of: (Int, CompletedPart).self) { group in
            var results: [(Int, CompletedPart)] = []
            var nextPart = 0

            // Seed initial batch
            for _ in 0..<min(maxConcurrentChunks, totalParts) {
                let idx = nextPart
                nextPart += 1
                group.addTask {
                    try Task.checkCancellation()
                    return try await uploadPart(
                        fileData: fileData, partIndex: idx, url: partURLs[idx],
                        tracker: tracker, onProgress: onProgress
                    )
                }
            }

            // Process results and enqueue remaining parts
            for try await result in group {
                results.append(result)
                if nextPart < totalParts {
                    let idx = nextPart
                    nextPart += 1
                    group.addTask {
                        try Task.checkCancellation()
                        return try await uploadPart(
                            fileData: fileData, partIndex: idx, url: partURLs[idx],
                            tracker: tracker, onProgress: onProgress
                        )
                    }
                }
            }

            let sorted = results.sorted { $0.0 < $1.0 }.map(\.1)
            onProgress(1.0)
            logger.info("Multipart upload complete for \(fileURL.lastPathComponent) (\(totalParts) parts)")
            return sorted
        }
    }

    private static func uploadPart(
        fileData: Data,
        partIndex: Int,
        url: String,
        tracker: MultipartProgressTracker,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Int, CompletedPart) {
        let start = partIndex * partSize
        let end = min(fileData.count, start + partSize)
        let chunk = fileData[start..<end]

        guard let partURL = URL(string: url) else {
            throw S3UploadError.partUploadFailed(partIndex: partIndex, statusCode: 0)
        }

        var request = URLRequest(url: partURL)
        request.httpMethod = "PUT"

        let delegate = UploadProgressDelegate { sent, _ in
            let pct = tracker.update(partIndex: partIndex, bytesSent: Int(sent))
            onProgress(pct)
        }

        let (_, response) = try await URLSession.shared.upload(
            for: request, from: Data(chunk), delegate: delegate
        )

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw S3UploadError.partUploadFailed(partIndex: partIndex, statusCode: code)
        }

        guard let etag = http.value(forHTTPHeaderField: "ETag") else {
            throw S3UploadError.missingETag(partIndex: partIndex)
        }

        let cleanETag = etag.replacingOccurrences(of: "\"", with: "")
        return (partIndex, CompletedPart(eTag: cleanETag, partNumber: partIndex + 1))
    }
}

// MARK: - Progress Tracking

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        onProgress(totalBytesSent, totalBytesExpectedToSend)
    }
}

private final class MultipartProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var partBytes: [Int]
    private let fileSize: Int

    nonisolated init(totalParts: Int, fileSize: Int) {
        self.partBytes = Array(repeating: 0, count: totalParts)
        self.fileSize = fileSize
    }

    nonisolated func update(partIndex: Int, bytesSent: Int) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard partIndex >= 0 && partIndex < partBytes.count else { return 0 }
        partBytes[partIndex] = bytesSent
        let total = partBytes.reduce(0, +)
        return fileSize > 0 ? min(Double(total) / Double(fileSize), 1.0) : 0
    }
}
