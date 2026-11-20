// Rebuilds the app icon from AppIcon-master.png:
// - AppIcon.icon/Assets/artwork.png, full-bleed art for the Icon Composer icon (macOS 26+);
// - AppIcon.iconset on Apple's 824-point grid for the legacy .icns (macOS 13–15).
// Usage: swiftc make-icon.swift -o make-icon && ./make-icon <Assets directory>
import AppKit

let assets = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
guard let master = NSImage(contentsOf: assets.appendingPathComponent("AppIcon-master.png")),
      let source = master.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Could not read AppIcon-master.png")
}
// Keep only the opaque artwork inside the master's soft rounded edge.
let inset = 140
let artwork = source.cropping(to: CGRect(x: inset, y: inset,
    width: source.width - inset * 2, height: source.height - inset * 2))!

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = context.cgContext
    let scale = CGFloat(pixels) / 1024
    cg.scaleBy(x: scale, y: scale)
    cg.interpolationQuality = .high
    let shape = CGRect(x: 100, y: 100, width: 824, height: 824)
    cg.addPath(CGPath(roundedRect: shape, cornerWidth: 185, cornerHeight: 185, transform: nil))
    cg.clip()
    cg.draw(artwork, in: shape)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = assets.appendingPathComponent("AppIcon.iconset")
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let full = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let fullContext = NSGraphicsContext(bitmapImageRep: full)!
fullContext.cgContext.interpolationQuality = .high
fullContext.cgContext.draw(artwork, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
fullContext.flushGraphics()
let iconAssets = assets.appendingPathComponent("AppIcon.icon/Assets")
try FileManager.default.createDirectory(at: iconAssets, withIntermediateDirectories: true)
try full.representation(using: .png, properties: [:])!.write(to: iconAssets.appendingPathComponent("artwork.png"))
