import Foundation

extension APIClient {
    /// Fetches unresolved comment counts for the given asset IDs.
    /// Returns a dictionary mapping asset ID to unresolved count.
    func fetchUnresolvedCounts(assetIds: [String]) async throws -> [String: Int] {
        guard !assetIds.isEmpty else { return [:] }

        let joined = assetIds.joined(separator: ",")
        return try await request(
            path: "comments/unresolved-counts",
            queryItems: [URLQueryItem(name: "assetIds", value: joined)]
        )
    }
}
