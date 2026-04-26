import SwiftUI
import CoreText
import Supabase
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "AppDelegate")

@main
struct TransferSyncCompanionApp: App {
 @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

 var body: some Scene {
 // No visible windows - the app lives entirely in the menu bar panel.
 Settings { EmptyView() }
 }
}

/// Minimal delegate - only exists for URL callback handling and app lifecycle.
/// All UI is managed by MenuBarPanelManager.
final class AppDelegate: NSObject, NSApplicationDelegate {
 private let authManager = AuthManager()
 private let panelManager = MenuBarPanelManager()
 private let realtimeManager = RealtimeManager()
 private let connectivityManager = ConnectivityManager()
 private let notificationManager = NotificationManager()
 private lazy var apiClient = APIClient(onUnauthorized: { [weak self] in
 await self?.authManager.handleTokenInvalidation()
 })
 private lazy var configManager = ConfigManager(apiClient: apiClient)
 private lazy var uploadManager = UploadManager(
 apiClient: apiClient,
 configManager: configManager,
 realtimeManager: realtimeManager,
 connectivityManager: connectivityManager,
 notificationManager: notificationManager
 )
 private lazy var iconManager = MenuBarIconManager(
 uploadManager: uploadManager,
 panelManager: panelManager
 )
 private let settingsStore = SettingsStore()
 private lazy var watchedFolderStore = WatchedFolderStore()
 private lazy var uploadHistoryStore = UploadHistoryStore()
 private lazy var watchedFolderManager = WatchedFolderManager(
 uploadManager: uploadManager,
 store: watchedFolderStore,
 historyStore: uploadHistoryStore,
 settingsStore: settingsStore
 )

 func applicationDidFinishLaunching(_ notification: Notification) {
 logger.info("Application did finish launching")
 registerFonts()

 connectivityManager.startMonitoring()
 notificationManager.requestPermission()

 let contentView = ContentView()
 .environment(authManager)
 .environment(uploadManager)
 .environment(configManager)
 .environment(watchedFolderManager)
 .environment(settingsStore)
 .environment(connectivityManager)
 .environment(\.panelManager, panelManager)

 panelManager.setUp(rootView: contentView)
 iconManager.startObserving()

 authManager.startAuthStateListener()

 NSWorkspace.shared.notificationCenter.addObserver(
 forName: NSWorkspace.didWakeNotification,
 object: nil,
 queue: .main
 ) { [weak self] _ in
 guard let self else { return }
 Task { @MainActor in
 await self.handleSystemWake()
 }
 }

 Task {
 await authManager.restoreSession()
 if case .loggedIn = authManager.authState {
 await configManager.loadConfig()
 watchedFolderManager.startAll()
 watchedFolderManager.scanForMissedFiles()
 await uploadManager.fetchUnresolvedCommentCounts()
 }
 }
 }

 /// Registers bundled Geologica font files with CoreText so they're available to SwiftUI.
 private func registerFonts() {
 let fontNames = ["Geologica-ExtraLight", "Geologica-Regular", "Geologica-Medium", "Geologica-SemiBold", "Geologica-Bold"]
 for name in fontNames {
 if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
 var error: Unmanaged<CFError>?
 if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
 logger.warning("Failed to register font \(name): \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
 }
 } else {
 logger.warning("Font file not found in bundle: \(name).ttf")
 }
 }
 }

 private func handleSystemWake() async {
 logger.info("System wake detected")
 guard case .loggedIn = authManager.authState else { return }

 // Refresh token - it may have expired during sleep
 do {
 try await authManager.supabase.auth.refreshSession()
 logger.info("Token refreshed after wake")
 } catch {
 logger.warning("Token refresh after wake failed: \(error.localizedDescription)")
 }

 // Reconnect Realtime channels that may have dropped during sleep
 await realtimeManager.reconnectAll()
 }

 func application(_ application: NSApplication, open urls: [URL]) {
 logger.info("application(_:open:) called with \(urls.count) URL(s)")
 for url in urls {
 logger.info("Handling URL: \(url.absoluteString)")
 panelManager.show()
 Task { @MainActor in
 await authManager.handleCallback(url: url)
 if case .loggedIn = authManager.authState {
 await configManager.loadConfig()
 watchedFolderManager.startAll()
 watchedFolderManager.scanForMissedFiles()
 await uploadManager.fetchUnresolvedCommentCounts()
 }
 }
 }
 }
}
