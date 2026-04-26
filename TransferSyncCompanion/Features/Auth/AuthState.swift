import Foundation

enum AuthState: Equatable {
    case unknown
    case loggedOut
    case loggingIn
    case loggedIn(user: AuthUser)
}

struct AuthUser: Equatable {
    let id: String
    let email: String
    let displayName: String
    let avatarURL: URL?
}
