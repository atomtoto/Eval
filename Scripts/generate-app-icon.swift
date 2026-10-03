// Regenerate the app icon with the system SF Symbol: swift Scripts/generate-app-icon.swift
import AppKit

let side = 1024
let bitmapContext = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
let configuration = NSImage.SymbolConfiguration(pointSize: 520, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "function", accessibilityDescription: nil)!
    .withSymbolConfiguration(configuration)!
let size = symbol.size
symbol.draw(in: NSRect(x: (CGFloat(side) - size.width) / 2,
                      y: (CGFloat(side) - size.height) / 2,
                      width: size.width, height: size.height))
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("EvalApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let bitmap = NSBitmapImageRep(cgImage: bitmapContext.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
