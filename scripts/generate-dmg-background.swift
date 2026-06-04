#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let outputPath = arguments.first ?? "build/dmg-background.png"
let sourcePath = arguments.dropFirst().first ?? "assets/dmg-background-source.png"
let outputURL = URL(fileURLWithPath: outputPath)
let sourceURL = URL(fileURLWithPath: sourcePath)
guard let sourceBackground = NSImage(contentsOf: sourceURL) else {
    fputs("Could not read DMG background source at \(sourceURL.path)\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

// The design is laid out in point space matching the DMG Finder window content.
// writePNG emits it at 2x for retina crispness (1000x680 pt -> 2000x1360 px).
let pointSize = CGSize(width: 1000, height: 680)
let renderScale: CGFloat = 2
try writePNG(drawBackground(pointSize: pointSize, source: sourceBackground), scale: renderScale, to: outputURL)

func drawBackground(pointSize: CGSize, source: NSImage) -> NSImage {
    let image = NSImage(size: pointSize)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let viewportRect = CGRect(origin: .zero, size: pointSize)
    drawImageCover(source, in: viewportRect)
    context.setFillColor(NSColor.black.withAlphaComponent(0.13).cgColor)
    context.fill(viewportRect)

    let panel = NSBezierPath(roundedRect: CGRect(x: 80, y: 105, width: 840, height: 420), xRadius: 38, yRadius: 38)
    context.setFillColor(NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 0.22).cgColor)
    context.addPath(panel.cgPath)
    context.fillPath()
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.09).cgColor)
    context.setLineWidth(0.9)
    context.addPath(panel.cgPath)
    context.strokePath()

    context.saveGState()
    context.setBlendMode(.multiply)
    drawSoftEllipse(
        context,
        center: CGPoint(x: 320, y: 304),
        size: CGSize(width: 220, height: 32),
        color: NSColor.black.withAlphaComponent(0.34)
    )
    context.restoreGState()

    context.saveGState()
    context.setBlendMode(.plusLighter)
    drawRadialGlow(
        context,
        center: CGPoint(x: 320, y: 340),
        radius: 170,
        color: NSColor(red: 1.0, green: 0.58, blue: 0.36, alpha: 0.05)
    )
    context.restoreGState()

    drawFinderLabelHaze(context, center: CGPoint(x: 320, y: 226), width: 170)
    drawFinderLabelHaze(context, center: CGPoint(x: 720, y: 226), width: 158)
    drawArrow(context, appRightEdge: 416, applicationsLeftEdge: 624, centerY: 345)

    return image
}

func drawImageCover(_ image: NSImage, in rect: CGRect) {
    let sourceSize = image.size
    let scale = max(rect.width / sourceSize.width, rect.height / sourceSize.height)
    let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    let drawRect = CGRect(
        x: rect.midX - drawSize.width / 2,
        y: rect.midY - drawSize.height / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1)
}

func drawArrow(_ context: CGContext, appRightEdge: CGFloat, applicationsLeftEdge: CGFloat, centerY: CGFloat) {
    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setBlendMode(.plusLighter)

    let leftMargin = appRightEdge + 24
    let rightMargin = applicationsLeftEdge - 24
    let centerX = (leftMargin + rightMargin) / 2
    drawRadialGlow(context, center: CGPoint(x: centerX - 44, y: centerY), radius: 40, color: NSColor(red: 0.95, green: 0.40, blue: 0.30, alpha: 0.045))
    drawRadialGlow(context, center: CGPoint(x: centerX + 18, y: centerY), radius: 48, color: NSColor(red: 0.42, green: 0.48, blue: 0.76, alpha: 0.04))

    let dotCenters = [leftMargin + 4, leftMargin + 26, leftMargin + 50]
    let dotAlphas: [CGFloat] = [0.16, 0.28, 0.68]
    let dotRadii: [CGFloat] = [2.8, 3.6, 5.0]
    for index in dotCenters.indices {
        let color = NSColor(red: 0.95, green: 0.33, blue: 0.25, alpha: dotAlphas[index])
        drawGlowDot(context, center: CGPoint(x: dotCenters[index], y: centerY), color: color, radius: dotRadii[index])
    }

    drawChevron(context, center: CGPoint(x: centerX - 14, y: centerY), color: NSColor(red: 1.0, green: 0.48, blue: 0.38, alpha: 1))
    drawChevron(context, center: CGPoint(x: centerX + 16, y: centerY), color: NSColor(red: 0.74, green: 0.56, blue: 0.95, alpha: 1))
    drawChevron(context, center: CGPoint(x: centerX + 46, y: centerY), color: NSColor(red: 0.34, green: 0.72, blue: 0.90, alpha: 1))

    context.restoreGState()
}

