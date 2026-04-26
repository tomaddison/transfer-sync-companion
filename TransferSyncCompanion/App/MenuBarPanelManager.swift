import AppKit
import SwiftUI
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TransferSyncCompanion", category: "MenuBarPanelManager")

/// Owns the NSStatusItem and the MenuBarPanel. Handles show/hide/toggle
/// and dismisses the panel when the user clicks outside.
@MainActor
final class MenuBarPanelManager: NSObject {
 private var statusItem: NSStatusItem?
 private var panel: MenuBarPanel?
 private var clickOutsideMonitor: Any?
 /// When true, outside-click monitoring is paused (e.g. while NSOpenPanel is open).
 private(set) var isClickMonitoringSuspended = false

 private let panelSize = NSSize(width: 320, height: 420)

 func setUp(rootView: some View) {
 logger.info("Setting up menu bar panel")

 let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
 if let button = item.button {
 button.image = NSImage(named: "MenuBarIcon")
 button.action = #selector(statusItemClicked)
 button.target = self
 button.sendAction(on: [.leftMouseUp, .rightMouseUp])
 }
 statusItem = item

 let p = MenuBarPanel(contentRect: NSRect(origin: .zero, size: panelSize))
 let hosting = NSHostingView(rootView: rootView.ignoresSafeArea())
 hosting.frame = NSRect(origin: .zero, size: panelSize)
 p.contentView = hosting
 panel = p

 logger.info("Menu bar panel setup complete")
 }

 var isVisible: Bool { panel?.isVisible ?? false }

 /// Exposes the status bar button for icon customisation (e.g. upload indicator).
 var statusButton: NSStatusBarButton? { statusItem?.button }

 func show() {
 guard let panel, let button = statusItem?.button, let buttonWindow = button.window else {
 logger.warning("Cannot show panel - missing panel, button, or button window")
 return
 }

 let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
 let x = buttonFrame.midX - panelSize.width / 2
 let y = buttonFrame.minY - panelSize.height - 4

 let alreadyVisible = panel.isVisible
 panel.setFrameOrigin(NSPoint(x: x, y: y))
 if !alreadyVisible {
 panel.alphaValue = 0
 }
 panel.makeKeyAndOrderFront(nil)
 if !alreadyVisible {
 NSAnimationContext.runAnimationGroup { ctx in
 ctx.duration = 0.15
 ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
 panel.animator().alphaValue = 1
 }
 }
 startMonitoringClicks()
 NotificationCenter.default.post(name: .panelDidShow, object: nil)
 logger.info("Panel shown")
 }

 func hide() {
 guard let panel else { return }
 NSAnimationContext.runAnimationGroup({ ctx in
 ctx.duration = 0.12
 ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
 panel.animator().alphaValue = 0
 }, completionHandler: { [weak self] in
 panel.orderOut(nil)
 panel.alphaValue = 1
 Task { @MainActor [weak self] in
 self?.stopMonitoringClicks()
 }
 })
 }

 func toggle() {
 if isVisible { hide() } else { show() }
 }

 // MARK: - Status Item Action

 @objc private func statusItemClicked() {
 let event = NSApp.currentEvent
 if event?.type == .rightMouseUp {
 showContextMenu()
 } else {
 toggle()
 }
 }

 private func showContextMenu() {
 guard let statusItem else { return }
 if isVisible { hide() }

 let menu = NSMenu()
 let quitItem = NSMenuItem(title: "Quit TransferSync", action: #selector(quitApp), keyEquivalent: "q")
 quitItem.target = self
 menu.addItem(quitItem)

 statusItem.menu = menu
 statusItem.button?.performClick(nil)
 statusItem.menu = nil
 }

 @objc private func quitApp() {
 NSApp.terminate(nil)
 }

 // MARK: - Click Monitoring Suspension

 /// Suspend outside-click monitoring (e.g. while a system panel like NSOpenPanel is open).
 func suspendClickMonitoring() {
 isClickMonitoringSuspended = true
 stopMonitoringClicks()
 }

 /// Resume outside-click monitoring after a system panel closes.
 func resumeClickMonitoring() {
 isClickMonitoringSuspended = false
 if isVisible {
 startMonitoringClicks()
 }
 }

 // MARK: - Menu Bar Icon

 /// Update the status bar icon image by name.
 func setIcon(named name: String) {
 statusItem?.button?.image = NSImage(named: name)
 }

 // MARK: - Outside Click Monitoring

 private func startMonitoringClicks() {
 stopMonitoringClicks()
 clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
 Task { @MainActor in
 self?.hide()
 }
 }
 }

 private func stopMonitoringClicks() {
 if let monitor = clickOutsideMonitor {
 NSEvent.removeMonitor(monitor)
 clickOutsideMonitor = nil
 }
 }
}

// MARK: - Environment Key

private struct PanelManagerKey: EnvironmentKey {
 static let defaultValue: MenuBarPanelManager? = nil
}

extension Notification.Name {
 static let panelDidShow = Notification.Name("panelDidShow")
}

extension EnvironmentValues {
 var panelManager: MenuBarPanelManager? {
 get { self[PanelManagerKey.self] }
 set { self[PanelManagerKey.self] = newValue }
 }
}
