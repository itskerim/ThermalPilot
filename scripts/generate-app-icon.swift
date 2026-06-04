#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let outputURL = URL(fileURLWithPath: arguments.first ?? "build/AppIcon.iconset")
let sourceURL = URL(fileURLWithPath: arguments.dropFirst().first ?? "assets/AppIcon.png")
let sourceZoom: CGFloat = 1.18

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Could not read icon source at \(sourceURL.path)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for icon in sizes {
    let fileURL = outputURL.appendingPathComponent(icon.name)
    try writeResizedPNG(sourceImage, pixels: icon.pixels, to: fileURL)
}

func writeResizedPNG(_ image: NSImage, pixels: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
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

    let size = NSSize(width: pixels, height: pixels)
    bitmap.size = size

    NSGraphicsContext.saveGraphicsState()
    let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)
    graphicsContext?.imageInterpolation = .high
    NSGraphicsContext.current = graphicsContext
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    let drawSize = NSSize(width: CGFloat(pixels) * sourceZoom, height: CGFloat(pixels) * sourceZoom)
    let drawRect = NSRect(
        x: (CGFloat(pixels) - drawSize.width) / 2,
        y: (CGFloat(pixels) - drawSize.height) / 2,
        width: drawSize.width,
        height: drawSize.height
    )
    image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}
