import XCTest
@testable import TransferSyncCompanion

final class UploadModelsTests: XCTestCase {

    // MARK: - PresignResult decoding

    func testPresignResult_simpleDecoding() throws {
        let json = """
        { "type": "simple", "key": "assets/m1/m1.wav", "url": "https://s3.example.com/presigned" }
        """

        let result = try JSONDecoder().decode(PresignResult.self, from: json.data(using: .utf8)!)

        if case .simple(let key, let url) = result {
            XCTAssertEqual(key, "assets/m1/m1.wav")
            XCTAssertEqual(url, "https://s3.example.com/presigned")
        } else {
            XCTFail("Expected simple presign result")
        }

        XCTAssertNil(result.multipartUploadId)
    }

    func testPresignResult_multipartDecoding() throws {
        let json = """
        {
            "type": "multipart",
            "key": "assets/m1/m1.wav",
            "uploadId": "upload-123",
            "urls": ["https://s3.example.com/part1", "https://s3.example.com/part2"]
        }
        """

        let result = try JSONDecoder().decode(PresignResult.self, from: json.data(using: .utf8)!)

        if case .multipart(let key, let uploadId, let urls) = result {
            XCTAssertEqual(key, "assets/m1/m1.wav")
            XCTAssertEqual(uploadId, "upload-123")
            XCTAssertEqual(urls.count, 2)
        } else {
            XCTFail("Expected multipart presign result")
        }

        XCTAssertEqual(result.multipartUploadId, "upload-123")
    }

    func testPresignResult_unknownType_throws() {
        let json = """
        { "type": "unknown", "key": "k" }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(PresignResult.self, from: json.data(using: .utf8)!)
        )
    }

    // MARK: - PresignInput encoding

    func testPresignInput_simpleEncoding() throws {
        let input = PresignInput.simple(
            key: "assets/m1/m1.wav",
            contentType: "audio/wav",
            metadata: UploadMetadata(mediaId: "m1", assetId: "a1")
        )

        let data = try JSONEncoder().encode(input)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "simple")
        XCTAssertEqual(dict["key"] as? String, "assets/m1/m1.wav")
        XCTAssertEqual(dict["contentType"] as? String, "audio/wav")
        XCTAssertNil(dict["totalParts"])
    }

    func testPresignInput_multipartEncoding() throws {
        let input = PresignInput.multipart(
            key: "assets/m1/m1.wav",
            contentType: "audio/wav",
            totalParts: 5,
            metadata: UploadMetadata(mediaId: "m1", assetId: "a1")
        )

        let data = try JSONEncoder().encode(input)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["type"] as? String, "multipart")
        XCTAssertEqual(dict["totalParts"] as? Int, 5)
    }

    // MARK: - UploadInitResponse decoding

    func testUploadInitResponse_decoding() throws {
        let json = """
        {
            "mediaPairs": [
                { "mediaId": "m1", "assetId": "a1" },
                { "mediaId": "m2", "assetId": "a2" }
            ],
            "batchId": "batch-001"
        }
        """

        let response = try JSONDecoder().decode(UploadInitResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.batchId, "batch-001")
        XCTAssertEqual(response.mediaPairs.count, 2)
        XCTAssertEqual(response.mediaPairs[0].mediaId, "m1")
        XCTAssertEqual(response.mediaPairs[1].assetId, "a2")
    }

    // MARK: - AutoStackResponse decoding

    func testAutoStackResponse_decoding() throws {
        let json = """
        {
            "stackId": "stack-001",
            "mediaPairs": [
                { "mediaId": "m1", "assetId": "a1", "versionName": "v3" }
            ],
            "batchId": "batch-002"
        }
        """

        let response = try JSONDecoder().decode(AutoStackResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.stackId, "stack-001")
        XCTAssertEqual(response.batchId, "batch-002")
        XCTAssertEqual(response.mediaPairs.count, 1)
        XCTAssertEqual(response.mediaPairs[0].versionName, "v3")
    }

    // MARK: - CompletedPart

    func testCompletedPart_customCodingKeys() throws {
        let part = CompletedPart(eTag: "abc123", partNumber: 1)
        let data = try JSONEncoder().encode(part)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["ETag"] as? String, "abc123")
        XCTAssertEqual(dict["PartNumber"] as? Int, 1)
    }

    // MARK: - FileInitData

    func testFileInitData_customCodingKeys() throws {
        let fileData = FileInitData(
            name: "test.wav",
            fileSize: 1024,
            fileType: "audio/wav",
            srcModified: "2024-01-01T00:00:00Z",
            projectId: "p1"
        )

        let data = try JSONEncoder().encode(fileData)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["name"] as? String, "test.wav")
        XCTAssertEqual(dict["file_size"] as? Int, 1024)
        XCTAssertEqual(dict["file_type"] as? String, "audio/wav")
        XCTAssertEqual(dict["src_modified"] as? String, "2024-01-01T00:00:00Z")
        XCTAssertEqual(dict["project_id"] as? String, "p1")
    }

    // MARK: - FolderAsset

    func testFolderAsset_decodingWithCustomKeys() throws {
        let json = """
        { "id": "fa-1", "name": "My Track", "asset_type": "stack" }
        """

        let asset = try JSONDecoder().decode(FolderAsset.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(asset.id, "fa-1")
        XCTAssertEqual(asset.name, "My Track")
        XCTAssertEqual(asset.assetType, "stack")
    }

    func testFolderAsset_nilName() throws {
        let json = """
        { "id": "fa-1", "name": null, "asset_type": "file" }
        """

        let asset = try JSONDecoder().decode(FolderAsset.self, from: json.data(using: .utf8)!)

        XCTAssertNil(asset.name)
    }

    // MARK: - CompanionConfig

    func testCompanionConfig_decoding() throws {
        let json = """
        { "multipartThresholdBytes": 52428800 }
        """

        let config = try JSONDecoder().decode(CompanionConfig.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(config.multipartThresholdBytes, 50 * 1024 * 1024)
    }

    // MARK: - APIError

    func testAPIError_descriptions() {
        XCTAssertNotNil(APIError.unauthorized.errorDescription)
        XCTAssertNotNil(APIError.serverError(statusCode: 500, message: "fail").errorDescription)
        XCTAssertNotNil(APIError.networkError(URLError(.notConnectedToInternet)).errorDescription)
        XCTAssertNotNil(APIError.noSession.errorDescription)

        let serverError = APIError.serverError(statusCode: 422, message: "Validation failed")
        XCTAssertTrue(serverError.errorDescription?.contains("422") ?? false)
        XCTAssertTrue(serverError.errorDescription?.contains("Validation failed") ?? false)
    }
}
