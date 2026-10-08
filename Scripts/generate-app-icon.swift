// Regenerate the app icons (light, dark, tinted): swift Scripts/generate-app-icon.swift
// The artwork is drawn from plain paths: a parabola (E = ½mv²) above the graduated
// ruler of the variable sliders, joined by a guide at the fixed indicator. It uses no SF Symbol.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let rgb = CGColorSpaceCreateDeviceRGB()

struct Palette {
    let top: CGColor
    let bottom: CGColor
    let ink: CGColor
    let accent: CGColor
}

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [red, green, blue, alpha])!
}

let variants: [(file: String, palette: Palette)] = [
    ("AppIcon.png", Palette(top: color(0.20, 0.58, 1), bottom: color(0, 0.40, 0.92),
                            ink: color(1, 1, 1), accent: color(1, 1, 1))),
    ("AppIcon-Dark.png", Palette(top: color(0.07, 0.11, 0.20), bottom: color(0.02, 0.04, 0.09),
                                 ink: color(0.62, 0.78, 1), accent: color(1, 1, 1))),
    ("AppIcon-Tinted.png", Palette(top: color(0.16, 0.16, 0.16), bottom: color(0.02, 0.02, 0.02),
                                   ink: color(0.85, 0.85, 0.85), accent: color(1, 1, 1)))
]

// Quadratic Bézier of the parabola, in a 1024 × 1024 space with the origin at the bottom left.
let start = CGPoint(x: 190, y: 400), control = CGPoint(x: 590, y: 400), end = CGPoint(x: 850, y: 850)

func point(at t: Double) -> CGPoint {
    let u = 1 - t
    return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                   y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
}

/// The curve point whose x is the center of the ruler, found by bisection.
func parameter(forX x: Double) -> Double {
    var low = 0.0, high = 1.0
    for _ in 0..<60 {
        let middle = (low + high) / 2
        if point(at: middle).x < x { low = middle } else { high = middle }
    }
    return (low + high) / 2
}

func render(_ palette: Palette) -> CGImage {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let gradient = CGGradient(colorsSpace: rgb, colors: [palette.top, palette.bottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(side)), end: .zero, options: [])
    context.setLineCap(.round)
    context.setLineJoin(.round)

    // The parabola.
    context.setStrokeColor(palette.ink)
    context.setLineWidth(46)
    context.move(to: start)
    context.addQuadCurve(to: end, control: control)
    context.strokePath()

    // The ruler: fixed indicator at the center, graduations fading away from it.
    let center = Double(side) / 2
    for index in -6...6 {
        let x = center + Double(index) * 62
        let fade = 1 - abs(Double(index)) / 7
        context.setStrokeColor(palette.ink.copy(alpha: 0.25 + 0.6 * fade)!)
        context.setLineWidth(26)
        context.move(to: CGPoint(x: x, y: 150))
        context.addLine(to: CGPoint(x: x, y: index == 0 ? 330 : 270))
        context.strokePath()
    }

    // The guide from the indicator up to the point on the curve, then the point.
    let marker = point(at: parameter(forX: center))
    context.setStrokeColor(palette.accent)
    context.setLineWidth(26)
    context.move(to: CGPoint(x: center, y: 150))
    context.addLine(to: CGPoint(x: center, y: 330))
    context.strokePath()
    context.setStrokeColor(palette.accent.copy(alpha: 0.5)!)
    context.setLineWidth(14)
    context.setLineDash(phase: 0, lengths: [6, 38])
    context.move(to: CGPoint(x: center, y: 372))
    context.addLine(to: CGPoint(x: center, y: marker.y - 70))
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])
    context.setFillColor(palette.accent)
    context.fillEllipse(in: CGRect(x: marker.x - 64, y: marker.y - 64, width: 128, height: 128))
    context.setFillColor(palette.bottom)
    context.fillEllipse(in: CGRect(x: marker.x - 26, y: marker.y - 26, width: 52, height: 52))
    return context.makeImage()!
}

let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("EvalApp/Assets.xcassets/AppIcon.appiconset")
for variant in variants {
    let url = directory.appendingPathComponent(variant.file) as CFURL
    let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, render(variant.palette), nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(variant.file)") }
}
