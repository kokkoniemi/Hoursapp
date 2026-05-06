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
    let center = NSPoint(x: canvas.midX, y: canvas.midY)

    // ---- Blue rounded rect background ----
    let outerInset = 70.0 * scale
    let outerRect = canvas.insetBy(dx: outerInset, dy: outerInset)
    let outerCorner = 220.0 * scale
    let outerPath = NSBezierPath(roundedRect: outerRect,
                                 xRadius: outerCorner, yRadius: outerCorner)
    NSColor(deviceRed: 0.0, green: 0.48, blue: 1.0, alpha: 1.0).setFill()
    outerPath.fill()

    // ---- White clock face ----
    let dialRadius = 380.0 * scale
    let dialPath = NSBezierPath(ovalIn: NSRect(
        x: center.x - dialRadius, y: center.y - dialRadius,
        width: dialRadius * 2, height: dialRadius * 2
    ))
    NSColor.white.setFill()
    dialPath.fill()

    // ---- Tick marks (12 hour, 48 minute) ----
    let tickOuter = dialRadius
    let hourLen = dialRadius * 0.10
    let minuteLen = dialRadius * 0.035

    let hourTicks = NSBezierPath()
    let minuteTicks = NSBezierPath()
    for i in 0..<60 {
        let angle = Double(i) / 60.0 * .pi * 2 - .pi / 2
        let isHour = (i % 5 == 0)
        let len = isHour ? hourLen : minuteLen
        let x0 = center.x + Darwin.cos(angle) * tickOuter
        let y0 = center.y + Darwin.sin(angle) * tickOuter
        let x1 = center.x + Darwin.cos(angle) * (tickOuter - len)
        let y1 = center.y + Darwin.sin(angle) * (tickOuter - len)
        let path = isHour ? hourTicks : minuteTicks
        path.move(to: NSPoint(x: x0, y: y0))
        path.line(to: NSPoint(x: x1, y: y1))
    }
    NSColor(white: 0.0, alpha: 0.55).setStroke()
    minuteTicks.lineWidth = 3 * scale
    minuteTicks.stroke()

    NSColor.black.setStroke()
    hourTicks.lineWidth = 9 * scale
    hourTicks.lineCapStyle = .round
    hourTicks.stroke()

    // ---- h / m italic labels at the 9 and 3 positions ----
    let labelSize = 110.0 * scale
    let labelFont =
        NSFontManager.shared.font(withFamily: "Times New Roman", traits: .italicFontMask, weight: 5, size: labelSize)
        ?? NSFontManager.shared.font(withFamily: "Georgia", traits: .italicFontMask, weight: 5, size: labelSize)
        ?? NSFont.systemFont(ofSize: labelSize)
    let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: labelFont,
        .foregroundColor: NSColor.black
    ]

    func drawCentered(_ s: String, at point: NSPoint) {
        let str = NSAttributedString(string: s, attributes: labelAttrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: point.x - sz.width / 2, y: point.y - sz.height / 2))
    }

    drawCentered("h", at: NSPoint(x: center.x - dialRadius * 0.65, y: center.y))
    drawCentered("m", at: NSPoint(x: center.x + dialRadius * 0.65, y: center.y))

    // ---- Hands: flat, rounded ends. Hour & minute black, second hand orange. ----
    func drawHand(clockHours: Double, length: CGFloat, width: CGFloat,
                  counterLength: CGFloat, color: NSColor) {
        let radians = .pi / 2 - clockHours * (.pi * 2 / 12)
        let dx = Darwin.cos(radians)
        let dy = Darwin.sin(radians)
        let tip = NSPoint(x: center.x + dx * length, y: center.y + dy * length)
        let tail = NSPoint(x: center.x - dx * counterLength, y: center.y - dy * counterLength)

        let path = NSBezierPath()
        path.move(to: tail)
        path.line(to: tip)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    let displayHour = 10.0
    let displayMinute = 9.0
    let hourClock = displayHour + displayMinute / 60.0
    let minuteClock = displayMinute / 5.0

    drawHand(clockHours: hourClock,
             length: dialRadius * 0.50,
             width: 28 * scale,
             counterLength: dialRadius * 0.10,
             color: .black)

    drawHand(clockHours: minuteClock,
             length: dialRadius * 0.74,
             width: 22 * scale,
             counterLength: dialRadius * 0.13,
             color: .black)

    // ---- Center dot ----
    let dotRadius = 16 * scale
    let dotPath = NSBezierPath(ovalIn: NSRect(x: center.x - dotRadius, y: center.y - dotRadius,
                                              width: dotRadius * 2, height: dotRadius * 2))
    NSColor.black.setFill()
    dotPath.fill()

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
