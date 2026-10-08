import EvalCore
import SwiftUI

/// The sheets of this device, most recently modified first.
struct SheetListView: View {
    @Environment(SheetLibrary.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selection: UUID?
    var searchRequest = 0
    let open: (UUID) -> Void
    @State private var search = ""
    @State private var renaming: SheetRecord?
    @State private var pendingDeletion: SheetRecord?

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
                pendingDeletion = offsets.first.map { sheets[$0] }
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
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ExampleMenuContent { example in
                        open(library.createSheet(from: example))
                    }
                } label: {
                    Label("Nouvelle à partir d’un exemple", systemImage: "text.book.closed")
                }
                // ⌘N is a command of the app, so it works while this list is hidden.
                Button("Nouvelle feuille", systemImage: "square.and.pencil") {
                    open(library.createSheet())
                }
            }
        }
        .sheetRenameAlert($renaming)
        .sheetDeletionConfirmation($pendingDeletion) { id in
            if selection == id { selection = nil }
        }
    }

    @ViewBuilder
    private func actions(for record: SheetRecord) -> some View {
        Button("Renommer", systemImage: "pencil") { renaming = record }
        Button("Dupliquer", systemImage: "plus.square.on.square") {
            library.duplicateSheet(id: record.id)
        }
        ShareLink(item: record.source) {
            Label("Partager", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button("Supprimer", systemImage: "trash", role: .destructive) { pendingDeletion = record }
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
