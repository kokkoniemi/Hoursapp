#!/usr/bin/env swift
import AppKit
import Darwin

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]
let assetsDir = "Hoursapp/Assets.xcassets/AppIcon.appiconset"

func renderIcon(pixels: Int) -> Data {
    let size = NSSize(width: pixels, height: pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = NSRect(origin: .zero, size: size)
    let scale = CGFloat(pixels) / 1024.0

    let shapeInset = (1024.0 - 824.0) / 2.0 * scale
    let shapeRect = canvas.insetBy(dx: shapeInset, dy: shapeInset)
    let cornerRadius = 185.0 * scale
    let shape = NSBezierPath(roundedRect: shapeRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSColor.white.setFill()
    shape.fill()

    let center = NSPoint(x: canvas.midX, y: canvas.midY)
    let radius = CGFloat(pixels) * 0.32
    let lineWidth = max(1.0, CGFloat(pixels) * 0.025)

    NSColor.black.setStroke()
    let circle = NSBezierPath(ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
    circle.lineWidth = lineWidth
    circle.stroke()

    let hourLength = radius * 0.55
    let minuteLength = radius * 0.82
    let hourLineWidth = lineWidth * 1.6
    let minuteLineWidth = lineWidth

    func drawHand(clockAngle: Double, length: CGFloat, lineWidth: CGFloat) {
        let radians = .pi / 2 - clockAngle
        let end = NSPoint(
            x: center.x + Darwin.cos(radians) * length,
            y: center.y + Darwin.sin(radians) * length
        )
        let path = NSBezierPath()
        path.move(to: center)
        path.line(to: end)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.stroke()
    }

    let hour = 10.0
    let minute = 9.0
    let second = 30.0
    let hourAngle = (hour + minute / 60.0) * (.pi * 2 / 12)
    let minuteAngle = (minute + second / 60.0) * (.pi * 2 / 60)

    drawHand(clockAngle: hourAngle, length: hourLength, lineWidth: hourLineWidth)
    drawHand(clockAngle: minuteAngle, length: minuteLength, lineWidth: minuteLineWidth)

    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

let cwd = FileManager.default.currentDirectoryPath
let outDir = "\(cwd)/\(assetsDir)"

for px in sizes {
    let data = renderIcon(pixels: px)
    let url = URL(fileURLWithPath: "\(outDir)/icon_\(px).png")
    try data.write(to: url)
    print("wrote \(url.lastPathComponent) (\(data.count) bytes)")
}

let json = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try json.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("updated Contents.json")
