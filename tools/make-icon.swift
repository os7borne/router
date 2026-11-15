import AppKit
// Renders the Router app icon (matches the design canvas) into an .iconset directory.
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 120
    ctx.scaleBy(x: s, y: s); ctx.translateBy(x: 0, y: 120); ctx.scaleBy(x: 1, y: -1) // SVG-style coords
    let rect = CGRect(x: 4, y: 4, width: 112, height: 112)
    let path = CGPath(roundedRect: rect, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(red: 0.357, green: 0.549, blue: 1, alpha: 1).cgColor, NSColor(red: 0.133, green: 0.827, blue: 0.933, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 4, y: 4), end: CGPoint(x: 116, y: 116), options: [])
    let sh = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [NSColor(white: 1, alpha: 0.22).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sh, start: CGPoint(x: 0, y: 4), end: CGPoint(x: 0, y: 60), options: [])
    ctx.restoreGState()
    ctx.setLineWidth(9); ctx.setLineCap(.round)
    for (r, a) in [(52.0, 0.55), (36.0, 0.8), (20.0, 1.0)] as [(CGFloat, CGFloat)] {
        ctx.setStrokeColor(NSColor(white: 1, alpha: a).cgColor)
        ctx.addArc(center: CGPoint(x: 60, y: 84), radius: r, startAngle: .pi * 1.25, endAngle: .pi * 1.75, clockwise: false)
        ctx.strokePath()
    }
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: 53, y: 79, width: 14, height: 14))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (n, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let suffix = scale == 2 ? "@2x" : ""
    try! render(n * scale).write(to: URL(fileURLWithPath: "\(out)/icon_\(n)x\(n)\(suffix).png"))
}
