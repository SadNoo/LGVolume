import AppKit

let outputURL = URL(fileURLWithPath: "Resources/AppIcon-1024.png")
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

func drawClipped(_ path: NSBezierPath, drawing: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    drawing()
    NSGraphicsContext.restoreGraphicsState()
}

func drawShadow(color: NSColor, blur: CGFloat, offset: NSSize, drawing: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = offset
    shadow.set()
    drawing()
    NSGraphicsContext.restoreGraphicsState()
}

image.lockFocus()

let rect = NSRect(origin: .zero, size: size)
let iconRect = rect.insetBy(dx: 56, dy: 56)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 210, yRadius: 210)

drawShadow(color: NSColor.black.withAlphaComponent(0.18), blur: 44, offset: NSSize(width: 0, height: -18)) {
    NSColor.white.setFill()
    iconPath.fill()
}

drawClipped(iconPath) {
    NSGradient(colors: [
        NSColor(calibratedRed: 0.94, green: 0.98, blue: 1.00, alpha: 1.0),
        NSColor(calibratedRed: 0.73, green: 0.90, blue: 1.00, alpha: 1.0),
        NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.96, alpha: 1.0)
    ])?.draw(in: iconRect, angle: -34)

    let cyanBlob = NSBezierPath(ovalIn: NSRect(x: 60, y: 74, width: 650, height: 650))
    NSGradient(colors: [
        NSColor(calibratedRed: 0.00, green: 0.72, blue: 1.00, alpha: 0.92),
        NSColor(calibratedRed: 0.07, green: 0.94, blue: 0.96, alpha: 0.35)
    ])?.draw(in: cyanBlob, angle: 22)

    let pinkBlob = NSBezierPath(ovalIn: NSRect(x: 420, y: 210, width: 560, height: 650))
    NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.92, alpha: 0.72),
        NSColor(calibratedRed: 1.00, green: 0.88, blue: 0.98, alpha: 0.20)
    ])?.draw(in: pinkBlob, angle: -18)

    let blueCorner = NSBezierPath(ovalIn: NSRect(x: -150, y: -120, width: 540, height: 520))
    NSColor(calibratedRed: 0.02, green: 0.48, blue: 1.00, alpha: 0.55).setFill()
    blueCorner.fill()

    let topHighlight = NSBezierPath(roundedRect: NSRect(x: 142, y: 756, width: 740, height: 92), xRadius: 46, yRadius: 46)
    NSColor.white.withAlphaComponent(0.42).setFill()
    topHighlight.fill()
}

let innerStroke = NSBezierPath(roundedRect: iconRect.insetBy(dx: 8, dy: 8), xRadius: 200, yRadius: 200)
NSColor.white.withAlphaComponent(0.76).setStroke()
innerStroke.lineWidth = 10
innerStroke.stroke()

NSColor(calibratedWhite: 0.74, alpha: 0.34).setStroke()
iconPath.lineWidth = 8
iconPath.stroke()

let speakerGroup = NSBezierPath()
speakerGroup.move(to: NSPoint(x: 272, y: 436))
speakerGroup.line(to: NSPoint(x: 372, y: 436))
speakerGroup.line(to: NSPoint(x: 520, y: 322))
speakerGroup.curve(to: NSPoint(x: 560, y: 358), controlPoint1: NSPoint(x: 540, y: 307), controlPoint2: NSPoint(x: 560, y: 320))
speakerGroup.line(to: NSPoint(x: 560, y: 666))
speakerGroup.curve(to: NSPoint(x: 520, y: 702), controlPoint1: NSPoint(x: 560, y: 704), controlPoint2: NSPoint(x: 540, y: 717))
speakerGroup.line(to: NSPoint(x: 372, y: 588))
speakerGroup.line(to: NSPoint(x: 272, y: 588))
speakerGroup.curve(to: NSPoint(x: 238, y: 554), controlPoint1: NSPoint(x: 251, y: 588), controlPoint2: NSPoint(x: 238, y: 575))
speakerGroup.line(to: NSPoint(x: 238, y: 470))
speakerGroup.curve(to: NSPoint(x: 272, y: 436), controlPoint1: NSPoint(x: 238, y: 449), controlPoint2: NSPoint(x: 251, y: 436))
speakerGroup.close()

drawShadow(color: NSColor(calibratedRed: 0.00, green: 0.42, blue: 0.90, alpha: 0.32), blur: 28, offset: NSSize(width: 0, height: -10)) {
    NSColor.white.withAlphaComponent(0.90).setFill()
    speakerGroup.fill()
}

NSColor.white.withAlphaComponent(0.92).setStroke()
speakerGroup.lineWidth = 5
speakerGroup.stroke()

for (index, radius) in [95, 158, 220].enumerated() {
    let wave = NSBezierPath()
    wave.appendArc(
        withCenter: NSPoint(x: 560, y: 512),
        radius: CGFloat(radius),
        startAngle: -42,
        endAngle: 42,
        clockwise: false
    )
    wave.lineCapStyle = .round
    wave.lineWidth = CGFloat(42 - index * 8)
    NSColor.white.withAlphaComponent(0.84 - CGFloat(index) * 0.17).setStroke()
    wave.stroke()
}

let glassGlint = NSBezierPath()
glassGlint.move(to: NSPoint(x: 346, y: 670))
glassGlint.curve(to: NSPoint(x: 506, y: 704), controlPoint1: NSPoint(x: 400, y: 712), controlPoint2: NSPoint(x: 472, y: 724))
glassGlint.lineWidth = 20
glassGlint.lineCapStyle = .round
NSColor.white.withAlphaComponent(0.38).setStroke()
glassGlint.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to render icon")
}

try png.write(to: outputURL)
