import Foundation
import Supabase
import Realtime
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "RealtimeManager")

@Observable
@MainActor
final class RealtimeManager {
    private let supabase: SupabaseClient
    private var channels: [String: RealtimeChannelV2] = [:]
    private var listenerTasks: [String: Task<Void, Never>] = [:]
    private var callbacks: [String: @MainActor @Sendable (String, String) -> Void] = [:]

    init(supabase: SupabaseClient = SupabaseClientFactory.shared) {
        self.supabase = supabase
    }

    func subscribeToBatch(
        batchId: String,
        onStatusChange: @escaping @MainActor @Sendable (String, String) -> Void
    ) async {
        callbacks[batchId] = onStatusChange

        let channelName = "upload-batch-\(batchId)"
        let channel = supabase.realtimeV2.channel(channelName)

        let changes = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "media",
            filter: .eq("batch_id", value: batchId)
        )

        try? await channel.subscribeWithError()
        logger.info("Subscribed to Realtime for batch \(batchId)")

        let task = Task { [weak self] in
            for await change in changes {
                guard self != nil else { break }
                if let mediaId = change.record["id"]?.stringValue,
                   let status = change.record["upload_status"]?.stringValue {
                    onStatusChange(mediaId, status)
                }
            }
        }

        channels[batchId] = channel
        listenerTasks[batchId] = task
    }

    func unsubscribeFromBatch(batchId: String) async {
        listenerTasks[batchId]?.cancel()
        listenerTasks.removeValue(forKey: batchId)
        callbacks.removeValue(forKey: batchId)

        if let channel = channels.removeValue(forKey: batchId) {
            await channel.unsubscribe()
            logger.info("Unsubscribed from Realtime for batch \(batchId)")
        }
    }

    func unsubscribeAll() async {
        for (_, task) in listenerTasks { task.cancel() }
        listenerTasks.removeAll()
        callbacks.removeAll()

        for (_, channel) in channels {
            await channel.unsubscribe()
        }
        channels.removeAll()
        logger.info("Unsubscribed from all Realtime channels")
    }

    /// Re-subscribe all channels (call after system wake).
    func reconnectAll() async {
        let activeCallbacks = callbacks
        guard !activeCallbacks.isEmpty else { return }

        logger.info("Reconnecting \(activeCallbacks.count) Realtime channel(s)")

        // Tear down existing channels
        for (_, task) in listenerTasks { task.cancel() }
        listenerTasks.removeAll()
        for (_, channel) in channels {
            await channel.unsubscribe()
        }
        channels.removeAll()

        // Re-subscribe with stored callbacks
        for (batchId, callback) in activeCallbacks {
            await subscribeToBatch(batchId: batchId, onStatusChange: callback)
        }
    }
}
