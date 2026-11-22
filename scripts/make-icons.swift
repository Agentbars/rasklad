// Draws every Rasklad image from code, so the artwork lives in the repo as source.
//
//   swift scripts/make-icons.swift
//
// Writes into Resources/:
//   AppIcon.icon/            Icon Composer bundle; build.sh compiles it with actool into
//                            Assets.car (macOS 26+ Liquid Glass) and AppIcon.icns (older macOS)
//   MenuBarIcon.png, MenuBarIcon@2x.png   template image for the menu bar
// and into docs/:
//   logo.png (512), social-preview.png (1280x640, upload in GitHub repo settings)

import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let resources = root.appendingPathComponent("Resources")
let docs = root.appendingPathComponent("docs")

// MARK: - Palette

let bgTop = NSColor(srgbRed: 0.26, green: 0.42, blue: 1.00, alpha: 1)    // blue
let bgBottom = NSColor(srgbRed: 0.47, green: 0.25, blue: 0.93, alpha: 1) // violet
let latinColor = NSColor(srgbRed: 0.16, green: 0.33, blue: 0.93, alpha: 1)
let cyrillicColor = NSColor(srgbRed: 0.45, green: 0.22, blue: 0.88, alpha: 1)
let arrowColor = NSColor(srgbRed: 0.62, green: 0.66, blue: 0.78, alpha: 1)

// MARK: - Drawing helpers

func image(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: d, size: size) ?? base
}

/// Draws a glyph centered at `center` (y up), sized by its real outline, not the line box.
func drawGlyph(_ text: String, font: NSFont, color: NSColor, center: CGPoint, in ctx: CGContext) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.setFillColor(color.cgColor)
    ctx.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
    // Fill with the context color instead of the attributed string's default black.
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    for run in runs {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(), &glyphs)
        CTRunGetPositions(run, CFRange(), &positions)
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        for i in 0..<count {
            if let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
                ctx.saveGState()
                ctx.translateBy(x: ctx.textPosition.x + positions[i].x, y: ctx.textPosition.y + positions[i].y)
                ctx.addPath(path)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }
    ctx.restoreGState()
}

/// Two curved arrows in the empty corners: Z → Я over the top-right, Я → Z under the bottom-left.
func drawSwapArrows(center c: CGPoint, radius r: CGFloat, width: CGFloat, color: NSColor, in ctx: CGContext) {
    ctx.saveGState()
    ctx.setStrokeColor(color.cgColor)
    ctx.setFillColor(color.cgColor)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    let head = width * 1.9
    let deg = CGFloat.pi / 180
    // Clockwise arcs; each ends with an arrowhead pointing along the direction of travel.
    for (from, to) in [(78 * deg, 12 * deg), (258 * deg, 192 * deg)] {
        let stop = to + 0.16 // leave room for the head
        ctx.addArc(center: c, radius: r, startAngle: from, endAngle: stop, clockwise: true)
        ctx.strokePath()
        let tip = CGPoint(x: c.x + r * cos(to), y: c.y + r * sin(to))
        let dir = CGPoint(x: sin(to), y: -cos(to)) // clockwise tangent
        let normal = CGPoint(x: cos(to), y: sin(to))
        ctx.move(to: CGPoint(x: tip.x + dir.x * head * 0.45, y: tip.y + dir.y * head * 0.45))
        ctx.addLine(to: CGPoint(x: tip.x - dir.x * head * 0.9 + normal.x * head * 0.8, y: tip.y - dir.y * head * 0.9 + normal.y * head * 0.8))
        ctx.addLine(to: CGPoint(x: tip.x - dir.x * head * 0.9 - normal.x * head * 0.8, y: tip.y - dir.y * head * 0.9 - normal.y * head * 0.8))
        ctx.closePath()
        ctx.fillPath()
    }
    ctx.restoreGState()
}

// MARK: - Icon pieces (1024 canvas, y up)

let S: CGFloat = 1024
let keycapRect = CGRect(x: 182, y: 182, width: 660, height: 660)
let keycapRadius: CGFloat = 150

func drawBackground(_ ctx: CGContext, rect: CGRect) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
}

