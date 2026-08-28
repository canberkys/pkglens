#!/usr/bin/swift
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background rounded rect (macOS icon shape)
let radius: CGFloat = 220
let path = CGMutablePath()
path.addRoundedRect(in: CGRect(x: 0, y: 0, width: size, height: size),
                    cornerWidth: radius, cornerHeight: radius)
ctx.addPath(path)
ctx.clip()

// Deep navy-to-indigo gradient background
let bgColors = [
    CGColor(red: 0.07, green: 0.08, blue: 0.18, alpha: 1),
    CGColor(red: 0.10, green: 0.12, blue: 0.28, alpha: 1)
] as CFArray
let bgLocs: [CGFloat] = [0, 1]
let bgSpace = CGColorSpaceCreateDeviceRGB()
let bgGrad = CGGradient(colorsSpace: bgSpace, colors: bgColors, locations: bgLocs)!
ctx.drawLinearGradient(bgGrad,
                       start: CGPoint(x: 0, y: size),
                       end:   CGPoint(x: size, y: 0),
                       options: [])

// ── Magnifying glass ──────────────────────────────────────────────────────
let cx: CGFloat = 490
let cy: CGFloat = 530
let glassR: CGFloat = 260    // outer lens radius
let glassW: CGFloat = 38     // ring stroke width
let handleLen: CGFloat = 180
let handleW: CGFloat = 44

// Lens glow
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 80,
              color: CGColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 0.45))
let glassRing = CGPath(ellipseIn: CGRect(x: cx-glassR, y: cy-glassR,
                                         width: glassR*2, height: glassR*2),
                       transform: nil)
ctx.addPath(glassRing)
ctx.setLineWidth(glassW)
ctx.setStrokeColor(CGColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1))
ctx.strokePath()
ctx.restoreGState()

// Lens ring fill (glass tint)
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: cx-glassR+glassW/2, y: cy-glassR+glassW/2,
                           width: (glassR-glassW/2)*2, height: (glassR-glassW/2)*2))
ctx.clip()
let lensColors = [
    CGColor(red: 0.18, green: 0.28, blue: 0.60, alpha: 0.35),
    CGColor(red: 0.10, green: 0.16, blue: 0.38, alpha: 0.55)
] as CFArray
let lensGrad = CGGradient(colorsSpace: bgSpace, colors: lensColors, locations: bgLocs)!
ctx.drawLinearGradient(lensGrad,
                       start: CGPoint(x: cx-glassR, y: cy+glassR),
                       end:   CGPoint(x: cx+glassR, y: cy-glassR),
                       options: [])
ctx.restoreGState()

// Handle (bottom-right, 45°)
let angle: CGFloat = -CGFloat.pi / 4     // 45° toward bottom-right
let hx1 = cx + (glassR - glassW/2) * cos(angle)
let hy1 = cy + (glassR - glassW/2) * sin(angle)
let hx2 = hx1 + handleLen * cos(angle)
let hy2 = hy1 + handleLen * sin(angle)

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 20,
              color: CGColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 0.4))
ctx.setLineCap(.round)
ctx.setLineWidth(handleW)
ctx.setStrokeColor(CGColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1))
ctx.move(to: CGPoint(x: hx1, y: hy1))
ctx.addLine(to: CGPoint(x: hx2, y: hy2))
ctx.strokePath()
ctx.restoreGState()

// ── Package manager dots inside the lens ─────────────────────────────────
// Colors: Homebrew amber, npm red, pip sky, Cargo orange, Gem red-pink
let dots: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
    // x      y       r     R      G      B
    ( cx-100, cy+60,  42,  0.95, 0.55, 0.15),  // Homebrew
    ( cx+75,  cy+80,  36,  0.90, 0.20, 0.20),  // npm
    ( cx-40,  cy-95,  38,  0.25, 0.60, 0.95),  // pip
    ( cx+110, cy-40,  32,  0.95, 0.40, 0.15),  // Cargo
    ( cx-110, cy-30,  30,  0.85, 0.20, 0.55),  // Gem
    ( cx+20,  cy+30,  24,  0.40, 0.80, 0.55),  // accent
]

for (dx, dy, dr, r, g, b) in dots {
    ctx.saveGState()
    // clip to lens interior
    ctx.addEllipse(in: CGRect(x: cx-glassR+glassW, y: cy-glassR+glassW,
                               width: (glassR-glassW)*2, height: (glassR-glassW)*2))
    ctx.clip()

    // glow
    ctx.setShadow(offset: .zero, blur: 22,
                  color: CGColor(red: r, green: g, blue: b, alpha: 0.7))
    let dotColors = [
        CGColor(red: r, green: g, blue: b, alpha: 1.0),
        CGColor(red: r*0.7, green: g*0.7, blue: b*0.7, alpha: 1.0)
    ] as CFArray
    let dotGrad = CGGradient(colorsSpace: bgSpace, colors: dotColors, locations: bgLocs)!
    let dotPath = CGPath(ellipseIn: CGRect(x: dx-dr, y: dy-dr, width: dr*2, height: dr*2),
                         transform: nil)
    ctx.addPath(dotPath)
    ctx.clip()
    ctx.drawRadialGradient(dotGrad,
                           startCenter: CGPoint(x: dx - dr*0.2, y: dy + dr*0.2),
                           startRadius: 0,
                           endCenter: CGPoint(x: dx, y: dy),
                           endRadius: dr,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// ── "PKG" text at top-left (subtle label) ────────────────────────────────
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 72, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 0.55, green: 0.75, blue: 1.0, alpha: 0.22)
]
let label = NSAttributedString(string: "PKG", attributes: attrs)
label.draw(at: NSPoint(x: 72, y: size - 72 - 72))

image.unlockFocus()

// Save as PNG
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.png"

if let tiff = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: outPath))
    print("Saved \(outPath)")
} else {
    print("ERROR: failed to generate PNG")
    exit(1)
}