func drawFinderLabelHaze(_ context: CGContext, center: CGPoint, width: CGFloat) {
    context.saveGState()
    context.setBlendMode(.normal)
    drawSoftEllipse(
        context,
        center: center,
        size: CGSize(width: width * 1.45, height: 64),
        color: NSColor.white.withAlphaComponent(0.16)
    )
    drawRadialGlow(
        context,
        center: center,
        radius: width * 1.1,
        color: NSColor.white.withAlphaComponent(0.05)
    )
    context.restoreGState()
}

func drawGlowDot(_ context: CGContext, center: CGPoint, color: NSColor, radius: CGFloat) {
    drawRadialGlow(context, center: center, radius: radius * 5.2, color: color.withAlphaComponent(color.alphaComponent * 0.28))
    drawRadialGlow(context, center: center, radius: radius * 2.4, color: color.withAlphaComponent(color.alphaComponent * 0.58))
    context.setFillColor(color.withAlphaComponent(min(color.alphaComponent + 0.12, 0.82)).cgColor)
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

func drawChevron(_ context: CGContext, center: CGPoint, color: NSColor) {
    let size: CGFloat = 12.5
    let points = [
        CGPoint(x: center.x - size * 0.50, y: center.y + size),
        CGPoint(x: center.x + size * 0.50, y: center.y),
        CGPoint(x: center.x - size * 0.50, y: center.y - size)
    ]

    context.setLineJoin(.round)
    context.setLineCap(.round)
    drawChevronStroke(context, points: points, color: color.withAlphaComponent(0.055), lineWidth: 18)
    drawChevronStroke(context, points: points, color: color.withAlphaComponent(0.12), lineWidth: 11)
    drawChevronStroke(context, points: points, color: color.withAlphaComponent(0.26), lineWidth: 7)
    drawChevronStroke(context, points: points, color: color.withAlphaComponent(0.70), lineWidth: 4.6)
    drawChevronStroke(context, points: points, color: NSColor.white.withAlphaComponent(0.56), lineWidth: 2.0)
    drawChevronStroke(context, points: points, color: color.withAlphaComponent(0.82), lineWidth: 3.2)
}

func drawChevronStroke(_ context: CGContext, points: [CGPoint], color: NSColor, lineWidth: CGFloat) {
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(lineWidth)
    context.move(to: points[0])
    context.addLine(to: points[1])
    context.addLine(to: points[2])
    context.strokePath()
}

func drawRadialGlow(_ context: CGContext, center: CGPoint, radius: CGFloat, color: NSColor) {
    let transparent = color.withAlphaComponent(0).cgColor
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.cgColor, transparent] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func drawSoftEllipse(_ context: CGContext, center: CGPoint, size: CGSize, color: NSColor) {
    let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    let transparent = color.withAlphaComponent(0).cgColor
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color.cgColor, transparent] as CFArray,
        locations: [0, 1]
    )!

    context.saveGState()
    context.translateBy(x: rect.midX, y: rect.midY)
    context.scaleBy(x: rect.width / rect.height, y: 1)
    context.drawRadialGradient(
        gradient,
        startCenter: .zero,
        startRadius: 0,
        endCenter: .zero,
        endRadius: rect.height / 2,
        options: []
    )
    context.restoreGState()
}

func writePNG(_ image: NSImage, scale: CGFloat, to url: URL) throws {
    // Pixel buffer is `scale`x the point size; bitmap.size stays in points so the
    // PNG is tagged as a 2x/retina image and Finder maps it back to point size.
    let pixelsWide = Int(image.size.width * scale)
    let pixelsHigh = Int(image.size.height * scale)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelsWide,
        pixelsHigh: pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = image.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: CGRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()

    guard
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}
