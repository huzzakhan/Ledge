// Renders Ledge's 1024x1024 app icon to a PNG.
// Usage: swift Scripts/make-icon.swift output.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = 1024

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("Could not create bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background squircle
let bgRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.26, alpha: 1),
           ending: NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1))?.draw(in: bg, angle: -90)

// The bar
NSColor(white: 1, alpha: 0.10).setFill()
NSBezierPath(roundedRect: NSRect(x: 190, y: 300, width: 644, height: 170), xRadius: 60, yRadius: 60).fill()

// Widget tiles
let colors: [NSColor] = [.systemBlue, .systemOrange, .systemPink, .systemGreen]
for (i, c) in colors.enumerated() {
    c.setFill()
    NSBezierPath(roundedRect: NSRect(x: 220 + Double(i) * 150, y: 330, width: 124, height: 110),
                 xRadius: 34, yRadius: 34).fill()
}

// Expanded card above the bar
NSColor(white: 1, alpha: 0.16).setFill()
NSBezierPath(roundedRect: NSRect(x: 250, y: 520, width: 524, height: 270), xRadius: 50, yRadius: 50).fill()
NSColor(white: 1, alpha: 0.90).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 690, width: 260, height: 36), xRadius: 18, yRadius: 18).fill()
NSColor(white: 1, alpha: 0.45).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 625, width: 400, height: 26), xRadius: 13, yRadius: 13).fill()
NSColor(white: 1, alpha: 0.28).setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 575, width: 300, height: 26), xRadius: 13, yRadius: 13).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
try png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
