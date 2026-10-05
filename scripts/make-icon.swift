#!/usr/bin/env swift
// Renders the app icon's layers into App/AppIcon.icon/Assets (an Icon Composer document).
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let canvas = 1024.0
let outputDirectory = URL(fileURLWithPath: "App/AppIcon.icon/Assets")
let white = NSColor.white
let turquoise = NSColor(srgbRed: 0x00 / 255, green: 0xAD / 255, blue: 0xD0 / 255, alpha: 1)  // the T line
let center = CGPoint(x: canvas / 2, y: canvas / 2 + 40)

func renderLayer(_ name: String, draw: (CGContext) -> Void) throws {
    let context = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Top-left origin, like the design canvas.
    context.translateBy(x: 0, y: canvas)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    draw(context)
    let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
}

// The thin white rule along the top of every NYC subway sign.
try renderLayer("rule") { context in
    context.setFillColor(white.cgColor)
    context.fill(CGRect(x: 0, y: 150, width: canvas, height: 22))
}

// A countdown ring: three quarters of the time left, running clockwise from 12 o'clock.
// (In this flipped context, increasing angles run clockwise on screen.)
try renderLayer("ring") { context in
    context.setStrokeColor(white.cgColor)
    context.setLineWidth(46)
    context.setLineCap(.round)
    let twelveOClock = -CGFloat.pi / 2
    context.addArc(center: center, radius: 318, startAngle: twelveOClock, endAngle: twelveOClock + 1.5 * .pi, clockwise: false)
    context.strokePath()
}

try renderLayer("bullet") { context in
    context.setFillColor(turquoise.cgColor)
    context.fillEllipse(in: CGRect(x: center.x - 236, y: center.y - 236, width: 472, height: 472))
}

try renderLayer("letter") { _ in
    let font = NSFont(name: "Helvetica-Bold", size: 360)!
    let text = NSAttributedString(string: "T", attributes: [.font: font, .foregroundColor: white])
    let bounds = text.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesFontLeading])
    // Center on the cap height rather than the line box so the letter sits optically centered.
    let origin = CGPoint(
        x: center.x - bounds.width / 2,
        y: center.y - font.capHeight / 2 - (font.ascender - font.capHeight)
    )
    text.draw(at: origin)
}

print("Wrote layers to \(outputDirectory.path)")
