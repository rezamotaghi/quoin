#!/usr/bin/env swift
// Generates every Quoin icon artifact from ONE geometric spec.
// Design: simple vintage wood-type "Q". Cream slab letter on warm ink.
// Run via Scripts/make-icon.sh (assembles the .icns with iconutil).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func srgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

enum Palette {
    static let inkTop = srgb(0x332A20)     // warm ink, lit
    static let inkBottom = srgb(0x241D15)  // warm ink, shadowed
    static let cream = srgb(0xF3E9D2)      // aged paper
}

// The Q, in t-space: tile is 0..824 both axes, y down. Wood-type: a heavy
// ring (bowl) plus a straight tail kicking out through the lower right.
// Bowl center (412, 385); outer radius 200, inner 120 (80-unit stroke,
// same weight as the old E's arms). Tail: 72-unit bar crossing the bowl
// from inside the counter at (440, 470) out to (585, 630); glyph box
// approx x 212..610, y 185..655 (center 412).
enum QGlyph {
    static let center = CGPoint(x: 412, y: 385)
    static let outerRadius: CGFloat = 200
    static let innerRadius: CGFloat = 120
    static let tailStart = CGPoint(x: 440, y: 470)
    static let tailEnd = CGPoint(x: 585, y: 630)
    static let tailWidth: CGFloat = 72
}

/// Fills the Q in cream into a context already scaled to t-space.
func fillQ(_ ctx: CGContext) {
    ctx.setFillColor(Palette.cream)
    let outer = CGRect(x: QGlyph.center.x - QGlyph.outerRadius,
                       y: QGlyph.center.y - QGlyph.outerRadius,
                       width: QGlyph.outerRadius * 2, height: QGlyph.outerRadius * 2)
    let inner = CGRect(x: QGlyph.center.x - QGlyph.innerRadius,
                       y: QGlyph.center.y - QGlyph.innerRadius,
                       width: QGlyph.innerRadius * 2, height: QGlyph.innerRadius * 2)
    ctx.addEllipse(in: outer)
    ctx.addEllipse(in: inner)
    ctx.fillPath(using: .evenOdd)
    ctx.setStrokeColor(Palette.cream)
    ctx.setLineWidth(QGlyph.tailWidth)
    ctx.setLineCap(.butt)
    ctx.move(to: QGlyph.tailStart)
    ctx.addLine(to: QGlyph.tailEnd)
    ctx.strokePath()
}

func makeContext(_ px: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: px, height: px,
                        bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: 1, y: -1)  // y-down, like screen coordinates
    return ctx
}

func drawCard(_ ctx: CGContext, px: Int, insetPx: CGFloat, cornerT: CGFloat, shadow: Bool, opaque: Bool) {
    let side = CGFloat(px) - 2 * insetPx
    let f = side / 824
    let art = CGRect(x: insetPx, y: insetPx, width: side, height: side)
    let tile: CGPath = opaque
        ? CGPath(rect: CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)), transform: nil)
        : CGPath(roundedRect: art, cornerWidth: cornerT * f, cornerHeight: cornerT * f, transform: nil)

    if shadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * CGFloat(px) / 1024),
                      blur: 26 * CGFloat(px) / 1024, color: CGColor(gray: 0, alpha: 0.32))
        ctx.setFillColor(Palette.inkBottom)
        ctx.addPath(tile); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    ctx.translateBy(x: art.minX, y: art.minY)
    ctx.scaleBy(x: f, y: f)
    let bg = CGGradient(colorsSpace: sRGB,
                        colors: [Palette.inkTop, Palette.inkBottom] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 412, y: 0), end: CGPoint(x: 412, y: 824),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    fillQ(ctx)
    ctx.restoreGState()
}

/// 16 px: pixel-snapped Q so the ring and tail stay crisp.
func drawTiny(_ ctx: CGContext, px: Int, insetPx: CGFloat) {
    let tile = CGRect(x: insetPx, y: insetPx,
                      width: CGFloat(px) - 2 * insetPx, height: CGFloat(px) - 2 * insetPx)
    ctx.setFillColor(Palette.inkBottom)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 3, cornerHeight: 3, transform: nil))
    ctx.fillPath()
    ctx.setStrokeColor(Palette.cream)
    // Bowl: a 2px ring, nudged up-left so the tail gets room.
    let ring = CGRect(x: tile.minX + 3, y: tile.minY + 3,
                      width: tile.width - 7, height: tile.height - 7)
    ctx.setLineWidth(2)
    ctx.strokeEllipse(in: ring.insetBy(dx: 1, dy: 1))
    // Tail: a 2px diagonal out of the lower right.
    ctx.setFillColor(Palette.cream)
    ctx.fill([
        CGRect(x: tile.maxX - 6, y: tile.maxY - 6, width: 2, height: 2),
        CGRect(x: tile.maxX - 5, y: tile.maxY - 5, width: 2, height: 2),
        CGRect(x: tile.maxX - 4, y: tile.maxY - 4, width: 2, height: 2),
    ])
}

