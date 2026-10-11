import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let inset = CGFloat(pixels) * 0.07
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: CGFloat(pixels) * 0.20, yRadius: CGFloat(pixels) * 0.20)
        NSGradient(starting: NSColor(calibratedRed: 0.48, green: 0.49, blue: 0.97, alpha: 1), ending: NSColor(calibratedRed: 0.25, green: 0.28, blue: 0.78, alpha: 1))!.draw(in: shape, angle: -60)
        let center = NSPoint(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)
        let radius = CGFloat(pixels) * 0.245
        let ring = NSBezierPath()
        ring.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        ring.lineWidth = CGFloat(pixels) * 0.075
        NSColor.white.withAlphaComponent(0.24).setStroke()
        ring.stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 355)
        arc.lineCapStyle = .round
        arc.lineWidth = CGFloat(pixels) * 0.075
        NSColor.white.setStroke()
        arc.stroke()
        let dot = NSBezierPath(ovalIn: NSRect(x: center.x - CGFloat(pixels) * 0.045, y: center.y - CGFloat(pixels) * 0.045, width: CGFloat(pixels) * 0.09, height: CGFloat(pixels) * 0.09))
        NSColor.white.setFill()
        dot.fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 1 ? "" : "@2x"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

// ICNS PNG elements; create the container directly so building needs no GUI service.
func word(_ value: Int) -> Data {
    var big = UInt32(value).bigEndian
    return withUnsafeBytes(of: &big) { Data($0) }
}
let entries = [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
               ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
               ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
               ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"),
               ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"),
               ("ic14", "icon_256x256@2x.png")]
var payload = Data()
for (type, file) in entries {
    let png = try Data(contentsOf: directory.appendingPathComponent(file))
    payload.append(Data(type.utf8))
    payload.append(word(png.count + 8))
    payload.append(png)
}
var icns = Data("icns".utf8)
icns.append(word(payload.count + 8))
icns.append(payload)
try icns.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
