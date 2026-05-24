import AppKit

let outputURL = URL(fileURLWithPath: "Resources/AppIcon-1024.png")
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
let rect = NSRect(origin: .zero, size: size)

let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 220, yRadius: 220)
NSGradient(colors: [
    NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.12, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.35, blue: 0.55, alpha: 1)
])?.draw(in: backgroundPath, angle: -35)

NSColor(calibratedRed: 0.34, green: 0.82, blue: 1.0, alpha: 0.75).setStroke()
backgroundPath.lineWidth = 26
backgroundPath.stroke()

let speaker = NSBezierPath()
speaker.move(to: NSPoint(x: 230, y: 445))
speaker.line(to: NSPoint(x: 330, y: 445))
speaker.line(to: NSPoint(x: 470, y: 335))
speaker.line(to: NSPoint(x: 470, y: 690))
speaker.line(to: NSPoint(x: 330, y: 580))
speaker.line(to: NSPoint(x: 230, y: 580))
speaker.close()
NSColor.white.setFill()
speaker.fill()

for offset in [0, 70, 140] {
    let wave = NSBezierPath()
    wave.appendArc(
        withCenter: NSPoint(x: 495, y: 512),
        radius: CGFloat(95 + offset),
        startAngle: -42,
        endAngle: 42,
        clockwise: false
    )
    wave.lineWidth = 34
    wave.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.92 - CGFloat(offset) / 280).setStroke()
    wave.stroke()
}

let labels = ["1", "2", "3", "4"]
let tileRects = [
    NSRect(x: 310, y: 160, width: 150, height: 92),
    NSRect(x: 500, y: 160, width: 150, height: 92),
    NSRect(x: 310, y: 50, width: 150, height: 92),
    NSRect(x: 500, y: 50, width: 150, height: 92)
]

for (index, tile) in tileRects.enumerated() {
    let path = NSBezierPath(roundedRect: tile, xRadius: 28, yRadius: 28)
    NSColor(calibratedWhite: 0.08, alpha: 0.78).setFill()
    path.fill()
    NSColor(calibratedRed: 0.58, green: 0.9, blue: 1.0, alpha: 0.95).setStroke()
    path.lineWidth = 8
    path.stroke()

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 52, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    let text = labels[index] as NSString
    let textSize = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: tile.midX - textSize.width / 2, y: tile.midY - textSize.height / 2), withAttributes: attrs)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render icon")
}

try png.write(to: outputURL)