func drawKeycap(_ ctx: CGContext, glass: Bool) {
    if !glass {
        // Classic look: soft drop shadow and a slightly darker bottom edge, like a real key.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: NSColor.black.withAlphaComponent(0.30).cgColor)
        ctx.setFillColor(NSColor(white: 0.86, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: keycapRect.offsetBy(dx: 0, dy: -22), cornerWidth: keycapRadius, cornerHeight: keycapRadius, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(CGPath(roundedRect: keycapRect, cornerWidth: keycapRadius, cornerHeight: keycapRadius, transform: nil))
    ctx.fillPath()
}

func drawLegend(_ ctx: CGContext) {
    let font = roundedFont(270, .heavy)
    let inset: CGFloat = 200
    drawGlyph("Z", font: font, color: latinColor, center: CGPoint(x: keycapRect.minX + inset, y: keycapRect.maxY - inset), in: ctx)
    drawGlyph("Я", font: font, color: cyrillicColor, center: CGPoint(x: keycapRect.maxX - inset, y: keycapRect.minY + inset), in: ctx)
    drawSwapArrows(center: CGPoint(x: keycapRect.midX, y: keycapRect.midY), radius: 215, width: 30, color: arrowColor, in: ctx)
}

/// Flat rendering for the README logo: Apple's macOS grid puts the 824pt rounded square inside a 1024 canvas.
func classicIcon(_ size: Int) -> NSBitmapImageRep {
    image(size, size) { ctx in
        let k = CGFloat(size) / S
        ctx.scaleBy(x: k, y: k)
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.addPath(tilePath); ctx.setFillColor(bgTop.cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(tilePath); ctx.clip()
        drawBackground(ctx, rect: tile)
        // Scale the keycap art (drawn for a full-bleed 1024 square) into the tile.
        ctx.translateBy(x: tile.minX, y: tile.minY)
        ctx.scaleBy(x: tile.width / S, y: tile.height / S)
        drawKeycap(ctx, glass: false)
        drawLegend(ctx)
        ctx.restoreGState()
    }
}

// MARK: - Icon Composer bundle (background is the bundle's fill, layers are full-bleed 1024)

func writeIconComposerBundle() {
    let bundle = resources.appendingPathComponent("AppIcon.icon")
    try? FileManager.default.removeItem(at: bundle)
    save(image(1024, 1024) { drawKeycap($0, glass: true) }, bundle.appendingPathComponent("Assets/keycap.png"))
    save(image(1024, 1024) { drawLegend($0) }, bundle.appendingPathComponent("Assets/legend.png"))
    func p3(_ c: NSColor) -> String {
        let c = c.usingColorSpace(.extendedSRGB)!
        return String(format: "extended-srgb:%.5f,%.5f,%.5f,1.00000", c.redComponent, c.greenComponent, c.blueComponent)
    }
    let json = """
    {
      "fill" : {
        "linear-gradient" : [
          "\(p3(bgTop))",
          "\(p3(bgBottom))"
        ]
      },
      "groups" : [
        {
          "layers" : [
            { "image-name" : "legend.png", "name" : "legend" }
          ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.4 },
          "translucency" : { "enabled" : false, "value" : 0 }
        },
        {
          "layers" : [
            { "image-name" : "keycap.png", "name" : "keycap" }
          ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
          "translucency" : { "enabled" : true, "value" : 0.15 }
        }
      ],
      "supported-platforms" : {
        "squares" : [ "macOS" ]
      }
    }
    """
    try! json.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
}

// MARK: - Menu bar template (black on transparent; macOS tints it)

func menuBarIcon(scale: Int) -> NSBitmapImageRep {
    let w = 22, h = 18 // points
    return image(w * scale, h * scale) { ctx in
        let k = CGFloat(scale)
        ctx.scaleBy(x: k, y: k)
        let cap = CGRect(x: 1.5, y: 1.5, width: 19, height: 15)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.4)
        ctx.addPath(CGPath(roundedRect: cap, cornerWidth: 3.8, cornerHeight: 3.8, transform: nil))
        ctx.strokePath()
        let font = roundedFont(8.6, .bold)
        drawGlyph("Z", font: font, color: .black, center: CGPoint(x: cap.minX + 5.4, y: cap.maxY - 4.6), in: ctx)
        drawGlyph("Я", font: font, color: .black, center: CGPoint(x: cap.maxX - 5.4, y: cap.minY + 4.6), in: ctx)
    }
}

// MARK: - README logo and GitHub social preview

func socialPreview() -> NSBitmapImageRep {
    image(1280, 640) { ctx in
        drawBackground(ctx, rect: CGRect(x: 0, y: 0, width: 1280, height: 640))
        // Icon on the left
        ctx.saveGState()
        ctx.translateBy(x: 90, y: 120)
        ctx.scaleBy(x: 400 / S, y: 400 / S)
        drawKeycap(ctx, glass: false)
        drawLegend(ctx)
        ctx.restoreGState()
        // Title and tagline on the right
        let title = NSAttributedString(string: "Rasklad", attributes: [
            .font: roundedFont(118, .heavy), .foregroundColor: NSColor.white])
        let tagline = NSAttributedString(string: "Typed in the wrong layout?\nDouble-tap Shift.", attributes: [
            .font: roundedFont(50, .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.88)])
        title.draw(at: CGPoint(x: 560, y: 330))
        tagline.draw(in: CGRect(x: 562, y: 150, width: 680, height: 150))
    }
}

try! FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
writeIconComposerBundle()
save(menuBarIcon(scale: 1), resources.appendingPathComponent("MenuBarIcon.png"))
save(menuBarIcon(scale: 2), resources.appendingPathComponent("MenuBarIcon@2x.png"))
save(classicIcon(512), docs.appendingPathComponent("logo.png"))
save(socialPreview(), docs.appendingPathComponent("social-preview.png"))
print("Icons written to \(resources.path) and \(docs.path)")
