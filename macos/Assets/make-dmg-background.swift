// Draws the DMG window background at 1x and 2x.
// Usage: swift make-dmg-background.swift <output-directory>
import AppKit

let size = NSSize(width: 640, height: 400)
let navy = NSColor(red: 0.09, green: 0.16, blue: 0.42, alpha: 1)
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func render(scale: CGFloat, to url: URL) throws {
    let pixels = NSSize(width: size.width * scale, height: size.height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width),
        pixelsHigh: Int(pixels.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(starting: NSColor(red: 0.97, green: 0.97, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.88, green: 0.91, blue: 0.98, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // A few faint stars echo the app icon without competing with the icons.
    navy.withAlphaComponent(0.12).setFill()
    for (x, y, r) in [(60.0, 340.0, 3.0), (590, 360, 2.5), (520, 70, 2), (110, 60, 2), (330, 370, 2)] {
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
    }

    // Arrow from the app (x 170) to Applications (x 470); Finder icon centres sit at y 200 from the top.
    let y = size.height - 190
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: y))
    shaft.line(to: NSPoint(x: 366, y: y))
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    shaft.setLineDash([2, 11], count: 2, phase: 0)
    navy.withAlphaComponent(0.55).setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 364, y: y + 13))
    head.line(to: NSPoint(x: 380, y: y))
    head.line(to: NSPoint(x: 364, y: y - 13))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    let caption = "Drag Mawaqit to Applications to install" as NSString
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    caption.draw(in: NSRect(x: 0, y: 48, width: size.width, height: 24), withAttributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: navy.withAlphaComponent(0.75),
        .paragraphStyle: paragraph,
    ])

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try render(scale: 1, to: output.appendingPathComponent("dmg-background.png"))
try render(scale: 2, to: output.appendingPathComponent("dmg-background@2x.png"))
