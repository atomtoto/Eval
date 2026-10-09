// Regenerate the Icon Composer document EvalApp/AppIcon.icon: swift Scripts/generate-app-icon.swift
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

let guide = svg("""
<line x1="\(center)" y1="652" x2="\(center)" y2="\(marker.y + 92)" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="14" stroke-linecap="round" stroke-dasharray="6 38"/>
""")

let lens = svg("""
<circle cx="\(marker.x)" cy="\(marker.y)" r="72" fill="#FFFFFF"/>
""")

let manifest = """
{
  "fill" : {
    "linear-gradient" : [
      "extended-srgb:0.20000,0.58000,1.00000,1.00000",
      "extended-srgb:0.00000,0.40000,0.92000,1.00000"
    ]
  },
  "groups" : [
    {
      "layers" : [
        {
          "glass" : true,
          "image-name" : "Point.svg",
          "name" : "Point"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.4
      }
    },
    {
      "layers" : [
        {
          "glass" : false,
          "image-name" : "Guide.svg",
          "name" : "Guide"
        },
        {
          "glass" : false,
          "image-name" : "Curve.svg",
          "name" : "Curve"
        },
        {
          "glass" : false,
          "image-name" : "Ruler.svg",
          "name" : "Ruler"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.3
      },
      "translucency" : {
        "enabled" : false,
        "value" : 0.5
      }
    }
  ],
  "supported-platforms" : {
    "squares" : "shared"
  }
}

"""

let document = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("EvalApp/AppIcon.icon")
let assets = document.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try manifest.write(to: document.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
for (name, contents) in [("Curve", curve), ("Ruler", ruler), ("Guide", guide), ("Point", lens)] {
    try contents.write(to: assets.appendingPathComponent(name + ".svg"), atomically: true, encoding: .utf8)
}
