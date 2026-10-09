// Regenerate the Icon Composer documents EvalApp/AppIcon.icon (the default: lens, orange),
// AppIconPoint.icon (point, orange), AppIconBlue.icon (lens, blue) and AppIconPointBlue.icon
// (point, blue), and their previews for Réglages: swift Scripts/generate-app-icon.swift
// The icon follows the accent color of the app, orange or blue.
// The artwork is drawn from plain paths: a parabola (E = ½mv²) above the graduated
// ruler of the variable sliders, joined by a guide at the fixed indicator. It uses no
// SF Symbol. The point on the curve is a Liquid Glass layer; the system derives the
// dark, tinted and clear appearances, and Xcode the flattened icons for earlier iOS.
import Foundation

let side = 1024.0

// SVG coordinates: origin at the top left, y downwards.
let start = (x: 190.0, y: 624.0), control = (x: 590.0, y: 624.0), end = (x: 850.0, y: 174.0)

func point(at t: Double) -> (x: Double, y: Double) {
    let u = 1 - t
    return (u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            u * u * start.y + 2 * u * t * control.y + t * t * end.y)
}

/// The curve point above the ruler's fixed indicator, found by bisection on x.
func point(atX x: Double) -> (x: Double, y: Double) {
    var low = 0.0, high = 1.0
    for _ in 0..<60 {
        let middle = (low + high) / 2
        if point(at: middle).x < x { low = middle } else { high = middle }
    }
    return point(at: (low + high) / 2)
}

