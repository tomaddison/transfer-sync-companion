import Foundation

extension APIClient {
    /// Downloads the PTX file for a given asset's comments.
    /// Returns the raw PTX data and the suggested filename from the Content-Disposition header.
    func downloadPtx(assetId: String) async throws -> (data: Data, filename: String) {
        let (data, response) = try await requestRawData(
            path: "export/ptx",
            queryItems: [URLQueryItem(name: "assetId", value: assetId)]
        )

        // Extract filename from Content-Disposition header, fallback to "export.ptx"
        var filename = "export.ptx"
        if let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           let range = disposition.range(of: "filename=\"") {
            let start = range.upperBound
            if let end = disposition[start...].firstIndex(of: "\"") {
                filename = String(disposition[start..<end])
            }
        }

        return (data, filename)
    }
}