func render(px: Int, inset1024: CGFloat, cornerT: CGFloat, shadow: Bool, opaque: Bool) -> CGImage {
    let ctx = makeContext(px)
    let insetPx = inset1024 * CGFloat(px) / 1024
    if px <= 16 {
        drawTiny(ctx, px: px, insetPx: insetPx.rounded())
    } else {
        drawCard(ctx, px: px, insetPx: insetPx, cornerT: cornerT,
                 shadow: shadow && px >= 32, opaque: opaque)
    }
    return ctx.makeImage()!
}

func pngData(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

/// favicon.ico: 6-byte header + 16-byte directory per entry + PNG blobs.
func writeICO(_ entries: [(px: Int, data: Data)], to url: URL) throws {
    var out = Data()
    func le16(_ v: Int) { out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF)) }
    func le32(_ v: Int) { le16(v & 0xFFFF); le16((v >> 16) & 0xFFFF) }
    le16(0); le16(1); le16(entries.count)
    var offset = 6 + 16 * entries.count
    for e in entries {
        out.append(UInt8(e.px >= 256 ? 0 : e.px)); out.append(UInt8(e.px >= 256 ? 0 : e.px))
        out.append(0); out.append(0)
        le16(1); le16(32)
        le32(e.data.count); le32(offset)
        offset += e.data.count
    }
    for e in entries { out.append(e.data) }
    try out.write(to: url)
}

func svgMaster() -> String {
    let midRadius = (QGlyph.outerRadius + QGlyph.innerRadius) / 2
    let strokeWidth = QGlyph.outerRadius - QGlyph.innerRadius
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 824 824">
      <title>Quoin</title>
      <desc>Quoin icon: a vintage wood-type Q, cream on warm ink.</desc>
      <defs>
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#332A20"/><stop offset="1" stop-color="#241D15"/>
        </linearGradient>
      </defs>
      <rect width="824" height="824" rx="184" fill="url(#bg)"/>
      <g stroke="#F3E9D2" fill="none">
        <circle cx="\(QGlyph.center.x)" cy="\(QGlyph.center.y)" r="\(midRadius)" stroke-width="\(strokeWidth)"/>
        <line x1="\(QGlyph.tailStart.x)" y1="\(QGlyph.tailStart.y)" x2="\(QGlyph.tailEnd.x)" y2="\(QGlyph.tailEnd.y)" stroke-width="\(QGlyph.tailWidth)"/>
      </g>
    </svg>
    """
}

// MARK: - Main

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconsetDir = root.appendingPathComponent("build/icon-work/Quoin.iconset")
let assetsDir = root.appendingPathComponent("Assets/icon")
try? fm.removeItem(at: iconsetDir)
try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)

// macOS .icns: artwork on Apple's grid (inset ~10%, squircle ~22.5%).
let macFiles: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
var cache: [Int: CGImage] = [:]
for (name, px) in macFiles {
    let img = cache[px] ?? render(px: px, inset1024: 100, cornerT: 186, shadow: true, opaque: false)
    cache[px] = img
    try pngData(img).write(to: iconsetDir.appendingPathComponent(name))
}

// Web set: full-bleed rounded square, no shadow.
let web16 = render(px: 16, inset1024: 0, cornerT: 148, shadow: false, opaque: false)
let web32 = render(px: 32, inset1024: 0, cornerT: 148, shadow: false, opaque: false)
let web48 = render(px: 48, inset1024: 0, cornerT: 148, shadow: false, opaque: false)
try pngData(web16).write(to: assetsDir.appendingPathComponent("favicon-16.png"))
try pngData(web32).write(to: assetsDir.appendingPathComponent("favicon-32.png"))
try pngData(render(px: 512, inset1024: 0, cornerT: 148, shadow: false, opaque: false))
    .write(to: assetsDir.appendingPathComponent("icon-512.png"))
try pngData(render(px: 180, inset1024: 0, cornerT: 148, shadow: false, opaque: true))
    .write(to: assetsDir.appendingPathComponent("apple-touch-icon.png"))
try writeICO([(16, pngData(web16)), (32, pngData(web32)), (48, pngData(web48))],
             to: assetsDir.appendingPathComponent("favicon.ico"))
try svgMaster().write(to: assetsDir.appendingPathComponent("icon.svg"),
                      atomically: true, encoding: .utf8)

print("Rendered \(macFiles.count) iconset sizes + web set + SVG + favicon.ico")
