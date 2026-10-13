import AVKit
import EvalCore
import PhotosUI
import SwiftUI

/// Formulas photographed on paper, as in Photomath: the camera fills the screen, a
/// centered frame, resized around its center by its corners and edges, chooses what is
/// read, and the lines read go straight to the sheet, at its end or below the line
/// being edited. A photo from the library is framed the same way. The controls are
/// Liquid Glass from iOS 26.
@available(iOS 18, *)
struct FormulaScannerView: View {
    /// Where the lines read go in the sheet.
    enum Destination {
        case endOfSheet, belowLine
    }

    /// The names the sheet declares, so that `0,5 m` beside `m = 80 kg` multiplies.
    var declaredNames: [String] = []
    var destination = Destination.endOfSheet
    /// Adds the lines read to the sheet, where `destination` says.
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
    /// The zoom while a pinch changes it, shown above the frame.
    @State private var shownZoom: CGFloat?
    /// The picture taken, held in the frame while it is read.
    @State private var frozen: UIImage?
    /// The size of the camera's frame, as a share of the room it has, from one scan to the next.
    @AppStorage("eval.scanner.frameWidth.v1") private var savedWidth = 0.0
    @AppStorage("eval.scanner.frameHeight.v1") private var savedHeight = 0.0

    private var usesCamera: Bool { photo == nil }

    /// A photo or the camera's picture, under the frame.
    private var hasPicture: Bool {
        photo != nil || camera.state == .running
    }

    private var canRead: Bool {
        !isReading && hasPicture
    }

    /// Over a photo, the button of the photo library brings the camera back.
    private var returnsToCamera: Bool {
        photo != nil && camera.state == .running
    }

