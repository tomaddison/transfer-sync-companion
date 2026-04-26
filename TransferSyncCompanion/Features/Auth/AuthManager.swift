import Foundation
import Supabase
import AppKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "AuthManager")

@Observable
@MainActor
final class AuthManager {
 private(set) var authState: AuthState = .unknown

 let supabase: SupabaseClient
 private var authStateListenerTask: Task<Void, Never>?

 /// Random nonce generated per login attempt for CSRF protection.
 private var pendingState: String?

 init(supabase: SupabaseClient = SupabaseClientFactory.shared) {
 self.supabase = supabase
 logger.info("AuthManager initialized")
 }

 // MARK: - Auth State Listener

 /// Listens for auth state changes (token refresh, sign-out, sign-in).
 /// Skips the initial session event - startup state is handled by `restoreSession()`.
 func startAuthStateListener() {
 logger.info("Starting auth state listener")
 authStateListenerTask?.cancel()
 authStateListenerTask = Task { [weak self] in
 guard let self else { return }
 for await (event, session) in self.supabase.auth.authStateChanges {
 guard !Task.isCancelled else { return }
 logger.info("Auth state change event: \(String(describing: event))")
 if event == .initialSession { continue }
 switch event {
 case .signedOut:
 logger.info("User signed out via auth state listener")
 self.authState = .loggedOut
 case .signedIn, .tokenRefreshed:
 if let session {
 logger.info("User signed in/token refreshed - user: \(session.user.id.uuidString)")
 self.authState = .loggedIn(user: Self.buildUser(from: session.user))
 }
 default:
 logger.debug("Unhandled auth event: \(String(describing: event))")
 break
 }
 }
 }
 }

 // MARK: - Session Restore

 /// Resolves the initial `.unknown` state on launch by checking for a stored session.
 func restoreSession() async {
 logger.info("Attempting to restore session")
 do {
 let session = try await supabase.auth.session
 if session.isExpired {
 logger.warning("Stored session is expired, attempting refresh")
 await attemptRefreshOrClear()
 return
 }
 logger.info("Session restored for user: \(session.user.id.uuidString)")
 authState = .loggedIn(user: Self.buildUser(from: session.user))
 } catch {
 logger.error("Failed to restore session: \(error.localizedDescription)")
 // No stored session - try refresh in case Keychain retains a refresh token
 // from a previous install
 await attemptRefreshOrClear()
 }
 }

 /// Attempts to refresh the session using a stored refresh token.
 /// Falls back to clearing the session on failure.
 private func attemptRefreshOrClear() async {
 do {
 try await supabase.auth.refreshSession()
 let refreshed = try await supabase.auth.session
 logger.info("Session refreshed for user: \(refreshed.user.id.uuidString)")
 authState = .loggedIn(user: Self.buildUser(from: refreshed.user))
 } catch {
 logger.error("Token refresh failed: \(error.localizedDescription)")
 await clearSession()
 }
 }

 // MARK: - Login

 func initiateLogin() {
 let state = generateState()
 pendingState = state
 let url = AppConstants.loginURL(state: state)
 logger.info("Initiating login, opening browser")
 authState = .loggingIn
 NSWorkspace.shared.open(url)
 }

 func cancelLogin() {
 logger.info("Login cancelled by user")
 pendingState = nil
 authState = .loggedOut
 }

 // MARK: - URL Callback

 /// Handles `transfersync://auth/callback?access_token=...&refresh_token=...&state=...`
 func handleCallback(url: URL) async {
 logger.info("Received auth callback")

 guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
 logger.error("Failed to parse callback URL into components")
 authState = .loggedOut
 return
 }

 guard components.scheme == AppConstants.urlScheme else {
 logger.error("Unexpected URL scheme: \(components.scheme ?? "nil"), expected: \(AppConstants.urlScheme)")
 return
 }

 guard components.host == "auth" else {
 logger.error("Unexpected URL host: \(components.host ?? "nil"), expected: auth")
 return
 }

 guard components.path == "/callback" else {
 logger.error("Unexpected URL path: \(components.path), expected: /callback")
 return
 }

