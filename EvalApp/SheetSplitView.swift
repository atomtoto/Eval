import SwiftUI

/// The Calcul tab: the sheet list beside the selected sheet. On iPhone, the
/// selected sheet opens directly, with a back button to the list.
struct SheetSplitView: View {
    @Environment(SheetLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Binding var selection: UUID?
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @Binding var column: NavigationSplitViewColumn
    /// Each change asks the search field of the list to take focus.
    var searchRequest = 0

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $column) {
            SheetListView(selection: $selection, searchRequest: searchRequest, open: open)
        } detail: {
            if let id = selection, let notebook = library.session(for: id) {
                NotebookView(notebook: notebook) { example in
                    open(library.createSheet(from: example))
                }
                .id(id)
            } else {
                ContentUnavailableView {
                    Label("Aucune feuille", systemImage: "doc.text")
                } description: {
                    Text("Créez une feuille ou choisissez-en une.")
                } actions: {
                    Button("Nouvelle feuille") { open(library.createSheet()) }
                }
            }
        }
        .onChange(of: selection) { previous, _ in
            // Another sheet takes over the window: the steps of the sheet left behind
            // are not undoable here. Showing another tab keeps them.
            if let previous { library.openSession(for: previous)?.removeUndoSteps(from: undoManager) }
        }
    }

    private func open(_ id: UUID) {
        selection = id
        column = .detail
    }
}