    private var showsTorch: Bool {
        usesCamera && camera.hasTorch && camera.state == .running
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
                viewfinder(limits: limits)
                    .ignoresSafeArea()
                controls
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear { frame = cameraFrame(in: limits) }
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

    // MARK: Viewfinder

    /// The camera or the photo, the frame over it, the picture being read and the zoom.
    private func viewfinder(limits: CGRect) -> some View {
        ZStack {
            background
            if let frozen {
                frozenPicture(frozen)
            }
            if hasPicture {
                ReadingFrame(rect: $frame, limits: photo == nil ? limits : photoRect) {
                    frameAdjusted(limits: limits)
                }
                .allowsHitTesting(!isReading)
            }
            if let shownZoom {
                zoomLabel(shownZoom, limits: limits)
            }
        }
    }

    /// As in Photomath, the frame holds the picture taken while it is read.
    private func frozenPicture(_ picture: UIImage) -> some View {
        Image(uiImage: picture)
            .resizable()
            .scaledToFill()
            .frame(width: frame.width, height: frame.height)
            .clipShape(.rect(cornerRadius: 14))
            .position(x: frame.midX, y: frame.midY)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// The zoom while a pinch changes it, above the frame, as in the Camera app.
    private func zoomLabel(_ zoom: CGFloat, limits: CGRect) -> some View {
        Text("\(Double(zoom).formatted(.number.precision(.fractionLength(1))))×")
            .font(.footnote.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .scannerBubble()
            .position(x: frame.midX, y: max(frame.minY - 22, limits.minY - 22))
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// The camera focuses on the frame, whose size is kept for the next scan.
    private func frameAdjusted(limits: CGRect) {
        guard usesCamera, limits.width > 0, limits.height > 0 else { return }
        camera.focus(onLayerRect: frame)
        savedWidth = frame.width / limits.width
        savedHeight = frame.height / limits.height
    }

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
                            shownZoom = camera.zoomFactor
                        }
                        .onEnded { _ in
                            zoomAtStart = nil
                            withAnimation(.easeOut(duration: 0.3).delay(0.6)) { shownZoom = nil }
                        })
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

    /// In one glass container, so that the glass of the controls is drawn together,
    /// and the lamp appears as glass does.
    private var controls: some View {
        ScannerGlassContainer {
            VStack(spacing: 0) {
                HStack {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                        .modifier(ScannerControl())
                    Spacer()
                }
                Spacer()
                // Glass ignores opacity: what is hidden is left out.
                if hasPicture {
                    hint
                        .padding(.bottom, 20)
                }
                // The side columns share the width, so that the shutter stays centered.
                HStack(spacing: 0) {
                    Button(returnsToCamera ? "Revenir à la caméra" : "Choisir une photo",
                           systemImage: returnsToCamera ? "camera" : "photo.on.rectangle") {
                        if returnsToCamera { photo = nil } else { showsPhotoPicker = true }
                    }
                    .contentTransition(.symbolEffect(.replace))
                    .modifier(ScannerControl())
                    .disabled(isReading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    shutter
                    ZStack {
                        if showsTorch {
                            Button(camera.isTorchOn ? "Éteindre la lampe" : "Allumer la lampe",
                                   systemImage: camera.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill") {
                                camera.toggleTorch()
                            }
                            .contentTransition(.symbolEffect(.replace))
                            .modifier(ScannerControl())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .animation(.default, value: returnsToCamera)
                .animation(.default, value: showsTorch)
                .animation(.default, value: camera.isTorchOn)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
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
        .scannerBubble()
        .accessibilityElement(children: .combine)
    }

    /// The shutter of the Camera app, in the color of the app, in a ring of glass from iOS 26.
    private var shutter: some View {
        Button(action: read) {
            // Glass ignores opacity: only the disc fades while the shutter is unavailable.
            Circle()
                .fill(.tint.opacity(canRead || isReading ? 1 : 0.4))
                .frame(width: 66, height: 66)
                .padding(6)
                .shutterRing()
        }
        .buttonStyle(.plain)
        .disabled(!canRead)
        .accessibilityLabel(usesCamera ? "Prendre la photo" : "Lire la formule")
        .accessibilityHint(destination == .belowLine ? "Les lignes lues sont ajoutées sous la ligne en cours."
                           : "Les lignes lues sont ajoutées à la fin de la feuille.")
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
                // As in Photomath, the frame holds the picture while it is read.
                if shownPhoto == nil { withAnimation(.easeOut(duration: 0.15)) { frozen = UIImage(cgImage: image) } }
                let recognition = try await FormulaRecognizer.recognize(image)
                let declared = Set(declaredNames)
                let lines = RecognizedMath.harmonizingCase(recognition.lines, declared: declared)
                insert(RecognizedMath.clarifyingProducts(lines, declared: declared))
                dismiss()
            } catch is CancellationError {
                isReading = false
                frozen = nil
            } catch {
                failure = error.localizedDescription
                isReading = false
                withAnimation { frozen = nil }
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
            frame = cameraFrame(in: limits)
        }
    }

    /// The frame centered in its room: as large as last time, else wide, as for a line of formula.
    private func cameraFrame(in limits: CGRect) -> CGRect {
        let minimum = ReadingFrame.minimumSize
        var size = CGSize(width: min(limits.width, 560), height: 0)
        size.height = min(limits.height, max(140, size.width * 0.45))
        if savedWidth > 0, savedHeight > 0 {
            size = CGSize(width: min(max(savedWidth * limits.width, minimum.width), limits.width),
                          height: min(max(savedHeight * limits.height, minimum.height), limits.height))
        }
        return ReadingFrame.centered(size, in: limits)
    }
}

/// The glass of the controls, drawn together from iOS 26.
private struct ScannerGlassContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

private extension View {
    /// A label over the camera: Liquid Glass from iOS 26, a system material before.
    @ViewBuilder
    func scannerBubble() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.regularMaterial, in: .capsule)
        }
    }

    /// The ring of the shutter: Liquid Glass from iOS 26, which answers the touch; white before, as in Camera.
    @ViewBuilder
    func shutterRing() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            overlay { Circle().strokeBorder(.white, lineWidth: 4) }
        }
    }
}

/// The round glass buttons over the camera.
private struct ScannerControl: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .labelStyle(.iconOnly)
                .font(.title3)
                // White, as over the Camera app's viewfinder, whatever the accent.
                .foregroundStyle(.white)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            content
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.white)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(.white)
        }
    }
}

/// The reading frame, always centered in its room: its corners, drawn as in the Camera
/// app, and its edges are dragged to resize it around its center, so the cross in the
/// middle never moves. From iOS 26 the corners are Liquid Glass that answers the finger,
/// as the thumb of a slider does. The outside is dimmed. VoiceOver adjusts its size with
/// a swipe up or down.
private struct ReadingFrame: View {
    @Binding var rect: CGRect
    /// Where the frame may go; it stays centered in it.
    let limits: CGRect
    /// Called when a corner or an edge is let go.
    let adjusted: () -> Void
    @State private var startSize: CGSize?
    @State private var isAtLimit = false
    @State private var grabs = 0

    static let minimumSize = CGSize(width: 100, height: 60)
    /// The side of the square where a corner is grabbed and drawn.
    private static let cornerGrip: CGFloat = 64

