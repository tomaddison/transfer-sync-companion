import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    let statusStore = SyncStatusStore()

    override init() {
        super.init()

        NSLog("FinderSync() launched from %@", Bundle.main.bundlePath as NSString)

        // Load watched paths and set them as monitored directories
        reloadWatchedPaths()

        // Register badge images using SF Symbols
        registerBadgeImages()

        // Restore badges from the persisted status store (survives app restarts)
        rebadgeAllTrackedFiles()

        // Listen for Darwin notifications from the main app
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            darwinNotificationCallback,
            SyncConstants.statusChangedNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - Badge Registration

    private func registerBadgeImages() {
        registerBadge("checkmark.icloud.fill", color: .systemGreen, label: "Uploaded", id: SyncBadge.complete.rawValue)
        registerBadge("arrow.trianglehead.2.clockwise.rotate.90.icloud.fill", color: .systemBlue, label: "Uploading", id: SyncBadge.uploading.rawValue)
        registerBadge("xmark.icloud.fill", color: .systemRed, label: "Failed", id: SyncBadge.failed.rawValue)
    }

    private func registerBadge(_ symbolName: String, color: NSColor, label: String, id: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?
            .withSymbolConfiguration(config) else { return }

        // Render into a bitmap at explicit 2x pixel density for Retina
        let pointSize = 32
        let pixelSize = pointSize * 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize, pixelsHigh: pixelSize,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        // Draw symbol centered in the bitmap
        let symbolSize = symbol.size
        let scale = min(CGFloat(pointSize) / symbolSize.width, CGFloat(pointSize) / symbolSize.height)
        let drawSize = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        let drawRect = NSRect(
            x: (CGFloat(pointSize) - drawSize.width) / 2,
            y: (CGFloat(pointSize) - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        symbol.draw(in: drawRect)

        // Tint
        color.set()
        drawRect.fill(using: .sourceAtop)

        NSGraphicsContext.restoreGraphicsState()

        let badge = NSImage(size: NSSize(width: pointSize, height: pointSize))
        badge.addRepresentation(rep)
        badge.isTemplate = false
        FIFinderSyncController.default().setBadgeImage(badge, label: label, forBadgeIdentifier: id)
    }

    // MARK: - Directory Observation

    override func beginObservingDirectory(at url: URL) {
        NSLog("beginObservingDirectoryAtURL: %@", url.path as NSString)
    }

    override func endObservingDirectory(at url: URL) {
        NSLog("endObservingDirectoryAtURL: %@", url.path as NSString)
    }

    // MARK: - Badge Assignment

    override func requestBadgeIdentifier(for url: URL) {
        guard let inode = inodeForFile(at: url.path) else { return }

        let statuses = statusStore.read()

        for (_, fileStatuses) in statuses {
            if let match = fileStatuses.first(where: { $0.inode == inode }) {
                FIFinderSyncController.default().setBadgeIdentifier(
                    match.status.rawValue, for: url
                )
                return
            }
        }
    }

    // MARK: - Darwin Notification

    func handleDarwinNotification() {
        reloadWatchedPaths()
        rebadgeAllTrackedFiles()
    }

    /// Re-apply badges for all files in the shared status store.
    /// This forces Finder to update badges without the user collapsing/expanding the folder.
    private func rebadgeAllTrackedFiles() {
        let statuses = statusStore.read()
        for (_, fileStatuses) in statuses {
            for fileStatus in fileStatuses {
                let url = URL(fileURLWithPath: fileStatus.filePath)
                FIFinderSyncController.default().setBadgeIdentifier(
                    fileStatus.status.rawValue, for: url
                )
            }
        }
    }

    private func reloadWatchedPaths() {
        let paths = statusStore.readWatchedPaths()
        if paths.isEmpty {
            FIFinderSyncController.default().directoryURLs = []
            NSLog("FinderSync: no watched paths")
        } else {
            let urls = Set(paths.map { URL(fileURLWithPath: $0) })
            FIFinderSyncController.default().directoryURLs = urls
            NSLog("FinderSync: watching %d path(s)", paths.count)
        }
    }

    // MARK: - Helpers

    private func inodeForFile(at path: String) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let inode = attrs[.systemFileNumber] as? UInt64 else {
            return nil
        }
        return inode
    }
}

// MARK: - Darwin Notification C Callback

private func darwinNotificationCallback(
    center: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    name: CFNotificationName?,
    object: UnsafeRawPointer?,
    userInfo: CFDictionary?
) {
    guard let observer else { return }
    let instance = Unmanaged<FinderSync>.fromOpaque(observer).takeUnretainedValue()
    instance.handleDarwinNotification()
}
