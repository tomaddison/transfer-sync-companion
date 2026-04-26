import Foundation
import Supabase

struct APIClient {
    let baseURL: URL
    let supabase: SupabaseClient
    private let session: URLSession
    private let decoder: JSONDecoder
    private let onUnauthorized: (@Sendable () async -> Void)?

    init(
        baseURL: URL = AppConstants.apiBaseURL,
        supabase: SupabaseClient = SupabaseClientFactory.shared,
        session: URLSession = .shared,
        onUnauthorized: (@Sendable () async -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.supabase = supabase
        self.session = session
        self.onUnauthorized = onUnauthorized
        self.decoder = JSONDecoder()
    }

    func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        encoder customEncoder: JSONEncoder? = nil
    ) async throws -> T {
        let (data, _) = try await performRequest(
            path: path, method: method, body: body,
            queryItems: queryItems, encoder: customEncoder
        )

        do {
            let envelope = try decoder.decode(APIDataResponse<T>.self, from: data)
            return envelope.data
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// For endpoints that return raw binary data (e.g. file downloads).
    func requestRawData(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let accessToken = try await currentAccessToken()

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.networkError(URLError(.badURL))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.networkError(URLError(.badURL))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
            await onUnauthorized?()
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return (data, httpResponse)
    }

    /// For endpoints that return `{ success: true }` without a `data` envelope.
    func requestVoid(
        path: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        encoder customEncoder: JSONEncoder? = nil
    ) async throws {
        _ = try await performRequest(
            path: path, method: method, body: body,
            queryItems: queryItems, encoder: customEncoder
        )
    }

    private func performRequest(
        path: String,
        method: String,
        body: (any Encodable)?,
        queryItems: [URLQueryItem]?,
        encoder customEncoder: JSONEncoder?
    ) async throws -> (Data, HTTPURLResponse) {
        let accessToken = try await currentAccessToken()

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.networkError(URLError(.badURL))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.networkError(URLError(.badURL))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            let encoder = customEncoder ?? JSONEncoder()
            urlRequest.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 401 {
            await onUnauthorized?()
            throw APIError.unauthorized
        }

        if httpResponse.statusCode >= 400 {
            let errorResponse = try? decoder.decode(APIErrorResponse.self, from: data)
            throw APIError.serverError(
                statusCode: httpResponse.statusCode,
                message: errorResponse?.error ?? "Unknown error"
            )
        }

        return (data, httpResponse)
    }

    private func currentAccessToken() async throws -> String {
        guard let session = try? await supabase.auth.session else {
            throw APIError.noSession
        }
        return session.accessToken
    }
}

private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        _encode = { encoder in try wrapped.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
