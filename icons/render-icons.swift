// render-icons.swift
//
// Native CoreGraphics renderer for the app icon and menu bar template PNGs.
//
// Rendering is done natively (not via qlmanage -t) because qlmanage
// rasterizes SVGs against an opaque white QuickLook canvas, which bakes an
// opaque white background into the PNG and breaks both the app icon's
// rounded-corner transparency and the menu bar template image's
// alpha-based rendering.
//
// This script hard-codes the geometry from icons/c-branch-key.svg (app
// icon) and icons/menubar.svg (menu bar glyph) and draws directly with
// CoreGraphics into bitmap contexts that have a fully transparent backing,
// so every non-painted pixel has alpha == 0.
//
// The mark is a git branch graph whose trunk ends in key teeth: a commit
// node at the top, a branch curving off to a second node, and a trunk line
// running down into a row of teeth pointing left (like a key bit).
//
// Run with: swift render-icons.swift   (from the icons/ directory)

import AppKit
import CoreGraphics
import Foundation

// MARK: - PNG export helpers

func writePNG(_ image: NSBitmapImageRep, to path: String) {
    guard let data = image.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(path)")
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        fatalError("Failed to write \(path): \(error)")
    }
}

/// Creates a CGContext with a transparent backing store at the given pixel
/// size, flipped so that (0,0) is the top-left corner and y grows downward
/// -- matching SVG coordinate conventions.
func makeContext(width: Int, height: Int) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CGContext")
    }
    // Flip so drawing coordinates match SVG (y grows downward).
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    return ctx
}

func saveContext(_ ctx: CGContext, to path: String) {
    guard let cgImage = ctx.makeImage() else {
        fatalError("Failed to make CGImage for \(path)")
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    writePNG(rep, to: path)
}

// MARK: - Drawing primitives

func drawStrokedCircle(
    ctx: CGContext,
    center: CGPoint,
    radius: CGFloat,
    lineWidth: CGFloat,
    color: CGColor
) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ctx.strokePath()
    ctx.restoreGState()
}

func drawLine(
    ctx: CGContext,
    from: CGPoint,
    to: CGPoint,
    lineWidth: CGFloat,
    color: CGColor
) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: from)
    ctx.addLine(to: to)
    ctx.strokePath()
    ctx.restoreGState()
}

func drawCubicCurve(
    ctx: CGContext,
    from: CGPoint,
    control1: CGPoint,
    control2: CGPoint,
    to: CGPoint,
    lineWidth: CGFloat,
    color: CGColor
) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: from)
    ctx.addCurve(to: to, control1: control1, control2: control2)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Branch-key mark
//
// Shared geometry description for the "branch-as-key" mark: a git branch
// graph whose trunk ends in key teeth. The same shape definition backs both
// the 1024px app icon and the small menu bar glyphs, each with its own
// coordinates tuned for legibility at that size.

struct BranchKeyGeometry {
    var topNode: CGPoint
    var branchNode: CGPoint
    var nodeRadius: CGFloat
    var trunkTop: CGPoint
    var trunkBottom: CGPoint
    var curveStart: CGPoint
    var curveControl1: CGPoint
    var curveControl2: CGPoint
    var curveEnd: CGPoint
    var teeth: [(y: CGFloat, x: CGFloat)]
    var trunkX: CGFloat
    var lineWidth: CGFloat
}

func drawBranchKey(ctx: CGContext, geometry g: BranchKeyGeometry, scale: CGFloat, color: CGColor) {
    func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x * scale, y: pt.y * scale) }
    let lw = g.lineWidth * scale

    drawStrokedCircle(ctx: ctx, center: p(g.topNode), radius: g.nodeRadius * scale, lineWidth: lw, color: color)
    drawStrokedCircle(ctx: ctx, center: p(g.branchNode), radius: g.nodeRadius * scale, lineWidth: lw, color: color)
    drawLine(ctx: ctx, from: p(g.trunkTop), to: p(g.trunkBottom), lineWidth: lw, color: color)
    drawCubicCurve(
        ctx: ctx,
        from: p(g.curveStart),
        control1: p(g.curveControl1),
        control2: p(g.curveControl2),
        to: p(g.curveEnd),
        lineWidth: lw,
        color: color
    )
    for tooth in g.teeth {
        drawLine(
            ctx: ctx,
            from: p(CGPoint(x: g.trunkX, y: tooth.y)),
            to: p(CGPoint(x: tooth.x, y: tooth.y)),
            lineWidth: lw,
            color: color
        )
    }
}

