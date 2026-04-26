import Foundation

extension APIClient {
    func fetchConfig() async throws -> CompanionConfig {
        try await request(path: "config")
    }
}
