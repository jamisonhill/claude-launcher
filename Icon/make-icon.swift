#!/usr/bin/env swift
//
// Generates AppIcon.icns from code, so the icon is reviewable and editable in
// version control rather than an opaque binary someone has to open Photoshop for.
//
//   swift Icon/make-icon.swift
//
// Design notes:
// - A terminal prompt chevron with a cursor block. It reads as "a terminal, about
//   to run something", which is what the app does.
// - Deliberately NOT modelled on Anthropic's own mark. This is an unofficial,
//   publicly distributed third-party app, and borrowing their logo or brand
//   colour would imply an endorsement that doesn't exist.
// - The glyph is heavy and high-contrast because the icon has to stay legible at
//   16pt in the Finder sidebar, which is where most icons fall apart.

import AppKit
import Foundation

// Each size is drawn natively rather than downscaled from one big bitmap.
// Shrinking 1024px artwork to 16px turns the chevron into a grey smudge; Apple
// ships distinct artwork per size for exactly this reason.
//
// Design notes:
// - A terminal prompt chevron with a cursor block: "a terminal, about to run
//   something", which is what the app does.
// - Deliberately NOT modelled on Anthropic's own mark. This is an unofficial,
//   publicly distributed third-party app, and borrowing their logo or brand
//   colour would imply an endorsement that doesn't exist.

let amber = NSColor(srgbRed: 0.949, green: 0.651, blue: 0.353, alpha: 1)

/// Proportions that change with size. Small icons need a bigger, heavier glyph
/// and less surrounding air, or they read as a featureless dark blob.
struct Metrics {
    let insetRatio: CGFloat      // plate inset, as a fraction of the canvas
    let strokeRatio: CGFloat     // chevron weight, as a fraction of plate width
    let armRatio: CGFloat        // chevron half-height, fraction of plate width
    let drawsSheen: Bool

    static func forPixels(_ px: Int) -> Metrics {
        if px <= 32 {
            // Tiny: nearly fill the tile, fatten the strokes, drop the sheen
            // (invisible at this size, and it only muddies the contrast).
            return Metrics(insetRatio: 0.045, strokeRatio: 0.105,
                           armRatio: 0.175, drawsSheen: false)
        }
        if px <= 64 {
            return Metrics(insetRatio: 0.070, strokeRatio: 0.085,
                           armRatio: 0.160, drawsSheen: false)
        }
        return Metrics(insetRatio: 0.098, strokeRatio: 0.062,
                       armRatio: 0.150, drawsSheen: true)
    }
}

func drawIcon(canvas: CGFloat, metrics: Metrics) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let inset = canvas * metrics.insetRatio
    let plate = NSRect(x: inset, y: inset,
                       width: canvas - inset * 2, height: canvas - inset * 2)
    // Apple's squircle corner radius is ~22.37% of the plate's width.
    let radius = plate.width * 0.2237

    ctx.saveGState()
    let platePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    platePath.addClip()

    // Dark slate gradient, lighter at the top so the plate reads as lit from above.
    NSGradient(colors: [
        NSColor(srgbRed: 0.204, green: 0.227, blue: 0.278, alpha: 1),
        NSColor(srgbRed: 0.078, green: 0.090, blue: 0.118, alpha: 1)
    ])?.draw(in: plate, angle: -90)

    if metrics.drawsSheen {
        // Standard macOS material cue; keeps a flat dark plate from looking
        // like a sticker.
        NSGradient(colors: [NSColor(white: 1, alpha: 0.14),
                            NSColor(white: 1, alpha: 0.0)])?
            .draw(in: NSRect(x: plate.minX, y: plate.midY,
                             width: plate.width, height: plate.height / 2), angle: -90)
    }
    ctx.restoreGState()

    let arm = plate.width * metrics.armRatio
    let stroke = plate.width * metrics.strokeRatio
    let cursorWidth = plate.width * 0.21
    let cursorHeight = stroke * 1.5
    let gap = plate.width * 0.075

    // Centre the chevron+cursor group as a unit, rather than centring the
    // chevron and letting the cursor pull the composition off-balance.
    let groupWidth = arm * 1.5 + gap + cursorWidth
    let groupLeft = plate.midX - groupWidth / 2
    let cx = groupLeft + arm * 0.75
    let cy = plate.midY

    amber.setStroke()
    let chevron = NSBezierPath()
    chevron.lineWidth = stroke
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.move(to: NSPoint(x: cx - arm * 0.72, y: cy + arm))
    chevron.line(to: NSPoint(x: cx + arm * 0.72, y: cy))
    chevron.line(to: NSPoint(x: cx - arm * 0.72, y: cy - arm))
    chevron.stroke()

    // Solid block rather than an underscore: a thin rule vanishes at 16pt.
    let cursor = NSBezierPath(roundedRect: NSRect(
        x: groupLeft + arm * 1.5 + gap,
        y: cy - arm,
        width: cursorWidth,
        height: cursorHeight), xRadius: cursorHeight * 0.32, yRadius: cursorHeight * 0.32)
    amber.withAlphaComponent(0.94).setFill()
    cursor.fill()
}

/// Renders the icon natively at an exact pixel size.
func png(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(canvas: CGFloat(pixels), metrics: .forPixels(pixels))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// iconutil expects this exact set of names.
let variants: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),      ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),      ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),   ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),   ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),   ("icon_512x512@2x.png", 1024)
]

let iconsetURL = URL(fileURLWithPath: "Icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for variant in variants {
    guard let data = png(pixels: variant.px) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: iconsetURL.appendingPathComponent(variant.name))
}
print("wrote \(variants.count) sizes to Icon/AppIcon.iconset")
