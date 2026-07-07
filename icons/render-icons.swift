// render-icons.swift
//
// Native CoreGraphics renderer for the app icon and menu bar template PNGs.
//
// Replaces the previous qlmanage-based SVG rasterization, which bakes an
// opaque white background into the PNG (qlmanage renders a QuickLook
// thumbnail against a white canvas). That produced a solid white/opaque
// menu bar icon and opaque white corners on the app icon, because macOS
// template image rendering and rounded-corner masking both depend on real
// alpha in the source PNG.
//
// This script hard-codes the geometry from icons/a-print-key.svg (app icon)
// and icons/menubar.svg (menu bar glyph) and draws directly with
// CoreGraphics into bitmap contexts that have a fully transparent backing,
// so every non-painted pixel has alpha == 0.
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

/// Draws a "fingerprint ridge" arc: a circle stroked over only part of its
/// circumference, similar to an SVG circle with stroke-dasharray covering a
/// single long dash. `coveragePercent` is the fraction of the circle drawn;
/// `startDegrees` is where the visible arc begins, measured clockwise from
/// the positive x-axis (matching SVG's rotate() + default 12-o'clock start
/// visual intent -- exact orientation was tuned by eye against the SVG).
func drawRidgeArc(
    ctx: CGContext,
    center: CGPoint,
    radius: CGFloat,
    lineWidth: CGFloat,
    startDegrees: CGFloat,
    coveragePercent: CGFloat,
    color: CGColor
) {
    let startRad = startDegrees * .pi / 180
    let sweepRad = 2 * .pi * (coveragePercent / 100)
    let endRad = startRad + sweepRad

    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.addArc(
        center: center,
        radius: radius,
        startAngle: startRad,
        endAngle: endRad,
        clockwise: false
    )
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

// MARK: - App icon (1024x1024)

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
    let bowCenter = CGPoint(x: 420, y: 420)

    // Fingerprint ridges (key bow), ~75% arcs with a gap, offset start angles.
    drawRidgeArc(ctx: ctx, center: bowCenter, radius: 60, lineWidth: 30, startDegrees: -30, coveragePercent: 75, color: orange)
    drawRidgeArc(ctx: ctx, center: bowCenter, radius: 120, lineWidth: 30, startDegrees: 80, coveragePercent: 75, color: orange)
    drawRidgeArc(ctx: ctx, center: bowCenter, radius: 180, lineWidth: 30, startDegrees: 200, coveragePercent: 75, color: orange)

    // Shaft, running to the lower-right of the bow.
    drawLine(ctx: ctx, from: CGPoint(x: 560, y: 560), to: CGPoint(x: 800, y: 800), lineWidth: 56, color: orange)

    // Teeth.
    drawLine(ctx: ctx, from: CGPoint(x: 716, y: 716), to: CGPoint(x: 660, y: 772), lineWidth: 44, color: orange)
    drawLine(ctx: ctx, from: CGPoint(x: 800, y: 800), to: CGPoint(x: 744, y: 856), lineWidth: 44, color: orange)

    saveContext(ctx, to: path)
}

// MARK: - Menu bar glyph

/// Renders the menu bar key/fingerprint glyph at the given pixel size using
/// geometry scaled from the 36x36 reference (menubar.svg is authored at
/// 36x36 == the @2x size). `scale` is size/36.
func renderMenuGlyph(path: String, size: Int, minStroke: CGFloat) {
    let ctx = makeContext(width: size, height: size)
    let scale = CGFloat(size) / 36.0

    let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    let center = CGPoint(x: 15 * scale, y: 15 * scale)
    let strokeWidth = max(3 * scale, minStroke)

    drawRidgeArc(ctx: ctx, center: center, radius: 4 * scale, lineWidth: strokeWidth, startDegrees: -30, coveragePercent: 85, color: black)
    drawRidgeArc(ctx: ctx, center: center, radius: 9.5 * scale, lineWidth: strokeWidth, startDegrees: 100, coveragePercent: 78, color: black)

    drawLine(ctx: ctx, from: CGPoint(x: 21 * scale, y: 21 * scale), to: CGPoint(x: 30 * scale, y: 30 * scale), lineWidth: strokeWidth, color: black)
    drawLine(ctx: ctx, from: CGPoint(x: 27.5 * scale, y: 27.5 * scale), to: CGPoint(x: 24.5 * scale, y: 30.5 * scale), lineWidth: strokeWidth, color: black)

    saveContext(ctx, to: path)
}

// MARK: - Main

let cwd = FileManager.default.currentDirectoryPath
renderAppIcon(path: cwd + "/app-1024.png")
renderMenuGlyph(path: cwd + "/MenuIconTemplate@2x.png", size: 36, minStroke: 3)
renderMenuGlyph(path: cwd + "/MenuIconTemplate.png", size: 18, minStroke: 2)

print("Rendered app-1024.png, MenuIconTemplate@2x.png, MenuIconTemplate.png")
