import Foundation

extension APIClient {
    func fetchWorkspaces() async throws -> [Workspace] {
        try await request(path: "workspaces")
    }
}
