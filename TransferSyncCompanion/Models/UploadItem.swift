import Foundation

enum UploadItemStatus: String, Codable, Comparable, CaseIterable {
    case pending
    case uploading
    case processing
    case complete
    case failed
    case exhausted

    private var order: Int {
        switch self {
        case .pending: 0
        case .uploading: 1
        case .processing: 2
        case .complete: 3
        case .failed: 4
        case .exhausted: 5
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

    var displayLabel: String {
        switch self {
        case .pending: "Pending"
        case .uploading: "Uploading"
        case .processing: "Processing"
        case .complete: "Complete"
        case .failed: "Failed"
        case .exhausted: "Upload Failed"
        }
    }

    var isCancellable: Bool {
        self == .pending || self == .uploading || self == .failed || self == .exhausted
    }

    var isTerminal: Bool {
        self == .complete || self == .failed || self == .exhausted
    }
}

struct UploadItem: Identifiable, Codable {
    let id: String
    let assetId: String
    let fileName: String
    let fileSize: Int
    let fileURL: URL
    let s3Key: String
    let projectId: String
    let workspaceId: String
    let parentFolderId: String?
    let batchId: String
    var status: UploadItemStatus
    var progress: Double
    var s3UploadId: String?
    var unresolvedCommentCount: Int?
    var versionOf: String?
    var retryCount: Int

    init(
        id: String, assetId: String, fileName: String, fileSize: Int,
        fileURL: URL, s3Key: String, projectId: String, workspaceId: String,
        parentFolderId: String?, batchId: String, status: UploadItemStatus,
        progress: Double, s3UploadId: String? = nil,
        unresolvedCommentCount: Int? = nil, versionOf: String? = nil,
        retryCount: Int = 0
    ) {
        self.id = id; self.assetId = assetId; self.fileName = fileName
        self.fileSize = fileSize; self.fileURL = fileURL; self.s3Key = s3Key
        self.projectId = projectId; self.workspaceId = workspaceId
        self.parentFolderId = parentFolderId; self.batchId = batchId
        self.status = status; self.progress = progress
        self.s3UploadId = s3UploadId; self.unresolvedCommentCount = unresolvedCommentCount
        self.versionOf = versionOf; self.retryCount = retryCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        assetId = try container.decode(String.self, forKey: .assetId)
        fileName = try container.decode(String.self, forKey: .fileName)
        fileSize = try container.decode(Int.self, forKey: .fileSize)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        s3Key = try container.decode(String.self, forKey: .s3Key)
        projectId = try container.decode(String.self, forKey: .projectId)
        workspaceId = try container.decode(String.self, forKey: .workspaceId)
        parentFolderId = try container.decodeIfPresent(String.self, forKey: .parentFolderId)
        batchId = try container.decode(String.self, forKey: .batchId)
        status = try container.decode(UploadItemStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        s3UploadId = try container.decodeIfPresent(String.self, forKey: .s3UploadId)
        unresolvedCommentCount = try container.decodeIfPresent(Int.self, forKey: .unresolvedCommentCount)
        versionOf = try container.decodeIfPresent(String.self, forKey: .versionOf)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
    }
}
