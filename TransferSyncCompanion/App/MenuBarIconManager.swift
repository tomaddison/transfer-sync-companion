import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "MenuBarIconManager")

/// Observes upload activity and updates the menu bar icon with a shimmer progress bar.
@MainActor
final class MenuBarIconManager {
 private let uploadManager: UploadManager
 private let panelManager: MenuBarPanelManager
 private var timer: Timer?
 private var shimmerPhase: CGFloat = 0.0

 /// Width of the shimmer highlight relative to the bar.
 private static let shimmerWidth: CGFloat = 0.35
 /// How far the shimmer moves per tick.
 private static let shimmerStep: CGFloat = 0.04

 init(uploadManager: UploadManager, panelManager: MenuBarPanelManager) {
 self.uploadManager = uploadManager
 self.panelManager = panelManager
 }

 /// Call periodically to sync icon state with upload activity.
 func startObserving() {
 timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
 Task { @MainActor [weak self] in
 self?.update()
 }
 }
 update()
 }

 func stopObserving() {
 timer?.invalidate()
 timer = nil
 resetIcon()
 }

 private func update() {
 let hasActiveUploads = uploadManager.items.contains { $0.status == .uploading || $0.status == .processing || $0.status == .pending }

 if hasActiveUploads {
 drawIconWithShimmer()
 } else if shimmerPhase != 0 {
 shimmerPhase = 0
 resetIcon()
 }
 }

 private func drawIconWithShimmer() {
 shimmerPhase += Self.shimmerStep
 if shimmerPhase > 1.0 + Self.shimmerWidth {
 shimmerPhase = -Self.shimmerWidth
 }

 guard let button = panelManager.statusButton else { return }

 let size = NSSize(width: 18, height: 22)
 let image = NSImage(size: size, flipped: false) { rect in
 // Draw the base icon in the upper portion.
 // The asset is a template image - draw within a dark appearance context
 // so AppKit tints it white (matching the menu bar chrome).
 let iconRect = NSRect(x: 0, y: 4, width: 18, height: 18)
 if let baseIcon = NSImage(named: "MenuBarIcon") {
 NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
 baseIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
 }
 }

 // Draw shimmer progress bar at the bottom
 let barHeight: CGFloat = 2.0
 let barY: CGFloat = 0.0
 let barRect = NSRect(x: 1, y: barY, width: rect.width - 2, height: barHeight)

 // Bar background (very subtle)
 NSColor.white.withAlphaComponent(0.15).setFill()
 let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1)
 barPath.fill()

 // Shimmer highlight
 let shimmerStart = barRect.minX + (barRect.width * self.shimmerPhase)
 let shimmerEnd = shimmerStart + (barRect.width * Self.shimmerWidth)
 let shimmerRect = NSRect(
 x: max(barRect.minX, shimmerStart),
 y: barY,
 width: min(shimmerEnd, barRect.maxX) - max(barRect.minX, shimmerStart),
 height: barHeight
 )

 if shimmerRect.width > 0 {
 NSColor.white.withAlphaComponent(0.8).setFill()
 let shimmerPath = NSBezierPath(roundedRect: shimmerRect, xRadius: 1, yRadius: 1)
 shimmerPath.fill()
 }

 return true
 }

 image.isTemplate = false
 button.image = image
 }

 private func resetIcon() {
 panelManager.statusButton?.image = NSImage(named: "MenuBarIcon")
 }
}
