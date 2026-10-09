import SwiftUI

/// Whether the warning before a reading without Apple Intelligence is still shown.
enum ReadingWarningSetting {
    static let storageKey = "eval.readingWarning.hidden.v1"
}

/// What the person is about to read: a page from the camera, a photo or the drawing.
enum ReadingSource: Identifiable {
    case scan, photo, drawing

    var id: Self { self }

    var confirmation: LocalizedStringKey {
        switch self {
        case .scan: "Scanner la page"
        case .photo: "Choisir une photo"
        case .drawing: "Lire le dessin"
        }
    }
}

/// A warning shown before a reading on a device without Apple Intelligence: the text
/// recognizer reads characters well, but not the layout of fractions and exponents.
struct ReadingWarningView: View {
    let source: ReadingSource
    /// Why Apple Intelligence is not available here.
    let reason: LocalizedStringResource?
    let proceed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ReadingWarningSetting.storageKey) private var hidesWarning = false

    /// The height the warning needs, so that the sheet fits it exactly.
    @State private var height: CGFloat?

    var body: some View {
        // Scrolls only when the text is too large for the screen.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .presentationDetents(height.map { [.height($0)] } ?? [.medium])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 40))
                .accessibilityHidden(true)
            Text("Lecture moins fiable")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Sans Apple Intelligence, Eval lit les caractères un par un : les chiffres et les lettres sont bien reconnus, mais les fractions, les exposants et les racines le sont souvent mal. Vérifiez chaque ligne avant de l’ajouter.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let reason {
                Label {
                    Text(reason)
                } icon: {
                    Image(systemName: "sparkles")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary, in: .rect(cornerRadius: 12))
            }
            Toggle("Ne plus afficher", isOn: $hidesWarning)
                .padding(.vertical, 4)
            VStack(spacing: 8) {
                Button {
                    proceed()
                    dismiss()
                } label: {
                    Text(source.confirmation)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Annuler", role: .cancel) { dismiss() }
                    .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height + $0.safeAreaInsets.bottom } action: { height = $0 }
    }
}
