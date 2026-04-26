import Foundation

// MARK: - Upload Init

struct UploadInitRequest: Encodable {
    let files: [FileInitData]
    let parentId: String?
    let projectId: String
    let workspaceId: String
}

struct FileInitData: Encodable {
    let name: String
    let fileSize: Int
    let fileType: String?
    let srcModified: String
    let projectId: String

    enum CodingKeys: String, CodingKey {
        case name
        case fileSize = "file_size"
        case fileType = "file_type"
        case srcModified = "src_modified"
        case projectId = "project_id"
    }
}

struct UploadInitResponse: Decodable {
    let mediaPairs: [MediaPair]
    let batchId: String
}

struct MediaPair: Decodable {
    let mediaId: String
    let assetId: String
}

// MARK: - Presign

struct PresignRequest: Encodable {
    let inputs: [PresignInput]
    let projectId: String
}

struct UploadMetadata: Codable {
    let mediaId: String
    let assetId: String
}

enum PresignInput: Encodable {
    case simple(key: String, contentType: String, metadata: UploadMetadata)
    case multipart(key: String, contentType: String, totalParts: Int, metadata: UploadMetadata)

    private enum CodingKeys: String, CodingKey {
        case type, key, contentType, metadata, totalParts
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .simple(let key, let contentType, let metadata):
            try container.encode("simple", forKey: .type)
            try container.encode(key, forKey: .key)
            try container.encode(contentType, forKey: .contentType)
            try container.encode(metadata, forKey: .metadata)
        case .multipart(let key, let contentType, let totalParts, let metadata):
            try container.encode("multipart", forKey: .type)
            try container.encode(key, forKey: .key)
            try container.encode(contentType, forKey: .contentType)
            try container.encode(totalParts, forKey: .totalParts)
            try container.encode(metadata, forKey: .metadata)
        }
    }
}

enum PresignResult: Decodable {
    case simple(key: String, url: String)
    case multipart(key: String, uploadId: String, urls: [String])

    var multipartUploadId: String? {
        if case .multipart(_, let uploadId, _) = self { return uploadId }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case type, key, url, uploadId, urls
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "simple":
            let key = try container.decode(String.self, forKey: .key)
            let url = try container.decode(String.self, forKey: .url)
            self = .simple(key: key, url: url)
        case "multipart":
            let key = try container.decode(String.self, forKey: .key)
            let uploadId = try container.decode(String.self, forKey: .uploadId)
            let urls = try container.decode([String].self, forKey: .urls)
            self = .multipart(key: key, uploadId: uploadId, urls: urls)
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [CodingKeys.type], debugDescription: "Unknown presign type: \(type)")
            )
        }
    }
}

// MARK: - Upload Status

struct UpdateStatusRequest: Encodable {
    let mediaId: String
    let projectId: String
    let status: String?
    let originalPath: String?
    let uploadCompletedAt: String?
}

// MARK: - Complete Multipart

struct CompleteMultipartRequest: Encodable {
    let key: String
    let uploadId: String
    let parts: [CompletedPart]
    let projectId: String
}

struct CompletedPart: Codable {
    let eTag: String
    let partNumber: Int

    enum CodingKeys: String, CodingKey {
        case eTag = "ETag"
        case partNumber = "PartNumber"
    }
}

// MARK: - Abort Multipart

struct AbortMultipartRequest: Encodable {
    let key: String
    let uploadId: String
    let projectId: String
}

// MARK: - Auto-Stack

struct FolderAsset: Decodable {
    let id: String
    let name: String?
    let assetType: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case assetType = "asset_type"
    }
}

struct AutoStackRequest: Encodable {
    let files: [FileInitData]
    let parentId: String?
    let projectId: String
    let targetId: String
    let targetType: String
    let workspaceId: String
}

struct AutoStackMediaPair: Decodable {
    let mediaId: String
    let assetId: String
    let versionName: String?
}

struct AutoStackResponse: Decodable {
    let stackId: String
    let mediaPairs: [AutoStackMediaPair]
    let batchId: String
}

// MARK: - Fail Upload

struct FailUploadRequest: Encodable {
    let mediaIds: [String]
    let projectId: String
}