 let params = parseCallbackParameters(from: components)

 let accessToken = params["access_token"]
 let refreshToken = params["refresh_token"]
 let callbackState = params["state"]

 logger.info("Parsed callback - accessToken present: \(accessToken != nil), refreshToken present: \(refreshToken != nil), state present: \(callbackState != nil)")

 guard let accessToken, let refreshToken else {
 logger.error("Missing tokens in callback URL")
 authState = .loggedOut
 return
 }

 // Verify the state parameter matches the one generated during initiateLogin().
 // This prevents CSRF/session-fixation attacks where an attacker tricks the app
 // into accepting tokens from the attacker's auth session.
 guard let expected = pendingState, callbackState == expected else {
 logger.error("State mismatch - expected: \(self.pendingState != nil ? "[set]" : "[nil]"), received: \(callbackState != nil ? "[set]" : "[nil]")")
 pendingState = nil
 authState = .loggedOut
 return
 }
 pendingState = nil

 do {
 logger.info("Setting session with tokens from callback")
 try await supabase.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
 let session = try await supabase.auth.session
 authState = .loggedIn(user: Self.buildUser(from: session.user))
 logger.info("Session set successfully for user: \(session.user.id.uuidString)")
 } catch {
 logger.error("Failed to set session from callback: \(error.localizedDescription)")
 await clearSession()
 }
 }

 // MARK: - Logout

 func logout() async {
 logger.info("Logging out (local only - preserving server session)")
 do {
 try await supabase.auth.signOut(scope: .local)
 } catch {
 logger.warning("Local sign-out error: \(error.localizedDescription)")
 }
 authState = .loggedOut
 }

 // MARK: - Token Invalidation

 /// Called when a 401 is received, indicating the token is no longer valid.
 func handleTokenInvalidation() async {
 logger.warning("Token invalidated (401 received), clearing session")
 await clearSession()
 }

 // MARK: - Private

 private static func buildUser(from user: Auth.User) -> AuthUser {
 let metadata = user.userMetadata
 var displayName: String?
 if let name = metadata["full_name"]?.stringValue, !name.isEmpty {
 displayName = name
 } else if let name = metadata["name"]?.stringValue, !name.isEmpty {
 displayName = name
 }
 var avatarURL: URL?
 if let urlStr = metadata["avatar_url"]?.stringValue, !urlStr.isEmpty {
 avatarURL = URL(string: urlStr)
 } else if let urlStr = metadata["picture"]?.stringValue, !urlStr.isEmpty {
 avatarURL = URL(string: urlStr)
 }
 return AuthUser(
 id: user.id.uuidString,
 email: user.email ?? "",
 displayName: displayName ?? "",
 avatarURL: avatarURL
 )
 }

 /// Generates a cryptographically random state string for CSRF protection.
 private func generateState() -> String {
 var bytes = [UInt8](repeating: 0, count: 32)
 _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
 return Data(bytes).base64EncodedString()
 .replacingOccurrences(of: "+", with: "-")
 .replacingOccurrences(of: "/", with: "_")
 .replacingOccurrences(of: "=", with: "")
 }

 /// Parses token parameters from both the URL fragment and query string.
 /// Implicit OAuth returns tokens in the fragment; some flows may use query params.
 private func parseCallbackParameters(from components: URLComponents) -> [String: String] {
 var params: [String: String] = [:]

 // Parse query items first (lower priority)
 if let queryItems = components.queryItems {
 for item in queryItems {
 if let value = item.value {
 params[item.name] = value
 }
 }
 }

 // Parse fragment items (higher priority - overwrites query if both exist)
 if let fragment = components.fragment {
 let fragmentItems = URLComponents(string: "?\(fragment)")?.queryItems ?? []
 for item in fragmentItems {
 if let value = item.value {
 params[item.name] = value
 }
 }
 }

 return params
 }

 private func clearSession() async {
 logger.info("Clearing local session")
 do {
 try await supabase.auth.signOut(scope: .local)
 } catch {
 logger.warning("Local sign-out error (best-effort): \(error.localizedDescription)")
 }
 authState = .loggedOut
 }
}
