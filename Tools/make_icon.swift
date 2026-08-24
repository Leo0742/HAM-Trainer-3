import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("bitmap") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill(); bounds.fill()

let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 54, dy: 54), xRadius: 220, yRadius: 220)
NSGradient(colors: [NSColor(calibratedRed: 0.04, green: 0.13, blue: 0.30, alpha: 1), NSColor(calibratedRed: 0.03, green: 0.35, blue: 0.55, alpha: 1)])!.draw(in: tile, angle: -55)

NSColor(calibratedRed: 0.24, green: 0.88, blue: 0.95, alpha: 1).setStroke()
for (radius, width) in [(300.0, 34.0), (220.0, 38.0), (140.0, 42.0)] {
    let left = NSBezierPath(); left.appendArc(withCenter: NSPoint(x: 512, y: 470), radius: radius, startAngle: 125, endAngle: 235); left.lineWidth = width; left.lineCapStyle = .round; left.stroke()
    let right = NSBezierPath(); right.appendArc(withCenter: NSPoint(x: 512, y: 470), radius: radius, startAngle: -55, endAngle: 55); right.lineWidth = width; right.lineCapStyle = .round; right.stroke()
}

NSColor.white.setStroke()
let mast = NSBezierPath(); mast.move(to: NSPoint(x: 512, y: 255)); mast.line(to: NSPoint(x: 512, y: 540)); mast.lineWidth = 54; mast.lineCapStyle = .round; mast.stroke()
NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 456, y: 520, width: 112, height: 112)).fill()

let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 170, weight: .black), .foregroundColor: NSColor.white, .paragraphStyle: paragraph]
NSAttributedString(string: "2", attributes: attributes).draw(in: NSRect(x: 330, y: 650, width: 364, height: 210))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
