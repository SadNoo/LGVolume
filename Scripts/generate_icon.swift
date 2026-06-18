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
let iconRect = rect.insetBy(dx: 10, dy: 10)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 224, yRadius: 224)

drawShadow(color: NSColor.black.withAlphaComponent(0.20), blur: 34, offset: NSSize(width: 0, height: -10)) {
    NSColor.white.setFill()
    iconPath.fill()
}

drawClipped(iconPath) {
    NSGradient(colors: [
        NSColor(calibratedRed: 0.94, green: 0.98, blue: 1.00, alpha: 1.0),
        NSColor(calibratedRed: 0.73, green: 0.90, blue: 1.00, alpha: 1.0),
        NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.96, alpha: 1.0)
    ])?.draw(in: iconRect, angle: -34)

    let cyanBlob = NSBezierPath(ovalIn: NSRect(x: -18, y: 42, width: 720, height: 720))
    NSGradient(colors: [
        NSColor(calibratedRed: 0.00, green: 0.72, blue: 1.00, alpha: 0.92),
        NSColor(calibratedRed: 0.07, green: 0.94, blue: 0.96, alpha: 0.35)
    ])?.draw(in: cyanBlob, angle: 22)

    let pinkBlob = NSBezierPath(ovalIn: NSRect(x: 360, y: 168, width: 690, height: 735))
    NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.92, alpha: 0.72),
        NSColor(calibratedRed: 1.00, green: 0.88, blue: 0.98, alpha: 0.20)
    ])?.draw(in: pinkBlob, angle: -18)

    let blueCorner = NSBezierPath(ovalIn: NSRect(x: -170, y: -140, width: 620, height: 590))
    NSColor(calibratedRed: 0.02, green: 0.48, blue: 1.00, alpha: 0.55).setFill()
    blueCorner.fill()

    let topHighlight = NSBezierPath(roundedRect: NSRect(x: 122, y: 766, width: 780, height: 96), xRadius: 48, yRadius: 48)
    NSColor.white.withAlphaComponent(0.42).setFill()
    topHighlight.fill()
}

let innerStroke = NSBezierPath(roundedRect: iconRect.insetBy(dx: 8, dy: 8), xRadius: 216, yRadius: 216)
NSColor.white.withAlphaComponent(0.76).setStroke()
innerStroke.lineWidth = 10
innerStroke.stroke()

NSColor(calibratedWhite: 0.74, alpha: 0.34).setStroke()
iconPath.lineWidth = 8
iconPath.stroke()

let speakerGroup = NSBezierPath()
speakerGroup.move(to: NSPoint(x: 216, y: 420))
speakerGroup.line(to: NSPoint(x: 344, y: 420))
speakerGroup.line(to: NSPoint(x: 524, y: 284))
speakerGroup.curve(to: NSPoint(x: 574, y: 330), controlPoint1: NSPoint(x: 552, y: 264), controlPoint2: NSPoint(x: 574, y: 286))
speakerGroup.line(to: NSPoint(x: 574, y: 694))
speakerGroup.curve(to: NSPoint(x: 524, y: 740), controlPoint1: NSPoint(x: 574, y: 738), controlPoint2: NSPoint(x: 552, y: 760))
speakerGroup.line(to: NSPoint(x: 344, y: 604))
speakerGroup.line(to: NSPoint(x: 216, y: 604))
speakerGroup.curve(to: NSPoint(x: 178, y: 566), controlPoint1: NSPoint(x: 193, y: 604), controlPoint2: NSPoint(x: 178, y: 589))
speakerGroup.line(to: NSPoint(x: 178, y: 458))
speakerGroup.curve(to: NSPoint(x: 216, y: 420), controlPoint1: NSPoint(x: 178, y: 435), controlPoint2: NSPoint(x: 193, y: 420))
speakerGroup.close()

drawShadow(color: NSColor(calibratedRed: 0.00, green: 0.42, blue: 0.90, alpha: 0.32), blur: 28, offset: NSSize(width: 0, height: -10)) {
    NSColor.white.withAlphaComponent(0.90).setFill()
    speakerGroup.fill()
}

NSColor.white.withAlphaComponent(0.92).setStroke()
speakerGroup.lineWidth = 5
speakerGroup.stroke()

for (index, radius) in [105, 178, 252].enumerated() {
    let wave = NSBezierPath()
    wave.appendArc(
        withCenter: NSPoint(x: 574, y: 512),
        radius: CGFloat(radius),
        startAngle: -42,
        endAngle: 42,
        clockwise: false
    )
    wave.lineCapStyle = .round
    wave.lineWidth = CGFloat(46 - index * 9)
    NSColor.white.withAlphaComponent(0.84 - CGFloat(index) * 0.17).setStroke()
    wave.stroke()
}

let glassGlint = NSBezierPath()
glassGlint.move(to: NSPoint(x: 308, y: 682))
glassGlint.curve(to: NSPoint(x: 506, y: 728), controlPoint1: NSPoint(x: 376, y: 730), controlPoint2: NSPoint(x: 462, y: 752))
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
