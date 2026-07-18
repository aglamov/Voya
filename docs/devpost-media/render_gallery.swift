import AppKit

let workspace = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let media = workspace.appendingPathComponent("docs/devpost-media")
let raw = media.appendingPathComponent("raw")
let output = media.appendingPathComponent("final")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let canvasSize = NSSize(width: 1800, height: 1200)
let navy = NSColor(calibratedRed: 0.035, green: 0.086, blue: 0.122, alpha: 1)
let teal = NSColor(calibratedRed: 0.015, green: 0.43, blue: 0.40, alpha: 1)
let mint = NSColor(calibratedRed: 0.79, green: 0.98, blue: 0.91, alpha: 1)
let warm = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.86, alpha: 1)

struct Card {
    let filename: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let chips: [String]
    let screenshots: [String]
    let number: String
}

let cards = [
    Card(
        filename: "01-voya-cover.png",
        eyebrow: "VOYA  ·  OPENAI BUILD WEEK",
        title: "From confirmation\nto the next best action.",
        subtitle: "The agentic travel companion that turns fragmented bookings into a verified, living journey.",
        chips: ["Agentic by design", "Grounded in live context", "Human in control"],
        screenshots: ["02-trips.png", "04-assistant.png"],
        number: "01"
    ),
    Card(
        filename: "02-inspiration.png",
        eyebrow: "START WITH A FEELING",
        title: "Tell Voya how you\nwant to feel.",
        subtitle: "Agents search, verify, and curate real possibilities — then you choose what becomes a trip.",
        chips: ["Search", "Verify", "Curate"],
        screenshots: ["05-inspiration-demo.png"],
        number: "02"
    ),
    Card(
        filename: "03-living-itinerary.png",
        eyebrow: "ONE CALM TIMELINE",
        title: "A verified,\nliving itinerary.",
        subtitle: "Bookings, transfer context, timing, and the next useful action stay together as the journey evolves.",
        chips: ["Flights", "Stays", "Transfers", "Events"],
        screenshots: ["02-trips.png"],
        number: "03"
    ),
    Card(
        filename: "04-smart-import.png",
        eyebrow: "BRING ANY CONFIRMATION",
        title: "Import the way\ntravel arrives.",
        subtitle: "Add PDFs, booking text, or photos. Voya extracts the itinerary and keeps uncertainty visible for review.",
        chips: ["PDF or text", "Paste", "Photo OCR"],
        screenshots: ["03-import.png"],
        number: "04"
    ),
    Card(
        filename: "05-trip-guardian.png",
        eyebrow: "PROACTIVE, NOT NOISY",
        title: "Trip Guardian sees\nthe whole journey.",
        subtitle: "Bounded agents watch the itinerary and live signals, surfacing only risks and actions that matter now.",
        chips: ["4 watched", "4 specialist agents", "Actionable alerts"],
        screenshots: ["04-assistant.png"],
        number: "05"
    )
]

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

func drawPhone(_ filename: String, rect: NSRect, border: CGFloat = 10) {
    guard let image = NSImage(contentsOf: raw.appendingPathComponent(filename)) else {
        fatalError("Missing screenshot: \(filename)")
    }

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
    shadow.shadowBlurRadius = 42
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    roundedRect(rect.insetBy(dx: -border, dy: -border), radius: 62, color: NSColor.white.withAlphaComponent(0.92))
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(roundedRect: rect, xRadius: 54, yRadius: 54)
    clip.addClip()
    image.draw(
        in: rect,
        from: NSRect(origin: .zero, size: image.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
}

func drawCard(_ card: Card) throws {
    let canvas = NSImage(size: canvasSize)
    canvas.lockFocusFlipped(true)

    let bounds = NSRect(origin: .zero, size: canvasSize)
    NSGradient(colors: [navy, NSColor(calibratedRed: 0.02, green: 0.20, blue: 0.22, alpha: 1), teal])!
        .draw(in: bounds, angle: 0)

    NSColor.white.withAlphaComponent(0.055).setFill()
    NSBezierPath(ovalIn: NSRect(x: 780, y: -320, width: 980, height: 980)).fill()
    NSColor(calibratedRed: 0.94, green: 0.73, blue: 0.18, alpha: 0.10).setFill()
    NSBezierPath(ovalIn: NSRect(x: -280, y: 760, width: 760, height: 760)).fill()

    guard let icon = NSImage(contentsOf: workspace.appendingPathComponent("Voya/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")) else {
        fatalError("Missing app icon")
    }
    roundedRect(NSRect(x: 88, y: 76, width: 96, height: 96), radius: 24, color: .white)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: NSRect(x: 88, y: 76, width: 96, height: 96), xRadius: 24, yRadius: 24).addClip()
    icon.draw(
        in: NSRect(x: 88, y: 76, width: 96, height: 96),
        from: NSRect(origin: .zero, size: icon.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()

    drawText(card.eyebrow, rect: NSRect(x: 210, y: 91, width: 690, height: 50), font: .systemFont(ofSize: 25, weight: .bold), color: mint)
    drawText(card.title, rect: NSRect(x: 88, y: 245, width: 900, height: 300), font: .systemFont(ofSize: 72, weight: .bold), color: .white, lineHeight: 82)
    drawText(card.subtitle, rect: NSRect(x: 92, y: 590, width: 805, height: 190), font: .systemFont(ofSize: 32, weight: .medium), color: NSColor.white.withAlphaComponent(0.76), lineHeight: 44)

    var chipX: CGFloat = 92
    var chipY: CGFloat = 840
    for chip in card.chips {
        let width = min(360, max(150, CGFloat(chip.count) * 16 + 52))
        if chipX + width > 900 {
            chipX = 92
            chipY += 76
        }
        roundedRect(NSRect(x: chipX, y: chipY, width: width, height: 58), radius: 29, color: NSColor.white.withAlphaComponent(0.11))
        drawText(chip, rect: NSRect(x: chipX + 25, y: chipY + 13, width: width - 50, height: 34), font: .systemFont(ofSize: 23, weight: .semibold), color: warm)
        chipX += width + 16
    }

    drawText(card.number + "  /  05", rect: NSRect(x: 92, y: 1085, width: 260, height: 50), font: .monospacedDigitSystemFont(ofSize: 23, weight: .semibold), color: NSColor.white.withAlphaComponent(0.50))

    if card.screenshots.count == 2 {
        drawPhone(card.screenshots[0], rect: NSRect(x: 1000, y: 205, width: 370, height: 804), border: 8)
        drawPhone(card.screenshots[1], rect: NSRect(x: 1262, y: 76, width: 455, height: 989), border: 9)
    } else {
        drawPhone(card.screenshots[0], rect: NSRect(x: 1126, y: 56, width: 500, height: 1087), border: 10)
    }

    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode \(card.filename)")
    }
    try png.write(to: output.appendingPathComponent(card.filename))
    print(card.filename)
}

for card in cards {
    try drawCard(card)
}