func svg(_ body: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(side))" height="\(Int(side))" viewBox="0 0 \(Int(side)) \(Int(side))">\(body)</svg>

    """
}

let center = side / 2
let marker = point(atX: center)

let curve = svg("""
<path d="M\(start.x),\(start.y) Q\(control.x),\(control.y) \(end.x),\(end.y)" fill="none" stroke="#FFFFFF" stroke-width="46" stroke-linecap="round"/>
""")

let ticks = (-6...6).map { index -> String in
    let x = center + Double(index) * 62
    let opacity = index == 0 ? 1 : 0.25 + 0.6 * (1 - Double(abs(index)) / 7)
    let top = index == 0 ? 694.0 : 754.0
    let alpha = String(format: "%.3f", opacity)
    return "<line x1=\"\(x)\" y1=\"874\" x2=\"\(x)\" y2=\"\(top)\" stroke=\"#FFFFFF\" stroke-opacity=\"\(alpha)\" stroke-width=\"26\" stroke-linecap=\"round\"/>"
}.joined()
let ruler = svg(ticks)

/// The dashed guide from the indicator up to just below the point.
func guide(clearance: Double) -> String {
    svg("""
    <line x1="\(center)" y1="652" x2="\(center)" y2="\(marker.y + clearance)" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="14" stroke-linecap="round" stroke-dasharray="6 38"/>
    """)
}

func disk(radius: Double, color: String = "#FFFFFF") -> String {
    svg("""
    <circle cx="\(marker.x)" cy="\(marker.y)" r="\(radius)" fill="\(color)"/>
    """)
}

/// The colors of an icon: a background gradient from top to bottom, and the dot under the lens.
struct Palette {
    let top: String
    let bottom: String
    let dot: String

    /// A safety orange, in the family of the app's accent color (#DD5500).
    static let orange = Palette(top: "extended-srgb:1.00000,0.46000,0.05000,1.00000",
                                bottom: "extended-srgb:0.87000,0.27000,0.00000,1.00000",
                                dot: "#8C2400")
    /// The system blue.
    static let blue = Palette(top: "extended-srgb:0.20000,0.58000,1.00000,1.00000",
                              bottom: "extended-srgb:0.00000,0.40000,0.92000,1.00000",
                              dot: "#002E8A")
}

struct Layer {
    let name: String
    let glass: Bool
    let svg: String
    /// A fill that replaces the drawing's own color, such as a faint white for a clear lens.
    var fill: String? = nil
}

/// One Icon Composer document: the point layers above the curve, the guide and the ruler.
struct IconDocument {
    let name: String
    let palette: Palette
    let pointLayers: [Layer]
    /// Drawn under the glass, above the curve.
    var underLayers: [Layer] = []
    let guide: String

    var drawingLayers: [Layer] {
        underLayers + [Layer(name: "Guide", glass: false, svg: guide),
         Layer(name: "Curve", glass: false, svg: curve),
         Layer(name: "Ruler", glass: false, svg: ruler)]
    }

    func group(_ layers: [Layer], shadow: Double, translucent: Bool) -> String {
        let entries = layers.map { layer in
            let fill = layer.fill.map { """
                      "fill-specializations" : [ { "value" : { "solid" : "\($0)" } } ],
            """ } ?? ""
            return """
                    {
            \(fill)
                      "glass" : \(layer.glass),
                      "image-name" : "\(layer.name).svg",
                      "name" : "\(layer.name)"
                    }
            """
        }.joined(separator: ",\n")
        return """
            {
              "layers" : [
        \(entries)
              ],
              "shadow" : {
                "kind" : "neutral",
                "opacity" : \(shadow)
              },
              "translucency" : {
                "enabled" : \(translucent),
                "value" : 0.4
              }
            }
        """
    }

    var manifest: String {
        """
        {
          "fill" : {
            "linear-gradient" : [
              "\(palette.top)",
              "\(palette.bottom)"
            ]
          },
          "groups" : [
        \(group(pointLayers, shadow: 0.5, translucent: true)),
        \(group(drawingLayers, shadow: 0.3, translucent: false))
          ],
          "supported-platforms" : {
            "squares" : "shared"
          }
        }

        """
    }

    func write(to folder: URL) throws {
        let document = folder.appendingPathComponent(name + ".icon")
        let assets = document.appendingPathComponent("Assets")
        try? FileManager.default.removeItem(at: document)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try manifest.write(to: document.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
        for layer in pointLayers + drawingLayers {
            try layer.svg.write(to: assets.appendingPathComponent(layer.name + ".svg"), atomically: true, encoding: .utf8)
        }
    }
}

/// The point icon: one glass point on the curve.
func pointIcon(_ name: String, _ palette: Palette) -> IconDocument {
    IconDocument(name: name, palette: palette,
                 pointLayers: [Layer(name: "Point", glass: true, svg: disk(radius: 72))],
                 guide: guide(clearance: 92))
}

/// The lens icon: a larger point in two parts, a tinted dot seen through a glass lens.
func lensIcon(_ name: String, _ palette: Palette) -> IconDocument {
    IconDocument(name: name, palette: palette,
                 pointLayers: [Layer(name: "Lens", glass: true, svg: disk(radius: 104),
                                     fill: "extended-srgb:1.00000,1.00000,1.00000,0.18000")],
                 underLayers: [Layer(name: "Dot", glass: false, svg: disk(radius: 40, color: palette.dot))],
                 guide: guide(clearance: 124))
}

// AppIcon is the primary icon, in the default orange; the others are alternates.
let documents = [
    lensIcon("AppIcon", .orange),
    pointIcon("AppIconPoint", .orange),
    lensIcon("AppIconBlue", .blue),
    pointIcon("AppIconPointBlue", .blue)
]

let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("EvalApp")
for document in documents {
    try document.write(to: folder)
}

// Previews for the icon picker in Réglages, rendered by Icon Composer's tool.
let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
for document in documents {
    let set = folder.appendingPathComponent("Assets.xcassets/\(document.name)Preview.imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ictool)
    process.arguments = [folder.appendingPathComponent(document.name + ".icon").path, "--export-image",
                         "--output-file", set.appendingPathComponent("\(document.name)Preview.png").path,
                         "--platform", "iOS", "--rendition", "Default",
                         "--width", "120", "--height", "120", "--scale", "3"]
    try process.run()
    process.waitUntilExit()
    let contents = """
    {
      "images" : [
        { "filename" : "\(document.name)Preview.png", "idiom" : "universal" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
    try contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
