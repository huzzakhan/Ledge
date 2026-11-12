import AppKit

// Ledge runs as a menu-bar "accessory" app: no icon in the macOS Dock,
// just the floating Ledge bar plus a small menu bar item.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
