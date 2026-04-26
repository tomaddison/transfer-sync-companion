import Foundation

enum AppConstants {
    static let urlScheme = "transfersync"

    static let apiBaseURL: URL = loadURL("APIBaseURL")
    static let webBaseURL: String = loadString("WebBaseURL")

    /// Builds the login URL with an embedded `state` parameter for CSRF protection.
    static func loginURL(state: String) -> URL {
        let callbackUrl = "\(urlScheme)://auth/callback?state=\(state)"
        var components = URLComponents(string: "\(webBaseURL)/auth/login")!
        components.queryItems = [URLQueryItem(name: "callbackUrl", value: callbackUrl)]
        return components.url!
    }

    enum Supabase {
        static let url: URL = loadURL("SupabaseURL")
        static let anonKey: String = loadString("SupabaseAnonKey")
    }

    private static func loadString(_ key: String) -> String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty,
            !value.contains("REPLACE_ME")
        else {
            fatalError("""
            Missing or placeholder value for '\(key)' in Info.plist.
            Did you forget to copy Configs/<Config>.example.xcconfig → Configs/<Config>.xcconfig?
            """)
        }
        return value
    }

    private static func loadURL(_ key: String) -> URL {
        let raw = loadString(key)
        guard let url = URL(string: raw) else {
            fatalError("Invalid URL for '\(key)': \(raw)")
        }
        return url
    }
}