// MARK: - App icon (1024x1024)
//
// Geometry matches icons/c-branch-key.svg exactly.

let appIconGeometry = BranchKeyGeometry(
    topNode: CGPoint(x: 410, y: 240),
    branchNode: CGPoint(x: 690, y: 340),
    nodeRadius: 66,
    trunkTop: CGPoint(x: 410, y: 306),
    trunkBottom: CGPoint(x: 410, y: 830),
    curveStart: CGPoint(x: 410, y: 520),
    curveControl1: CGPoint(x: 410, y: 415),
    curveControl2: CGPoint(x: 510, y: 385),
    curveEnd: CGPoint(x: 624, y: 352),
    teeth: [
        (y: 590, x: 320),
        (y: 670, x: 344),
        (y: 750, x: 310),
        (y: 830, x: 350),
    ],
    trunkX: 410,
    lineWidth: 44
)

func renderAppIcon(path: String) {
    let size = 1024
    let ctx = makeContext(width: size, height: size)

    // Transparent background is the default (nothing painted yet).

    // Rounded-rect tile.
    let tileRect = CGRect(x: 64, y: 64, width: 896, height: 896)
    let tilePath = CGPath(roundedRect: tileRect, cornerWidth: 200, cornerHeight: 200, transform: nil)
    ctx.addPath(tilePath)
    ctx.setFillColor(CGColor(red: 0x14 / 255.0, green: 0x17 / 255.0, blue: 0x1d / 255.0, alpha: 1))
    ctx.fillPath()

    let orange = CGColor(red: 0xe8 / 255.0, green: 0x83 / 255.0, blue: 0x3a / 255.0, alpha: 1)
    drawBranchKey(ctx: ctx, geometry: appIconGeometry, scale: 1, color: orange)

    saveContext(ctx, to: path)
}

// MARK: - Menu bar glyph
//
// Geometry matches icons/menubar.svg, authored at 36x36 (== the @2x size).
// Four teeth (y=21,24.5,28,31.5) were tried first, matching the app icon's
// four-tooth trunk, and read fine at 36px -- but at the real 18px menu bar
// size the four teeth blurred into indistinct mush (see
// icon-redesign-report.md for the side-by-side comparison), so the glyph
// was dropped to three teeth, which stay legible at both sizes.

let menuGlyphGeometry = BranchKeyGeometry(
    topNode: CGPoint(x: 13, y: 7),
    branchNode: CGPoint(x: 26, y: 11),
    nodeRadius: 3.5,
    trunkTop: CGPoint(x: 13, y: 10.5),
    trunkBottom: CGPoint(x: 13, y: 32),
    curveStart: CGPoint(x: 13, y: 19),
    curveControl1: CGPoint(x: 13, y: 15),
    curveControl2: CGPoint(x: 18, y: 12.5),
    curveEnd: CGPoint(x: 22.5, y: 12),
    teeth: [
        (y: 22, x: 8.5),
        (y: 26, x: 10),
        (y: 30, x: 8),
    ],
    trunkX: 13,
    lineWidth: 3
)

/// Renders the menu bar branch-key glyph at the given pixel size using
/// geometry scaled from the 36x36 reference (menubar.svg is authored at
/// 36x36 == the @2x size). `scale` is size/36. `minStroke` guarantees the
/// stroke never thins below a legible device-pixel width at small sizes.
func renderMenuGlyph(path: String, size: Int, minStroke: CGFloat) {
    let ctx = makeContext(width: size, height: size)
    let scale = CGFloat(size) / 36.0

    let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    var geometry = menuGlyphGeometry
    let scaledStroke = geometry.lineWidth * scale
    if scaledStroke < minStroke {
        geometry.lineWidth = minStroke / scale
    }

    drawBranchKey(ctx: ctx, geometry: geometry, scale: scale, color: black)

    saveContext(ctx, to: path)
}

// MARK: - Main

let cwd = FileManager.default.currentDirectoryPath
renderAppIcon(path: cwd + "/app-1024.png")
renderMenuGlyph(path: cwd + "/MenuIconTemplate@2x.png", size: 36, minStroke: 3)
renderMenuGlyph(path: cwd + "/MenuIconTemplate.png", size: 18, minStroke: 2)

print("Rendered app-1024.png, MenuIconTemplate@2x.png, MenuIconTemplate.png")
