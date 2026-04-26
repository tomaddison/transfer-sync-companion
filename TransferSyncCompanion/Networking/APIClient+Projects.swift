import Foundation

extension APIClient {
    func fetchProjects(workspaceId: String) async throws -> [Project] {
        try await request(
            path: "projects",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId)]
        )
    }
}
