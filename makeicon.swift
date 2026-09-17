import AppKit

// Zeichnet das App-Icon aufloesungsunabhaengig (Koordinaten als Bruchteile von S, y nach oben).
// Motiv: Kaffeetasse mit blauem Dampf in den ChatGBuetti-Farben.
func drawIcon(_ ctx: CGContext, _ S: CGFloat) {
    let cream  = NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1)
    let bgTop  = NSColor(srgbRed: 16.0 / 255, green: 22.0 / 255, blue: 39.0 / 255, alpha: 1)
    let bgBot  = NSColor(srgbRed: 10.0 / 255, green: 14.0 / 255, blue: 26.0 / 255, alpha: 1)

    // Abgerundetes Quadrat (macOS-Squircle-Proportionen) mit transparentem Rand
    let margin = S * 0.098
    let rectSq = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let radius = rectSq.width * 0.225
    let squircle = NSBezierPath(roundedRect: rectSq, xRadius: radius, yRadius: radius)

    // Weicher Schlagschatten
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.006), blur: S * 0.02,
                  color: NSColor.black.withAlphaComponent(0.4).cgColor)
    NSColor(white: 0.1, alpha: 1).setFill()
    squircle.fill()
    ctx.restoreGState()

    // Ab hier alles auf das Squircle beschneiden
    ctx.saveGState()
    squircle.addClip()

    // Hintergrund-Verlauf + Licht oben
    (NSGradient(colors: [bgTop, bgBot]) ?? NSGradient(starting: .black, ending: .black)!)
        .draw(in: rectSq, angle: -90)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.10), .clear])?
        .draw(in: CGRect(x: rectSq.minX, y: rectSq.midY, width: rectSq.width, height: rectSq.height / 2), angle: -90)

    // ChatGBuetti-Blau #2563eb hinter der Tasse
    NSGradient(colors: [NSColor(srgbRed: 37.0 / 255, green: 99.0 / 255, blue: 235.0 / 255, alpha: 0.30), .clear])?
        .draw(fromCenter: CGPoint(x: 0.46 * S, y: 0.50 * S), radius: 0,
              toCenter: CGPoint(x: 0.46 * S, y: 0.50 * S), radius: 0.34 * S, options: [])

    // Henkel als Ring (Loch per Even-Odd -> zeigt Hintergrund); die Tasse verdeckt spaeter die linke Haelfte
    let ring = NSBezierPath(); ring.windingRule = .evenOdd
    ring.appendOval(in: CGRect(x: 0.615 * S - 0.085 * S, y: 0.45 * S - 0.10 * S, width: 0.17 * S, height: 0.20 * S))
    ring.appendOval(in: CGRect(x: 0.615 * S - 0.045 * S, y: 0.45 * S - 0.06 * S, width: 0.09 * S, height: 0.12 * S))
    cream.setFill(); ring.fill()

    // Tassenkoerper mit Verlauf
    let bodyRect = CGRect(x: 0.285 * S, y: 0.31 * S, width: 0.315 * S, height: 0.29 * S)
    let body = NSBezierPath(roundedRect: bodyRect, xRadius: 0.045 * S, yRadius: 0.045 * S)
    ctx.saveGState(); body.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.99, green: 0.99, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.80, green: 0.84, blue: 0.92, alpha: 1)])?
        .draw(in: bodyRect, angle: -90)
    ctx.restoreGState()

    // Glanzstreifen links
    NSColor.white.withAlphaComponent(0.35).setFill()
    NSBezierPath(roundedRect: CGRect(x: bodyRect.minX + 0.022 * S, y: bodyRect.minY + 0.03 * S,
                                     width: 0.028 * S, height: bodyRect.height - 0.09 * S),
                 xRadius: 0.014 * S, yRadius: 0.014 * S).fill()

    // Kaffee-Oberflaeche (Ellipse am oberen Rand)
    let coffee = CGRect(x: bodyRect.minX + 0.028 * S, y: bodyRect.maxY - 0.03 * S,
                        width: bodyRect.width - 0.056 * S, height: 0.058 * S)
    NSColor(srgbRed: 0.30, green: 0.17, blue: 0.10, alpha: 1).setFill()
    NSBezierPath(ovalIn: coffee).fill()
    NSColor(srgbRed: 0.52, green: 0.33, blue: 0.20, alpha: 0.85).setFill()
    NSBezierPath(ovalIn: CGRect(x: coffee.minX + coffee.width * 0.2, y: coffee.minY + coffee.height * 0.28,
                                width: coffee.width * 0.4, height: coffee.height * 0.44)).fill()
    cream.setStroke()
    let rim = NSBezierPath(ovalIn: coffee); rim.lineWidth = 0.008 * S; rim.stroke()

    // Dampf mit dem hellen ChatGBuetti-Akzent #6ea8ff
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 0.02 * S,
                  color: NSColor(srgbRed: 37.0 / 255, green: 99.0 / 255, blue: 235.0 / 255, alpha: 0.7).cgColor)
    NSColor(srgbRed: 110.0 / 255, green: 168.0 / 255, blue: 1, alpha: 0.92).setStroke()
    func steam(_ cx: CGFloat, _ baseY: CGFloat, _ h: CGFloat, _ amp: CGFloat) {
        let p = NSBezierPath(); p.lineWidth = 0.028 * S; p.lineCapStyle = .round
        p.move(to: CGPoint(x: cx, y: baseY))
        p.curve(to: CGPoint(x: cx, y: baseY + h),
                controlPoint1: CGPoint(x: cx + amp, y: baseY + h * 0.33),
                controlPoint2: CGPoint(x: cx - amp, y: baseY + h * 0.66))
        p.stroke()
    }
    steam(0.372 * S, 0.615 * S, 0.16 * S, 0.030 * S)
    steam(0.443 * S, 0.625 * S, 0.20 * S, 0.035 * S)
    steam(0.514 * S, 0.615 * S, 0.16 * S, 0.030 * S)
    ctx.restoreGState()

    ctx.restoreGState() // Squircle-Clip
}

func renderPNG(size: Int, to path: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    drawIcon(gctx.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "WachModus.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let targets: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in targets { renderPNG(size: px, to: "\(outDir)/\(name)") }
print("Icon-PNGs erzeugt in \(outDir)")
