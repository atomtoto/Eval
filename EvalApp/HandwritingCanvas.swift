import EvalCore
import PencilKit
import SwiftUI
import VisionKit

/// PencilKit's canvas, for formulas written with Apple Pencil or a finger, with the
/// system's tool picker. SwiftUI has no drawing canvas of its own.
struct HandwritingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    /// The tool picker shows while the canvas is on screen and active.
    var isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        // Black ink shows white in dark mode, and is rendered black for recognition.
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.accessibilityLabel = String(localized: "Zone d’écriture")
        canvas.accessibilityHint = String(localized: "Écrivez une formule par ligne, avec Apple Pencil ou le doigt.")
        context.coordinator.toolPicker.addObserver(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
        context.coordinator.toolPicker.setVisible(isActive, forFirstResponder: canvas)
        if isActive, !canvas.isFirstResponder {
            // The picker needs the canvas to be first responder once it is in a window.
            Task { @MainActor in canvas.becomeFirstResponder() }
        } else if !isActive, canvas.isFirstResponder {
            canvas.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker.removeObserver(canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker: PKToolPicker
        private let drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
            if #available(iOS 18, *) {
                // Formulas need a pen, an eraser and the lasso, not the whole set of tools.
                toolPicker = PKToolPicker(toolItems: [PKToolPickerInkingItem(type: .pen, color: .black, width: 4),
                                                      PKToolPickerEraserItem(type: .vector),
                                                      PKToolPickerLassoItem()])
            } else {
                toolPicker = PKToolPicker()
            }
        }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            if drawing.wrappedValue != canvas.drawing { drawing.wrappedValue = canvas.drawing }
        }
    }
}

extension PKDrawing {
    /// The drawing as black ink on white, as a recognizer reads best, with the
    /// strokes that look like fraction bars in the image's coordinates.
    func recognitionImage() -> (image: CGImage, bars: [RecognizedMath.Box])? {
        guard !strokes.isEmpty else { return nil }
        let area = bounds.insetBy(dx: -32, dy: -32)
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = image(from: area, scale: 2)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let page = UIGraphicsImageRenderer(size: area.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: area.size))
            ink.draw(at: .zero)
        }
        guard let image = page.cgImage else { return nil }
        // A long, flat stroke may be a fraction bar: text recognizers ignore lines.
        let bars = strokes.map(\.renderBounds).filter { $0.width > 40 && $0.width > 4 * $0.height }.map { rect in
            RecognizedMath.Box(x: (rect.minX - area.minX) / area.width, y: (rect.minY - area.minY) / area.height,
                               width: rect.width / area.width, height: rect.height / area.height)
        }
        return (image, bars)
    }
}

/// VisionKit's document camera, which finds the page, straightens it and lets
/// the person retake it. SwiftUI has no camera view of its own.
struct DocumentScanner: UIViewControllerRepresentable {
    /// The scanned pages, or none when the scan was cancelled or failed.
    let finish: ([CGImage]) -> Void

    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(finish: finish)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ camera: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let finish: ([CGImage]) -> Void

        init(finish: @escaping ([CGImage]) -> Void) {
            self.finish = finish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            finish((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).uprightImage() })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            finish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            finish([])
        }
    }
}

extension UIImage {
    /// The image drawn upright, at most `maximumSide` pixels on its longer side.
    func uprightImage(maximumSide: CGFloat = 2_400) -> CGImage? {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let ratio = min(1, maximumSide / max(pixels.width, pixels.height, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let target = CGSize(width: (pixels.width * ratio).rounded(), height: (pixels.height * ratio).rounded())
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}
