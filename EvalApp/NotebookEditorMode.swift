import Foundation

/// How a sheet is edited. A preference shared by every sheet and window.
/// The raw values are stored in eval.notebook.editorMode.v1 and must not change;
/// `title` is the text shown.
enum NotebookEditorMode: String, CaseIterable, Identifiable {
    case formulas = "Formules"
    case text = "Texte"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .formulas: "Formules"
        case .text: "Texte"
        }
    }
}
