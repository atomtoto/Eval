import EvalCore
import SwiftUI

/// Chooses which lines show their value in Résultats.
struct ResultSelectionView: View {
    let notebook: NotebookStore
    /// Nil where the sheet’s changes are not undoable.
    var undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if notebook.selectableLines.isEmpty {
                    ContentUnavailableView("Aucune formule à choisir", systemImage: "function",
                                           description: Text("Ajoutez une formule ou une variable dans la feuille."))
                } else {
                    Section {
                        ForEach(notebook.selectableLines) { item in
                            Toggle(isOn: Binding(
                                get: { item.entry.isSelected },
                                set: { notebook.setResultDisplayed($0, lineID: item.id, undoManager: undoManager) }
                            )) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Ligne \(item.index + 1)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    FormulaView(source: item.entry.source)
                                }
                            }
                        }
                    } footer: {
                        Text("Votre choix est enregistré avec la feuille. Une ligne masquée reste disponible pour les autres formules.")
                    }
                }
            }
            .navigationTitle("Choisir les résultats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Sélection", systemImage: "checklist") {
                        Button("Tout afficher") { notebook.selectAllResults(true, undoManager: undoManager) }
                        Button("Tout masquer") { notebook.selectAllResults(false, undoManager: undoManager) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
