import AVKit
import EvalCore
import PhotosUI
import SwiftUI

/// Formulas photographed on paper, as in Photomath: the camera fills the screen, a
/// frame resized by its corners chooses what is read, and the lines read go straight
/// to the end of the sheet. A photo from the library is framed the same way.
@available(iOS 18, *)
struct FormulaScannerView: View {
    /// The names the sheet declares, so that `0,5 m` beside `m = 80 kg` multiplies.
    var declaredNames: [String] = []
    /// Adds the lines read at the end of the sheet.
    let insert: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var camera = ScannerCamera()
    /// The reading frame, in the coordinates of the whole screen.
    @State private var frame = CGRect.zero
    /// A photo from the library, framed instead of the camera's picture, and where it is shown.
    @State private var photo: UIImage?
    @State private var photoRect = CGRect.zero
    @State private var pickedItem: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var isReading = false
    @State private var failure: String?
    @State private var shots = 0
    @State private var zoomAtStart: CGFloat?

    private var usesCamera: Bool { photo == nil }

    private var canRead: Bool {
        !isReading && (photo != nil || camera.state == .running)
    }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screen = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                                height: proxy.size.height + insets.top + insets.bottom)
            // The frame stays between the close button and the controls at the bottom.
            let top = insets.top + 76
            let limits = CGRect(x: insets.leading + 20, y: top,
                                width: max(160, screen.width - insets.leading - insets.trailing - 40),
                                height: max(140, screen.height - top - insets.bottom - 210))
            ZStack {
                ZStack {
                    background
                    if photo != nil || camera.state == .running {
                        ReadingFrame(rect: $frame, limits: photo == nil ? limits : photoRect) {
                            if usesCamera { camera.focus(onLayerRect: frame) }
                        }
                    }
                }
                .ignoresSafeArea()
                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { frame = Self.cameraFrame(in: limits) }
            .onChange(of: screen) { resetFrame(limits: limits) }
            .onChange(of: photo) { resetFrame(limits: limits) }
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onCameraCaptureEvent { event in
            // The volume buttons and the Camera Control take the photo, as in Camera.
            if event.phase == .ended, usesCamera { read() }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let upright = UIImage(data: data)?.uprightImage() else {
                    failure = String(localized: "Cette photo ne peut pas être ouverte.")
                    return
                }
                photo = UIImage(cgImage: upright)
            }
        }
        .alert("Lecture impossible", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: shots)
    }

    // MARK: Background

    @ViewBuilder
    private var background: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .frame(width: photoRect.width, height: photoRect.height)
                .position(x: photoRect.midX, y: photoRect.midY)
                .accessibilityLabel("Photo choisie")
        } else {
            switch camera.state {
            case .starting, .running:
                CameraPreview(camera: camera)
                    .gesture(MagnifyGesture()
                        .onChanged { value in
                            let start = zoomAtStart ?? camera.zoomFactor
                            zoomAtStart = start
                            camera.zoom(to: start * value.magnification)
                        }
                        .onEnded { _ in zoomAtStart = nil })
                    .accessibilityHidden(true)
            case .unavailable:
                ContentUnavailableView {
                    Label("Caméra indisponible", systemImage: "camera")
                } description: {
                    Text("Choisissez une photo de la formule dans votre photothèque.")
                }
            case .denied:
                ContentUnavailableView {
                    Label("Accès à la caméra refusé", systemImage: "camera")
                } description: {
                    Text("Autorisez la caméra dans Réglages pour photographier une formule, ou choisissez une photo.")
                } actions: {
                    Button("Ouvrir Réglages") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Button(usesCamera ? "Fermer" : "Revenir à la caméra", systemImage: "xmark") {
                    if photo != nil && camera.state == .running { photo = nil } else { dismiss() }
                }
                .modifier(ScannerControl())
                Spacer()
            }
            Spacer()
            hint
                .padding(.bottom, 20)
            HStack {
                Button("Choisir une photo", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
                    .modifier(ScannerControl())
                    .disabled(isReading)
                Spacer()
                shutter
                Spacer()
                Button(camera.isTorchOn ? "Éteindre la lampe" : "Allumer la lampe",
                       systemImage: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill") {
                    camera.toggleTorch()
                }
                .modifier(ScannerControl())
                .opacity(usesCamera && camera.hasTorch && camera.state == .running ? 1 : 0)
                .disabled(!(usesCamera && camera.hasTorch && camera.state == .running))
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var hint: some View {
        HStack(spacing: 8) {
            if isReading { ProgressView() }
            Text(isReading ? "Lecture des formules…"
                 : usesCamera ? "Cadrez la formule, puis prenez la photo" : "Ajustez le cadre sur la formule")
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .accessibilityElement(children: .combine)
        .opacity(photo != nil || camera.state == .running ? 1 : 0)
    }

    /// The shutter of the Camera app, in the color of the app.
    private var shutter: some View {
        Button(action: read) {
            Circle()
                .fill(.tint)
                .frame(width: 66, height: 66)
                .padding(6)
                .overlay { Circle().strokeBorder(.white, lineWidth: 4) }
        }
        .buttonStyle(.plain)
        .disabled(!canRead)
        .opacity(canRead || isReading ? 1 : 0.4)
        .accessibilityLabel(usesCamera ? "Prendre la photo" : "Lire la formule")
        .accessibilityHint("Les lignes lues sont ajoutées à la fin de la feuille.")
    }

    // MARK: Reading

    /// Reads what the frame holds and adds it to the sheet, which then shows.
    private func read() {
        guard canRead else { return }
        isReading = true
        shots += 1
        let (area, shownPhoto, shownIn) = (frame, photo, photoRect)
        Task {
            do {
                let image = if let shownPhoto {
                    try Self.crop(shownPhoto, to: area, shownIn: shownIn)
                } else {
                    try await camera.capture(layerRect: area)
                }
                let recognition = try await FormulaRecognizer.recognize(image)
                insert(RecognizedMath.clarifyingProducts(recognition.lines, declared: Set(declaredNames)))
                dismiss()
            } catch is CancellationError {
                isReading = false
            } catch {
                failure = error.localizedDescription
                isReading = false
            }
        }
    }

    /// The part of an upright photo under the frame, the photo being shown in `shown`.
    private static func crop(_ photo: UIImage, to area: CGRect, shownIn shown: CGRect) throws -> CGImage {
        guard let image = photo.cgImage, shown.width > 0, shown.height > 0 else { throw ScannerCamera.CaptureError.failed }
        let scale = CGSize(width: CGFloat(image.width) / shown.width, height: CGFloat(image.height) / shown.height)
        let part = area.intersection(shown).offsetBy(dx: -shown.minX, dy: -shown.minY)
        let pixels = CGRect(x: part.minX * scale.width, y: part.minY * scale.height,
                            width: part.width * scale.width, height: part.height * scale.height).integral
        guard !pixels.isEmpty, let cropped = image.cropping(to: pixels) else { throw ScannerCamera.CaptureError.failed }
        return cropped
    }

    // MARK: Frame

    private func resetFrame(limits: CGRect) {
        if let photo {
            // The photo fits between the controls, and the frame starts around most of it.
            let size = photo.size
            let ratio = min(limits.width / size.width, limits.height / size.height)
            let shown = CGSize(width: size.width * ratio, height: size.height * ratio)
            photoRect = CGRect(x: limits.midX - shown.width / 2, y: limits.midY - shown.height / 2,
                               width: shown.width, height: shown.height)
            frame = photoRect.insetBy(dx: shown.width * 0.05, dy: shown.height * 0.05)
        } else {
            frame = Self.cameraFrame(in: limits)
        }
    }

    /// A wide frame a little above the middle, as for a line of formula.
    private static func cameraFrame(in limits: CGRect) -> CGRect {
        let width = min(limits.width, 560)
        let height = min(limits.height, max(140, width * 0.45))
        return CGRect(x: limits.midX - width / 2, y: limits.minY + (limits.height - height) * 0.4,
                      width: width, height: height)
    }
}

/// The round glass buttons over the camera.
private struct ScannerControl: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            content
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(.white)
        }
    }
}

/// The reading frame: its corners, drawn as in the Camera app, are dragged to resize
/// it; the outside is dimmed. VoiceOver adjusts its size with a swipe up or down.
private struct ReadingFrame: View {
    @Binding var rect: CGRect
    /// Where the frame may go.
    let limits: CGRect
    /// Called when a corner is let go.
    let adjusted: () -> Void
    @State private var startRect: CGRect?

    private static let minimumSize = CGSize(width: 100, height: 60)

    private enum Corner: CaseIterable, Identifiable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var id: Self { self }
        /// −1 for the leading or top side, +1 for the trailing or bottom side.
        var signs: (x: CGFloat, y: CGFloat) {
            switch self {
            case .topLeading: (-1, -1)
            case .topTrailing: (1, -1)
            case .bottomLeading: (-1, 1)
            case .bottomTrailing: (1, 1)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DimmedOutside(hole: rect)
                .fill(.black.opacity(0.35), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            FrameCorners()
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(.white)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
            ForEach(Corner.allCases) { corner in
                Color.clear
                    .frame(width: 56, height: 56)
                    .contentShape(.rect)
                    .position(point(of: corner, in: rect))
                    .gesture(drag(corner))
            }
        }
        .coordinateSpace(.named("scanner"))
        .accessibilityElement()
        .accessibilityLabel("Cadre de lecture")
        .accessibilityHint("Seul ce qui est dans le cadre est lu. Balayez vers le haut ou le bas pour l’agrandir ou le réduire.")
        .accessibilityAdjustableAction { direction in
            let factor: CGFloat = direction == .increment ? 1.15 : 1 / 1.15
            resize(by: factor)
        }
    }

    private func point(of corner: Corner, in rect: CGRect) -> CGPoint {
        CGPoint(x: corner.signs.x < 0 ? rect.minX : rect.maxX, y: corner.signs.y < 0 ? rect.minY : rect.maxY)
    }

    /// The dragged corner follows the finger; the opposite one stays put.
    private func drag(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("scanner"))
            .onChanged { value in
                let start = startRect ?? rect
                startRect = start
                let (sx, sy) = corner.signs
                let fixed = CGPoint(x: sx < 0 ? start.maxX : start.minX, y: sy < 0 ? start.maxY : start.minY)
                let origin = point(of: corner, in: start)
                var x = min(max(origin.x + value.translation.width, limits.minX), limits.maxX)
                var y = min(max(origin.y + value.translation.height, limits.minY), limits.maxY)
                x = sx < 0 ? min(x, fixed.x - Self.minimumSize.width) : max(x, fixed.x + Self.minimumSize.width)
                y = sy < 0 ? min(y, fixed.y - Self.minimumSize.height) : max(y, fixed.y + Self.minimumSize.height)
                rect = CGRect(x: min(fixed.x, x), y: min(fixed.y, y), width: abs(x - fixed.x), height: abs(y - fixed.y))
            }
            .onEnded { _ in
                startRect = nil
                adjusted()
            }
    }

    private func resize(by factor: CGFloat) {
        let width = min(max(rect.width * factor, Self.minimumSize.width), limits.width)
        let height = min(max(rect.height * factor, Self.minimumSize.height), limits.height)
        let x = min(max(rect.midX - width / 2, limits.minX), limits.maxX - width)
        let y = min(max(rect.midY - height / 2, limits.minY), limits.maxY - height)
        rect = CGRect(x: x, y: y, width: width, height: height)
        adjusted()
    }
}

/// Everything but the frame, to be filled with the even-odd rule.
private struct DimmedOutside: Shape {
    var hole: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14))
        return path
    }
}

/// The four rounded corners of a viewfinder.
private struct FrameCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(30, rect.width / 3, rect.height / 3)
        let radius = min(14, length / 2)
        var path = Path()
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: rect.minX, y: rect.minY + length), CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX + length, y: rect.minY)),
            (CGPoint(x: rect.maxX - length, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + length)),
            (CGPoint(x: rect.maxX, y: rect.maxY - length), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX - length, y: rect.maxY)),
            (CGPoint(x: rect.minX + length, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY - length)),
        ]
        for (start, corner, end) in corners {
            path.move(to: start)
            path.addArc(tangent1End: corner, tangent2End: end, radius: radius)
            path.addLine(to: end)
        }
        return path
    }
}
