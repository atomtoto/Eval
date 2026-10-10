import AVFoundation
import SwiftUI
import UIKit

/// The back camera of the formula scanner: a photo session, its preview, the torch
/// and the zoom. SwiftUI has no camera view, so the preview is AVFoundation's layer.
@MainActor @Observable
final class ScannerCamera {
    enum State {
        case starting, running
        /// No camera here, as in the simulator.
        case unavailable
        /// The person refused access to the camera.
        case denied
    }

    private(set) var state = State.starting
    private(set) var isTorchOn = false
    private(set) var hasTorch = false

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var rotation: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    /// The delegate of the photo being taken, which the output holds only weakly.
    @ObservationIgnored private var pendingCapture: PhotoCapture?

    /// Asks for the camera if needed, then starts the session. Without a camera, nothing is asked.
    func start() async {
        guard state == .starting else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            state = .unavailable
            return
        }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            state = .denied
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            state = .unavailable
            return
        }
        session.beginConfiguration()
        // The photo preset shows the same field as the photo, so the frame crops exactly.
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            state = .unavailable
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        self.device = device
        hasTorch = device.hasTorch
        configureFocus(at: CGPoint(x: 0.5, y: 0.5))
        coordinateRotation()
        // Starting blocks for a moment: away from the main thread.
        let running = SessionHandle(session)
        await Task.detached { running.session.startRunning() }.value
        state = .running
    }

    func stop() {
        if isTorchOn { toggleTorch() }
        let running = SessionHandle(session)
        Task.detached { running.session.stopRunning() }
    }

    /// The preview layer shows the session, upright whatever the orientation.
    func attach(_ layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        coordinateRotation()
    }

    private func coordinateRotation() {
        guard rotation == nil, let device, let previewLayer else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotation = coordinator
        previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak self] _, change in
            guard let angle = change.newValue else { return }
            Task { @MainActor in self?.previewLayer?.connection?.videoRotationAngle = angle }
        }
    }

    // MARK: Torch, zoom and focus

    func toggleTorch() {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = isTorchOn ? .off : .on
        device.unlockForConfiguration()
        isTorchOn = device.torchMode == .on
    }

    var zoomFactor: CGFloat { device?.videoZoomFactor ?? 1 }

    /// Zooms up to six times, within what the camera allows.
    func zoom(to factor: CGFloat) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        let upper = min(device.maxAvailableVideoZoomFactor, 6)
        device.videoZoomFactor = min(max(factor, device.minAvailableVideoZoomFactor), upper)
        device.unlockForConfiguration()
    }

    /// Focuses on the middle of the frame, a rectangle in the preview layer.
    func focus(onLayerRect rect: CGRect) {
        guard let previewLayer else { return }
        configureFocus(at: previewLayer.captureDevicePointConverted(fromLayerPoint: CGPoint(x: rect.midX, y: rect.midY)))
    }

    private func configureFocus(at point: CGPoint) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
    }

    // MARK: Photo

    enum CaptureError: LocalizedError {
        case failed

        var errorDescription: String? { String(localized: "La photo n’a pas pu être prise.") }
    }

    /// Takes a photo and keeps what lies in `rect`, a rectangle of the preview layer,
    /// upright and at most 2 400 pixels on its longer side.
    func capture(layerRect rect: CGRect) async throws -> CGImage {
        guard let previewLayer, state == .running else { throw CaptureError.failed }
        // The sensor's coordinates, normalized: they match the photo's pixels as long as
        // the photo is not rotated, which the capture then does itself.
        let area = previewLayer.metadataOutputRectConverted(fromLayerRect: rect)
        let angle = rotation?.videoRotationAngleForHorizonLevelCapture ?? 90
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        let data = try await withCheckedThrowingContinuation { continuation in
            let capture = PhotoCapture(continuation: continuation)
            pendingCapture = capture
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: capture)
        }
        pendingCapture = nil
        guard let photo = UIImage(data: data)?.cgImage else { throw CaptureError.failed }
        let width = CGFloat(photo.width), height = CGFloat(photo.height)
        let crop = CGRect(x: area.minX * width, y: area.minY * height, width: area.width * width,
                          height: area.height * height).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !crop.isEmpty, let cropped = photo.cropping(to: crop),
              let upright = UIImage(cgImage: cropped, scale: 1, orientation: Self.orientation(forRotation: angle)).uprightImage()
        else { throw CaptureError.failed }
        return upright
    }

    /// The orientation that turns the sensor's picture by `angle` degrees clockwise.
    private static func orientation(forRotation angle: CGFloat) -> UIImage.Orientation {
        switch Int((angle.truncatingRemainder(dividingBy: 360) + 360).rounded()) % 360 {
        case 90: .right
        case 180: .down
        case 270: .left
        default: .up
        }
    }
}

/// The session, handed to the queue that starts and stops it; nothing else uses it there.
private struct SessionHandle: @unchecked Sendable {
    let session: AVCaptureSession

    init(_ session: AVCaptureSession) {
        self.session = session
    }
}

/// Receives one photo and resumes its caller with the photo's data.
private final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Data, Error>?

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: ScannerCamera.CaptureError.failed)
        }
        continuation = nil
    }
}

/// AVFoundation's preview of the camera, which fills its view.
struct CameraPreview: UIViewRepresentable {
    let camera: ScannerCamera

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        camera.attach(view.previewLayer)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // The layer class above makes the layer a preview layer.
            unsafeDowncast(layer, to: AVCaptureVideoPreviewLayer.self)
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
