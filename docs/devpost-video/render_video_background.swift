import AppKit

let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = workspace.appendingPathComponent("docs/devpost-video")
let size = NSSize(width: 1920, height: 1080)
let image = NSImage(size: size)

func roundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawText(_ value: String, rect: NSRect, font: NSFont, color: NSColor, lineHeight: CGFloat? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    if let lineHeight {
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
    }
    value.draw(in: rect, withAttributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ])
}

image.lockFocusFlipped(true)
let bounds = NSRect(origin: .zero, size: size)
NSGradient(colors: [
    NSColor(calibratedRed: 0.035, green: 0.086, blue: 0.122, alpha: 1),
    NSColor(calibratedRed: 0.015, green: 0.24, blue: 0.25, alpha: 1),
    NSColor(calibratedRed: 0.015, green: 0.43, blue: 0.40, alpha: 1)
])!.draw(in: bounds, angle: 0)

NSColor.white.withAlphaComponent(0.05).setFill()
NSBezierPath(ovalIn: NSRect(x: 780, y: -350, width: 1050, height: 1050)).fill()
NSColor(calibratedRed: 1, green: 0.75, blue: 0.22, alpha: 0.08).setFill()
NSBezierPath(ovalIn: NSRect(x: -310, y: 710, width: 760, height: 760)).fill()

let iconRect = NSRect(x: 92, y: 76, width: 104, height: 104)
if let appIcon = NSImage(contentsOf: workspace.appendingPathComponent("Voya/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: iconRect, xRadius: 26, yRadius: 26).addClip()
    appIcon.draw(
        in: iconRect,
        from: NSRect(origin: .zero, size: appIcon.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
}

let mint = NSColor(calibratedRed: 0.79, green: 0.98, blue: 0.91, alpha: 1)
drawText("VOYA  ·  OPENAI BUILD WEEK", rect: NSRect(x: 226, y: 105, width: 760, height: 45), font: .systemFont(ofSize: 25, weight: .bold), color: mint)
drawText("From confirmation\nto the next best action.", rect: NSRect(x: 92, y: 272, width: 1050, height: 210), font: .systemFont(ofSize: 68, weight: .bold), color: .white, lineHeight: 78)
drawText("A verified, living journey with bounded agents and grounded travel context.", rect: NSRect(x: 96, y: 535, width: 900, height: 125), font: .systemFont(ofSize: 31, weight: .medium), color: NSColor.white.withAlphaComponent(0.75), lineHeight: 43)

let pills: [(String, CGFloat)] = [("Inspiration", 190), ("Smart import", 205), ("Trip Guardian", 225)]
var pillX: CGFloat = 96
for (label, width) in pills {
    roundedRect(NSRect(x: pillX, y: 710, width: width, height: 58), radius: 29, color: NSColor.white.withAlphaComponent(0.11))
    drawText(label, rect: NSRect(x: pillX + 24, y: 724, width: width - 48, height: 32), font: .systemFont(ofSize: 22, weight: .semibold), color: NSColor(calibratedRed: 1, green: 0.96, blue: 0.84, alpha: 1))
    pillX += width + 18
}

drawText("BUILT WITH CODEX + GPT-5.6", rect: NSRect(x: 96, y: 930, width: 650, height: 42), font: .systemFont(ofSize: 24, weight: .bold), color: NSColor(calibratedRed: 1, green: 0.82, blue: 0.32, alpha: 1))

let phoneWidth: CGFloat = 460
let phoneHeight: CGFloat = 1000
let phoneX = size.width - phoneWidth - 92
let phoneY: CGFloat = 40
roundedRect(NSRect(x: phoneX - 12, y: phoneY - 12, width: phoneWidth + 24, height: phoneHeight + 24), radius: 58, color: NSColor.white.withAlphaComponent(0.94))

image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: folder.appendingPathComponent("background.png"))
print(folder.appendingPathComponent("background.png").path)
