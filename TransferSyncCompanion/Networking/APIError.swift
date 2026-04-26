import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case networkError(Error)
    case decodingError(Error)
    case noSession

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "You are not authorized. Please sign in again."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to read server response: \(error.localizedDescription)"
        case .noSession:
            return "No active session. Please sign in."
        }
    }
}
