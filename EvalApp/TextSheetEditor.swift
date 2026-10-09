import EvalCore
import SwiftUI

/// « Modifier en texte »: the whole sheet in one multiline field. Terminé applies
/// the text as one undo step; Annuler leaves the sheet as it was.
struct TextSheetEditor: View {
    let notebook: NotebookStore
    var undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var selection = FormulaSelectionState()
    @State private var showsReferences = false
    @FocusState private var isFocused: Bool

    init(notebook: NotebookStore, undoManager: UndoManager?) {
        self.notebook = notebook
        self.undoManager = undoManager
        _draft = State(initialValue: notebook.source)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // A vertical field grows with its text instead of scrolling inside a fixed box.
                    FormulaTextField(title: "Une formule par ligne", text: $draft, selection: selection, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(8...)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isFocused)
                        .accessibilityLabel("Feuille de formules")
                } footer: {
                    Text("Une ligne par formule ou variable. Terminez une ligne par = pour afficher sa valeur. Les unités suivent les valeurs, séparées par un espace.")
                }
            }
            .warmPage()
            .navigationTitle("Modifier en texte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé", action: apply)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                FormulaKeyboardToolbar(insertsSymbols: FormulaSelectionState.tracksCaret,
                                       variableNames: notebook.declaredNames, insert: insert,
                                       showReferences: { isFocused = false; showsReferences = true },
                                       done: { isFocused = false })
            }
            .sheet(isPresented: $showsReferences) {
                ReferencePickerView(insert: insert)
            }
        }
        .interactiveDismissDisabled(draft != notebook.source)
    }

    private func insert(_ snippet: FormulaInsertion.Snippet) {
        selection.insert(snippet, into: &draft)
    }

    private func apply() {
        notebook.recording("Modifier en texte", undoManager: undoManager) {
            notebook.source = draft
        }
        dismiss()
    }
}
