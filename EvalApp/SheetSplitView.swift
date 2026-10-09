import SwiftUI

/// The Calcul tab: the sheet list beside the selected sheet. On iPhone, the
/// selected sheet opens directly, with a back button to the list.
struct SheetSplitView: View {
    @Environment(SheetLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
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
                NotebookView(notebook: notebook, open: open)
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
            guard let previous else { return }
            library.openSession(for: previous)?.removeUndoSteps(from: undoManager)
            // Leaving a sheet, back to the list or for another one, may name it.
            library.suggestTitleIfNeeded(for: previous)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, let selection { library.suggestTitleIfNeeded(for: selection) }
        }
    }

    private func open(_ id: UUID) {
        selection = id
        column = .detail
    }
}
