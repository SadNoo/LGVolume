import AppKit

private let canvasSize: CGFloat = 1024
private let resourcesURL = URL(fileURLWithPath: "Resources", isDirectory: true)
private let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)

private func withShadow(color: NSColor, blur: CGFloat, offsetY: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: offsetY)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

private func speakerPath() -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 208, y: 424))
    path.line(to: NSPoint(x: 336, y: 424))
    path.line(to: NSPoint(x: 506, y: 292))
    path.curve(to: NSPoint(x: 566, y: 338), controlPoint1: NSPoint(x: 542, y: 265), controlPoint2: NSPoint(x: 566, y: 286))
    path.line(to: NSPoint(x: 566, y: 686))
    path.curve(to: NSPoint(x: 506, y: 732), controlPoint1: NSPoint(x: 566, y: 738), controlPoint2: NSPoint(x: 542, y: 759))
    path.line(to: NSPoint(x: 336, y: 600))
    path.line(to: NSPoint(x: 208, y: 600))
    path.curve(to: NSPoint(x: 170, y: 562), controlPoint1: NSPoint(x: 185, y: 600), controlPoint2: NSPoint(x: 170, y: 585))
    path.line(to: NSPoint(x: 170, y: 462))
    path.curve(to: NSPoint(x: 208, y: 424), controlPoint1: NSPoint(x: 170, y: 439), controlPoint2: NSPoint(x: 185, y: 424))
    path.close()
    return path
}

private func drawIcon(simplified: Bool) {
    let iconRect = NSRect(x: 42, y: 42, width: 940, height: 940)
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 202, yRadius: 202)

    withShadow(color: .black.withAlphaComponent(0.22), blur: 34, offsetY: -12) {
        NSColor.white.setFill()
        iconPath.fill()
    }

    NSGraphicsContext.saveGraphicsState()
    iconPath.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.73, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.18, green: 0.91, blue: 0.91, alpha: 1),
        NSColor(calibratedRed: 0.92, green: 0.62, blue: 0.98, alpha: 1)
    ])?.draw(in: iconRect, angle: -28)

    let lowerBlue = NSBezierPath(ovalIn: NSRect(x: -80, y: -120, width: 690, height: 700))
    NSColor(calibratedRed: 0.02, green: 0.42, blue: 0.96, alpha: simplified ? 0.55 : 0.62).setFill()
    lowerBlue.fill()

    let pinkLight = NSBezierPath(ovalIn: NSRect(x: 440, y: 190, width: 680, height: 700))
    NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.96, alpha: simplified ? 0.34 : 0.42).setFill()
    pinkLight.fill()

    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.78).setStroke()
    iconPath.lineWidth = simplified ? 15 : 11
    iconPath.stroke()

    let speaker = speakerPath()
    withShadow(color: NSColor(calibratedRed: 0.01, green: 0.18, blue: 0.43, alpha: 0.38), blur: simplified ? 18 : 28, offsetY: -8) {
        NSColor.white.withAlphaComponent(0.96).setFill()
        speaker.fill()
    }
    NSColor(calibratedRed: 0.04, green: 0.24, blue: 0.48, alpha: 0.26).setStroke()
    speaker.lineWidth = simplified ? 14 : 8
    speaker.stroke()

    let radii: [CGFloat] = simplified ? [116, 216] : [108, 182, 254]
    for (index, radius) in radii.enumerated() {
        let wave = NSBezierPath()
        wave.appendArc(
            withCenter: NSPoint(x: 566, y: 512),
            radius: radius,
            startAngle: -42,
            endAngle: 42,
            clockwise: false
        )
        wave.lineCapStyle = .round
        wave.lineWidth = simplified ? CGFloat(58 - index * 12) : CGFloat(48 - index * 9)
        NSColor(calibratedRed: 0.04, green: 0.24, blue: 0.48, alpha: 0.22).setStroke()
        wave.stroke()

        wave.lineWidth -= simplified ? 10 : 7
        NSColor.white.withAlphaComponent(0.94 - CGFloat(index) * 0.12).setStroke()
        wave.stroke()
    }
}

private func render(size: Int, simplified: Bool) throws -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / canvasSize)
    transform.concat()
    drawIcon(simplified: simplified)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return png
}

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

var renderedBySize: [Int: Data] = [:]
for (name, size) in outputs {
    let data = try render(size: size, simplified: size <= 64)
    renderedBySize[size] = data
    try data.write(to: iconsetURL.appendingPathComponent(name), options: .atomic)
}
guard let largestIcon = renderedBySize[1024] else {
    throw CocoaError(.fileWriteUnknown)
}
try largestIcon.write(to: resourcesURL.appendingPathComponent("AppIcon-1024.png"), options: .atomic)

let multiRepresentationImage = NSImage()
for size in renderedBySize.keys.sorted() {
    guard let data = renderedBySize[size], let representation = NSBitmapImageRep(data: data) else {
        continue
    }
    representation.size = NSSize(width: size, height: size)
    multiRepresentationImage.addRepresentation(representation)
}
guard let multiPageTIFF = multiRepresentationImage.tiffRepresentation else {
    throw CocoaError(.fileWriteUnknown)
}
let tiffURL = resourcesURL.appendingPathComponent("AppIcon.tiff")
try multiPageTIFF.write(to: tiffURL, options: .atomic)

let tiff2icns = Process()
tiff2icns.executableURL = URL(fileURLWithPath: "/usr/bin/tiff2icns")
tiff2icns.arguments = [tiffURL.path, resourcesURL.appendingPathComponent("AppIcon.icns").path]
try tiff2icns.run()
tiff2icns.waitUntilExit()
guard tiff2icns.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

print("Generated AppIcon-1024.png, AppIcon.iconset, and AppIcon.icns")
