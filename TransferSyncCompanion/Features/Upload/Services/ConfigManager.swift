import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "ConfigManager")

@Observable
@MainActor
final class ConfigManager {
    private(set) var multipartThresholdBytes: Int = 100 * 1024 * 1024
    private(set) var isLoaded = false

    private let apiClient: any UploadAPIClient

    init(apiClient: any UploadAPIClient) {
        self.apiClient = apiClient
    }

    func loadConfig() async {
        do {
            let config = try await apiClient.fetchConfig()
            self.multipartThresholdBytes = config.multipartThresholdBytes
            logger.info("Config loaded: multipart threshold = \(config.multipartThresholdBytes) bytes")
        } catch {
            logger.warning("Failed to fetch config, using defaults: \(error.localizedDescription)")
        }
        self.isLoaded = true
    }
}
