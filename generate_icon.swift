// Programmatically draw the Calendar app icon at every iconset size.
// Theme: a white calendar page with a red header bar and date grid —
// the familiar macOS Calendar silhouette. Used by build_app.sh:
//   swift generate_icon.swift <output.iconset>

import AppKit
import Foundation

let sizes: [(px: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func superellipsePath(in rect: NSRect, n: CGFloat = 5) -> NSBezierPath {
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let path = NSBezierPath()
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * copysign(pow(abs(ct), 2 / n), ct)
        let y = cy + b * copysign(pow(abs(st), 2 / n), st)
        if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    defer { img.unlockFocus() }

    let margin = size * 0.09
    let body = NSRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let bgPath = superellipsePath(in: body)
    bgPath.addClip()

    // Page fill.
    NSColor.white.setFill()
    bgPath.fill()

    // Red header band (top ~28% of the body).
    let headerH = body.height * 0.28
    let header = NSRect(x: body.minX, y: body.maxY - headerH, width: body.width, height: headerH)
    let headerGrad = NSGradient(colors: [
        NSColor(srgbRed: 0.95, green: 0.30, blue: 0.28, alpha: 1),
        NSColor(srgbRed: 0.86, green: 0.18, blue: 0.18, alpha: 1),
    ])!
    headerGrad.draw(in: header, angle: -90)

    // Binding rings on the header.
    let ringCount = 3
    let ringY = body.maxY - headerH * 0.55
    let ringR = max(1.2, size * 0.028)
    let ringSpan = body.width * 0.46
    let ringStartX = body.midX - ringSpan / 2
    for i in 0..<ringCount {
        let t = CGFloat(i) / CGFloat(max(ringCount - 1, 1))
        let cx = ringStartX + t * ringSpan
        let oval = NSRect(x: cx - ringR, y: ringY - ringR, width: ringR * 2, height: ringR * 2)
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: oval).fill()
    }

    // Date grid dots (3×3) in the lower page area.
    let gridArea = NSRect(
        x: body.minX + body.width * 0.20,
        y: body.minY + body.height * 0.14,
        width: body.width * 0.60,
        height: body.height * 0.42)
    let cols = 3, rows = 3
    let cellW = gridArea.width / CGFloat(cols)
    let cellH = gridArea.height / CGFloat(rows)
    let dotR = max(1.0, size * 0.035)
    let ink = NSColor(srgbRed: 0.22, green: 0.24, blue: 0.28, alpha: 1)
    ink.setFill()
    for r in 0..<rows {
        for c in 0..<cols {
            // Skip one cell to suggest "today" emphasis with a filled pill.
            if r == 1 && c == 1 {
                let pillW = cellW * 0.55
                let pillH = cellH * 0.55
                let pill = NSRect(
                    x: gridArea.minX + CGFloat(c) * cellW + (cellW - pillW) / 2,
                    y: gridArea.minY + CGFloat(rows - 1 - r) * cellH + (cellH - pillH) / 2,
                    width: pillW, height: pillH)
                NSColor(srgbRed: 0.90, green: 0.25, blue: 0.22, alpha: 1).setFill()
                NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2).fill()
                ink.setFill()
                continue
            }
            let cx = gridArea.minX + CGFloat(c) * cellW + cellW / 2
            let cy = gridArea.minY + CGFloat(rows - 1 - r) * cellH + cellH / 2
            let oval = NSRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)
            NSBezierPath(ovalIn: oval).fill()
        }
    }

    // Soft top highlight over the clipped squircle.
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.18),
        NSColor.white.withAlphaComponent(0.0),
    ])!
    highlight.draw(in: bgPath, angle: -90)

    return img
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(
        "usage: swift generate_icon.swift <iconset-dir>\n".data(using: .utf8)!)
    exit(1)
}
let outputDir = args[1]
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for entry in sizes {
    let img = drawIcon(size: CGFloat(entry.px))
    guard let tiff = img.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write("failed to encode \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: "\(outputDir)/\(entry.name)"))
    print("  \(entry.name) (\(entry.px)px)")
}
