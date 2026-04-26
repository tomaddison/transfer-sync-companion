import Foundation
import Network
import Observation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "ConnectivityManager")

@Observable
@MainActor
final class ConnectivityManager {
    private(set) var isConnected = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "transfersync.connectivity-monitor")

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isConnected != connected {
                    self.isConnected = connected
                    logger.info("Network connectivity changed: \(connected ? "online" : "offline")")
                }
            }
        }
        monitor.start(queue: queue)
        logger.info("Connectivity monitoring started")
    }

    func stopMonitoring() {
        monitor.cancel()
        logger.info("Connectivity monitoring stopped")
    }
}
