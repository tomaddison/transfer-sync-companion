import UserNotifications
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "NotificationManager")

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    private var pendingSuccessCount = 0
    private var pendingFailCount = 0
    private var lastSuccessFileName: String?
    private var lastSuccessVersionOf: String?
    private var lastFailFileName: String?
    private var debounceTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .milliseconds(2500)

    func requestPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.warning("Notification permission error: \(error.localizedDescription)")
            } else {
                logger.info("Notification permission \(granted ? "granted" : "denied")")
            }
        }
    }

    func notifyUploadComplete(fileName: String, versionOf: String?) {
        pendingSuccessCount += 1
        lastSuccessFileName = fileName
        lastSuccessVersionOf = versionOf
        scheduleFlush()
    }

    func notifyUploadFailed(fileName: String) {
        pendingFailCount += 1
        lastFailFileName = fileName
        scheduleFlush()
    }

    // MARK: - Batching

    private func scheduleFlush() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        if pendingSuccessCount == 1, let fileName = lastSuccessFileName {
            let content = UNMutableNotificationContent()
            content.title = "Upload Complete"
            if let version = lastSuccessVersionOf {
                content.body = "\(fileName) uploaded as \(version)"
            } else {
                content.body = "\(fileName) uploaded successfully"
            }
            content.sound = .default
            send(content: content)
        } else if pendingSuccessCount > 1 {
            let content = UNMutableNotificationContent()
            content.title = "Uploads Complete"
            content.body = "\(pendingSuccessCount) files uploaded successfully"
            content.sound = .default
            send(content: content)
        }

        if pendingFailCount == 1, let fileName = lastFailFileName {
            let content = UNMutableNotificationContent()
            content.title = "Upload Failed"
            content.body = "\(fileName) could not be uploaded"
            content.sound = .default
            send(content: content)
        } else if pendingFailCount > 1 {
            let content = UNMutableNotificationContent()
            content.title = "Uploads Failed"
            content.body = "\(pendingFailCount) files could not be uploaded"
            content.sound = .default
            send(content: content)
        }

        pendingSuccessCount = 0
        pendingFailCount = 0
        lastSuccessFileName = nil
        lastSuccessVersionOf = nil
        lastFailFileName = nil
    }

    private func send(content: UNMutableNotificationContent) {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true else { return }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("Failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }

    // Show notifications even when the app is in the foreground.
    // Menu bar apps are always technically foreground, so without this
    // delegate method notifications would be silently suppressed.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
