import EvalCore
import SwiftUI

/// The sheets of this device, most recently modified first.
struct SheetListView: View {
    @Environment(SheetLibrary.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager
    @Binding var selection: UUID?
    var searchRequest = 0
    let open: (UUID) -> Void
    @State private var search = ""
    @State private var renaming: SheetRecord?
    @State private var deletedSheet: SheetRecord?
    @State private var undoTimeout: Task<Void, Never>?
    @State private var showsSettings = false

    private var visibleSheets: [SheetRecord] {
        guard !search.isEmpty else { return library.sheets }
        return library.sheets.filter {
            $0.displayTitle.localizedStandardContains(search) || $0.source.localizedStandardContains(search)
        }
    }

    var body: some View {
        let sheets = visibleSheets
        List(selection: $selection) {
            ForEach(sheets) { record in
                SheetRow(record: record)
                    .contextMenu { actions(for: record) }
            }
            .onDelete { offsets in
                if let record = offsets.first.map({ sheets[$0] }) { delete(record) }
            }
        }
        .overlay {
            if library.sheets.isEmpty {
                ContentUnavailableView {
                    Label("Aucune feuille", systemImage: "doc.text")
                } description: {
                    Text("Créez une feuille pour commencer un calcul.")
                } actions: {
                    Button("Nouvelle feuille") { open(library.createSheet()) }
                }
            } else if sheets.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("Feuilles")
        .sidebarTitleFitsToolbar(horizontalSizeClass)
        .searchable(text: $search, prompt: "Rechercher dans les feuilles")
        .focusesSearch(on: searchRequest)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
                    .tint(.primary)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Réglages", systemImage: "gear") { showsSettings = true }
                    .tint(.primary)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ExampleMenuContent { example in
                        open(library.createSheet(from: example))
                    }
                } label: {
                    Label("Nouvelle à partir d’un exemple", systemImage: "text.book.closed")
                }
                .tint(.primary)
                // ⌘N is a command of the app, so it works while this list is hidden.
                Button("Nouvelle feuille", systemImage: "square.and.pencil") {
                    open(library.createSheet())
                }
                .tint(.primary)
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheetRenameAlert($renaming)
        .safeAreaInset(edge: .bottom) {
            if let deletedSheet, !library.contains(deletedSheet.id) {
                DeletionUndoBar(title: deletedSheet.displayTitle) { restore(deletedSheet) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: deletedSheet?.id)
    }

    /// Deletes at once and offers to undo, instead of asking first: the sheet
    /// comes back with the bar's button or with the system undo gesture.
    private func delete(_ record: SheetRecord) {
        guard let removed = library.deleteSheet(id: record.id) else { return }
        if selection == removed.id { selection = nil }
        deletedSheet = removed
        undoManager?.registerUndo(withTarget: library) { library in
            MainActor.assumeIsolated { library.restoreSheet(removed) }
        }
        undoManager?.setActionName(String(localized: "Supprimer la feuille"))
        VoiceOverAnnouncement.post(String(localized: "Feuille supprimée. Annuler est disponible."))
        undoTimeout?.cancel()
        undoTimeout = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { deletedSheet = nil }
        }
    }

    private func restore(_ record: SheetRecord) {
        undoTimeout?.cancel()
        deletedSheet = nil
        undoManager?.removeAllActions(withTarget: library)
        library.restoreSheet(record)
    }

    @ViewBuilder
    private func actions(for record: SheetRecord) -> some View {
        Button("Renommer", systemImage: "character.cursor.ibeam") { renaming = record }
        Button("Dupliquer", systemImage: "plus.square.on.square") {
            library.duplicateSheet(id: record.id)
        }
        ShareLink(item: record.source) {
            Label("Partager", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button("Supprimer", systemImage: "trash", role: .destructive) { delete(record) }
    }
}

/// Shown for a few seconds after a sheet is deleted.
private struct DeletionUndoBar: View {
    let title: String
    let undo: () -> Void

    var body: some View {
        HStack {
            Text("« \(title) » supprimée")
                .lineLimit(1)
            Spacer()
            Button("Annuler", action: undo)
                .fontWeight(.semibold)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

private extension View {
    /// Beside a sheet, the iPadOS 26 sidebar shows its title inline between the
    /// toolbar buttons, where it is reduced to an ellipsis. The Calcul tab
    /// already names the list there; compact width keeps the large title.
    @ViewBuilder
    func sidebarTitleFitsToolbar(_ horizontalSizeClass: UserInterfaceSizeClass?) -> some View {
        if #available(iOS 26, *), horizontalSizeClass == .regular {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}

/// Title, modification date and first displayed result, like a note in Notes.
private struct SheetRow: View {
    @Environment(SheetLibrary.self) private var library
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let record: SheetRecord
    @State private var evaluatedPreview: SheetRecord.ResultPreview?

    private var preview: SheetRecord.ResultPreview? {
        // An open sheet already has its results; others are evaluated in the background.
        if let session = library.openSession(for: record.id) {
            guard let text = session.resultPreview, let spoken = session.spokenResultPreview else { return nil }
            return SheetRecord.ResultPreview(text: text, spoken: spoken)
        }
        return evaluatedPreview
    }

    /// At accessibility sizes the date and the preview stack, and nothing is cut short.
    private var detailLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        let lineLimit = dynamicTypeSize.isAccessibilitySize ? nil : 1
        VStack(alignment: .leading, spacing: 4) {
            Text(record.displayTitle)
                .font(.headline)
                .lineLimit(lineLimit)
                // An automatic title arrives a moment after the sheet is left.
                .contentTransition(.opacity)
                .animation(.smooth, value: record.displayTitle)
            detailLayout {
                Text(record.modifiedAt, format: .relative(presentation: .named))
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                if let preview {
                    Text(preview.text)
                        .lineLimit(lineLimit)
                        .accessibilityLabel(preview.spoken)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .task(id: record.modifiedAt) {
            guard library.openSession(for: record.id) == nil else { return }
            let record = record
            let preview = await Task.detached(priority: .utility) { record.resultPreviewWithSpeech() }.value
            if !Task.isCancelled { evaluatedPreview = preview }
        }
    }
}
