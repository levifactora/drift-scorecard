import AppKit

// Draws the app icon: a drift line leaving a shaded allowed band.
let output = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let s = CGFloat(size)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let inset = s * 0.09
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2), xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(starting: NSColor(srgbRed: 0.09, green: 0.11, blue: 0.16, alpha: 1), ending: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.09, alpha: 1))!.draw(in: tile, angle: -90)
    NSColor(srgbRed: 0.22, green: 0.53, blue: 0.9, alpha: 0.22).setFill()
    NSBezierPath(rect: NSRect(x: inset, y: s * 0.36, width: s - inset * 2, height: s * 0.24)).fill()
    let line = NSBezierPath()
    line.lineWidth = s * 0.055
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: s * 0.2, y: s * 0.46))
    line.curve(to: NSPoint(x: s * 0.8, y: s * 0.74), controlPoint1: NSPoint(x: s * 0.5, y: s * 0.46), controlPoint2: NSPoint(x: s * 0.56, y: s * 0.7))
    NSColor(srgbRed: 0.35, green: 0.65, blue: 1, alpha: 1).setStroke()
    line.stroke()
    NSColor(srgbRed: 0.98, green: 0.7, blue: 0.1, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.74, y: s * 0.68, width: s * 0.12, height: s * 0.12)).fill()
    NSGraphicsContext.current = nil
    let name = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/\(name)"))
    if size > 16 && size < 1024 {
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(size / 2)x\(size / 2)@2x.png"))
    }
}
