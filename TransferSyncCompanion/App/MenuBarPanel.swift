import AppKit

/// A borderless, non-activating panel used as the menu bar dropdown.
/// Behaves like Dropbox/1Password: floats above everything, dismisses on outside click,
/// doesn't steal focus from other apps.
final class MenuBarPanel: NSPanel {
 init(contentRect: NSRect) {
 super.init(
 contentRect: contentRect,
 styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
 backing: .buffered,
 defer: true
 )

 // Make the titlebar invisible - content extends behind it,
 // and the header view occupies the titlebar area visually.
 titlebarAppearsTransparent = true
 titleVisibility = .hidden
 standardWindowButton(.closeButton)?.isHidden = true
 standardWindowButton(.miniaturizeButton)?.isHidden = true
 standardWindowButton(.zoomButton)?.isHidden = true

 isMovable = false
 isMovableByWindowBackground = false
 level = .popUpMenu
 isFloatingPanel = true
 hidesOnDeactivate = false
 hasShadow = true

 isOpaque = false
 backgroundColor = NSColor(red: 0x10/255.0, green: 0x10/255.0, blue: 0x12/255.0, alpha: 1.0)

 }

 override var canBecomeKey: Bool { true }
}