    /// A frame of this size, centered in the limits.
    static func centered(_ size: CGSize, in limits: CGRect) -> CGRect {
        CGRect(x: limits.midX - size.width / 2, y: limits.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// The four corners change both sides, the four edges one: always on both sides at once.
    private enum Handle: CaseIterable, Identifiable {
        case top, bottom, leading, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing

        var id: Self { self }
        var isCorner: Bool { signs.x != 0 && signs.y != 0 }
        /// −1 for the leading or top side, +1 for the trailing or bottom side, 0 for a side it keeps.
        var signs: (x: CGFloat, y: CGFloat) {
            switch self {
            case .top: (0, -1)
            case .bottom: (0, 1)
            case .leading: (-1, 0)
            case .trailing: (1, 0)
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
            // A shadow keeps the white cross visible over white paper.
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.45), radius: 2)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
            // The edges first, so that the corners win where they overlap.
            ForEach(Handle.allCases) { handle in
                grip(handle)
                    .frame(width: area(of: handle).width, height: area(of: handle).height)
                    .contentShape(.rect)
                    .position(point(of: handle))
                    .gesture(drag(handle))
            }
        }
        .sensoryFeedback(.selection, trigger: grabs)
        .sensoryFeedback(trigger: isAtLimit) { _, reached in reached ? .impact(weight: .light) : nil }
        .accessibilityElement()
        .accessibilityLabel("Cadre de lecture")
        .accessibilityHint("Seul ce qui est dans le cadre est lu. Balayez vers le haut ou le bas pour l’agrandir ou le réduire.")
        .accessibilityAdjustableAction { direction in
            let factor: CGFloat = direction == .increment ? 1.15 : 1 / 1.15
            rect = Self.centered(clamped(CGSize(width: rect.width * factor, height: rect.height * factor)), in: limits)
            adjusted()
        }
    }

    private func point(of handle: Handle) -> CGPoint {
        let (sx, sy) = handle.signs
        return CGPoint(x: rect.midX + sx * rect.width / 2, y: rect.midY + sy * rect.height / 2)
    }

    /// Where a handle can be grabbed: a square at a corner, the rest of the side for an edge.
    private func area(of handle: Handle) -> CGSize {
        let grip = Self.cornerGrip
        if handle.isCorner { return CGSize(width: grip, height: grip) }
        return handle.signs.x == 0 ? CGSize(width: max(44, rect.width - 2 * grip), height: 44)
            : CGSize(width: 44, height: max(44, rect.height - 2 * grip))
    }

    /// What a handle shows: nothing for an edge; for a corner, glass from iOS 26, else
    /// white with a shadow that keeps it visible over white paper, thicker while dragged.
    @ViewBuilder
    private func grip(_ handle: Handle) -> some View {
        if handle.isCorner {
            let length = min(Self.cornerGrip / 2 - 4, rect.width / 3, rect.height / 3)
            if #available(iOS 26, *) {
                Color.clear
                    .glassEffect(.regular.interactive(), in: FrameCorner(signs: handle.signs, length: length, lineWidth: 6))
            } else {
                FrameCorner(signs: handle.signs, length: length, lineWidth: startSize == nil ? 4 : 5)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3)
            }
        } else {
            Color.clear
        }
    }

    private func clamped(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, min(Self.minimumSize.width, limits.width)), limits.width),
               height: min(max(size.height, min(Self.minimumSize.height, limits.height)), limits.height))
    }

    /// The dragged side follows the finger, and the opposite side mirrors it.
    private func drag(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if startSize == nil {
                    startSize = rect.size
                    grabs += 1
                }
                let start = startSize ?? rect.size
                let (sx, sy) = handle.signs
                let wanted = CGSize(width: start.width + 2 * sx * value.translation.width,
                                    height: start.height + 2 * sy * value.translation.height)
                let size = clamped(wanted)
                isAtLimit = (sx != 0 && size.width != wanted.width) || (sy != 0 && size.height != wanted.height)
                rect = Self.centered(size, in: limits)
            }
            .onEnded { _ in
                startSize = nil
                isAtLimit = false
                adjusted()
            }
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

/// A rounded corner of a viewfinder, as a filled outline: from the corner, at the
/// middle of its rect, toward the inside of the frame, which the signs point away from.
private struct FrameCorner: Shape {
    /// −1 for a leading or top corner, +1 for a trailing or bottom one.
    let signs: (x: CGFloat, y: CGFloat)
    let length: CGFloat
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let corner = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: corner.x, y: corner.y - signs.y * length))
        path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x - signs.x * length, y: corner.y),
                    radius: min(14, length / 2))
        path.addLine(to: CGPoint(x: corner.x - signs.x * length, y: corner.y))
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}
