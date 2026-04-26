import Foundation

extension APIClient {
    func fetchFolders(projectId: String, parentId: String? = nil) async throws -> [Folder] {
        var items = [URLQueryItem(name: "projectId", value: projectId)]
        if let parentId {
            items.append(URLQueryItem(name: "parentId", value: parentId))
        }
        return try await request(path: "folders", queryItems: items)
    }
}
