#!/usr/bin/env swift
import AppKit

let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

let iconsetDir = "/tmp/DimmerFlow.iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let inset = s * 0.08
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = s * 0.22

    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.18, green: 0.18, blue: 0.24, alpha: 1),
        NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)
    ])!
    gradient.draw(in: bgPath, angle: -90)

    let center = NSPoint(x: s / 2, y: s / 2)
    let radius = s * 0.28

    let rightHalf = NSBezierPath()
    rightHalf.appendArc(withCenter: center, radius: radius, startAngle: -90, endAngle: 90)
    rightHalf.close()
    NSColor(white: 0.35, alpha: 1).setFill()
    rightHalf.fill()

    let leftHalf = NSBezierPath()
    leftHalf.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 270)
    leftHalf.close()
    NSColor(white: 0.95, alpha: 1).setFill()
    leftHalf.fill()

    let circlePath = NSBezierPath(ovalIn: NSRect(
        x: center.x - radius, y: center.y - radius,
        width: radius * 2, height: radius * 2
    ))
    NSColor(white: 0.6, alpha: 0.25).setStroke()
    circlePath.lineWidth = max(1, s * 0.012)
    circlePath.stroke()

    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to create PNG for size \(size)")
    }

    let path = (iconsetDir as NSString).appendingPathComponent(name)
    try! pngData.write(to: URL(fileURLWithPath: path))
}

print(iconsetDir)
