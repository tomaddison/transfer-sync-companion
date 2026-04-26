import Foundation

extension APIClient {
    func fetchFolderAssets(projectId: String, parentId: String? = nil) async throws -> [FolderAsset] {
        var items = [URLQueryItem(name: "projectId", value: projectId)]
        if let parentId {
            items.append(URLQueryItem(name: "parentId", value: parentId))
        }
        return try await request(path: "assets", queryItems: items)
    }

    func autoStack(_ body: AutoStackRequest) async throws -> AutoStackResponse {
        try await request(path: "versioning/auto-stack", method: "POST", body: body)
    }
}
