import AppKit

// Render the same flat tile and optical size for every wallpaper in the family.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let svg = try String(contentsOf: input, encoding: .utf8)
    .replacingOccurrences(of: "currentColor", with: "#191919")
guard let glyph = NSImage(data: Data(svg.utf8)), glyph.isValid,
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not render the application icon.")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
NSColor(srgbRed: 244 / 255, green: 244 / 255, blue: 244 / 255, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
context.imageInterpolation = .high
glyph.draw(in: NSRect(x: 192, y: 192, width: 640, height: 640), from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed.") }
try png.write(to: output, options: .atomic)
