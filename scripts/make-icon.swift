// Gera Resources/AppIcon.icns: dois círculos sobrepostos (uma cor por conta).
import AppKit

let out = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
                          xRadius: s * 0.18, yRadius: s * 0.18)
    NSColor(srgbRed: 0.11, green: 0.106, blue: 0.098, alpha: 1).setFill()
    bg.fill()
    let r = s * 0.2
    let cy = s / 2
    NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.40 - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    NSColor(srgbRed: 0.416, green: 0.608, blue: 0.8, alpha: 0.85).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.60 - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
