import EvalCore
import PencilKit
import PhotosUI
import SwiftUI

/// Formulas written by hand, with Apple Pencil or a finger, or photographed on paper:
/// they are read on the device, shown for checking, then added to the sheet.
struct HandwritingView: View {
    /// The names the sheet declares, so that `0,5 m` written beside `m = 80 kg` multiplies.
    var declaredNames: [String] = []
    /// Adds the checked lines at the end of the sheet.
    let insert: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var drawing = PKDrawing()
    @State private var phase = Phase.writing
    @State private var lines: [ReadLine] = []
    @State private var engine: HandwritingRecognizer.Engine?
    @State private var showsScanner = false
    @State private var showsPhotoPicker = false
    @State private var photo: PhotosPickerItem?
    @State private var failure: String?
    @State private var reading: Task<Void, Never>?
    /// The reading the warning is shown for, then the one it allowed.
    @State private var warning: ReadingSource?
    @State private var confirmed: ReadingSource?
    @AppStorage(ReadingWarningSetting.storageKey) private var hidesReadingWarning = false

    private enum Phase {
        case writing, reading, checking
    }

    /// A line as read, which the person can correct before adding it.
    struct ReadLine: Identifiable {
        let id = UUID()
        var text: String
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .writing:
                    writing
                case .reading:
                    ProgressView("Lecture des formules…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .checking:
                    checking
                }
            }
            .navigationTitle(phase == .checking ? "Vérifier les lignes" : "Écrire à la main")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(!drawing.strokes.isEmpty || phase != .writing)
        // The camera and the picker open once the warning has gone.
        .sheet(item: $warning, onDismiss: {
            if let source = confirmed {
                confirmed = nil
                perform(source)
            }
        }) { source in
            ReadingWarningView(source: source, reason: HandwritingRecognizer.unavailabilityReason) {
                confirmed = source
            }
        }
        .fullScreenCover(isPresented: $showsScanner) {
            DocumentScanner { pages in
                showsScanner = false
                if !pages.isEmpty { read(pages, bars: []) }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            phase = .reading
            reading = Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)?.uprightImage() else {
                    show(failure: String(localized: "Cette photo ne peut pas être ouverte."))
                    return
                }
                read([image], bars: [])
            }
        }
        .alert("Lecture impossible", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .onDisappear { reading?.cancel() }
    }

    // MARK: Writing

    private var writing: some View {
        HandwritingCanvas(drawing: $drawing,
                          isActive: phase == .writing && !showsScanner && !showsPhotoPicker && warning == nil)
            .background(Color(.systemBackground))
            .overlay {
                if drawing.strokes.isEmpty {
                    ContentUnavailableView {
                        Label("Écrivez vos formules", systemImage: "pencil.and.scribble")
                    } description: {
                        Text("Une formule par ligne, avec Apple Pencil ou le doigt. Pour une page déjà écrite, utilisez Scanner ou Photos.")
                    }
                    .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: Checking

    private var checking: some View {
        List {
            Section {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Ligne", text: $line.text, axis: .vertical)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if MathNotation.formula(line.text) != nil {
                            FormulaView(source: line.text) { EmptyView() }
                                .accessibilityHidden(true)
                        } else if !line.text.trimmingCharacters(in: .whitespaces).isEmpty, !line.text.hasPrefix("#") {
                            Label("À corriger : Eval ne lit pas cette ligne.", systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { lines.remove(atOffsets: $0) }
            } footer: {
                Text(footer)
            }
        }
        .warmPage()
    }

    private var footer: LocalizedStringKey {
        switch engine {
        case .appleIntelligence:
            "Lu sur l’appareil par Apple Intelligence. Corrigez une ligne en la touchant ; glissez vers la gauche pour la supprimer."
        default:
            "Lu sur l’appareil par la reconnaissance de texte. Vérifiez les fractions et les exposants, corrigez une ligne en la touchant ; glissez vers la gauche pour la supprimer."
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch phase {
        case .writing:
            ToolbarItem(placement: .cancellationAction) {
                if #available(iOS 26, *) {
                    // The system's close button leaves room for the title.
                    Button(role: .close) { dismiss() }
                } else {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("Importer", systemImage: "camera") {
                    if DocumentScanner.isSupported {
                        Button("Scanner une page", systemImage: "doc.viewfinder") { start(.scan) }
                    }
                    // The picker is presented from the view: a picker inside a menu goes away with it.
                    Button("Choisir une photo", systemImage: "photo") { start(.photo) }
                }
                Button("Effacer", systemImage: "trash") { drawing = PKDrawing() }
                    .disabled(drawing.strokes.isEmpty)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lire") { start(.drawing) }
                    .disabled(drawing.strokes.isEmpty)
            }
        case .reading:
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", role: .cancel) {
                    reading?.cancel()
                    phase = .writing
                }
            }
        case .checking:
            ToolbarItem(placement: .cancellationAction) {
                Button("Retour") { phase = .writing }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Ajouter") {
                    insert(lines.map { RecognizedMath.normalized($0.text) })
                    dismiss()
                }
                .disabled(lines.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty })
            }
        }
    }

    // MARK: Reading

    /// Without Apple Intelligence, a reading first warns that it is less reliable,
    /// unless the person asked not to be warned again.
    private func start(_ source: ReadingSource) {
        if HandwritingRecognizer.engine == .textRecognition && !hidesReadingWarning {
            warning = source
        } else {
            perform(source)
        }
    }

    private func perform(_ source: ReadingSource) {
        switch source {
        case .scan: showsScanner = true
        case .photo: showsPhotoPicker = true
        case .drawing: readDrawing()
        }
    }

    private func readDrawing() {
        guard let page = drawing.recognitionImage() else { return }
        read([page.image], bars: page.bars)
    }

    /// Reads the pages in turn and shows their lines for checking.
    private func read(_ pages: [CGImage], bars: [RecognizedMath.Box]) {
        phase = .reading
        reading?.cancel()
        reading = Task {
            var found: [String] = []
            var usedEngine = HandwritingRecognizer.Engine.textRecognition
            do {
                for page in pages {
                    let recognition = try await HandwritingRecognizer.recognize(page, bars: bars)
                    found += recognition.lines
                    usedEngine = recognition.engine
                }
            } catch is CancellationError {
                return
            } catch {
                show(failure: error.localizedDescription)
                return
            }
            guard !Task.isCancelled else { return }
            lines = RecognizedMath.clarifyingProducts(found, declared: Set(declaredNames)).map { ReadLine(text: $0) }
            engine = usedEngine
            phase = .checking
        }
    }

    private func show(failure message: String) {
        failure = message
        phase = .writing
    }
}
