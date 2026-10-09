import EvalCore
import SwiftUI

/// One sheet, on a single page: its lines, each with the value it asks for,
/// then the constants and unit symbols the sheet relies on. A line is edited
/// where it is; a last row adds a line, as in Reminders.
struct NotebookView: View {
    @Bindable var notebook: NotebookStore
    /// Shows another sheet in this window, such as a copy or a new example.
    let open: (UUID) -> Void
    @Environment(SheetLibrary.self) private var library
    @AppStorage(FormulaInputMode.storageKey) private var inputMode = FormulaInputMode.text
    @Environment(\.undoManager) private var undoManager
    /// The line whose field has the keyboard.
    @FocusState private var focusedLineID: UUID?
    /// The line edited in place, from the moment it is touched to the loss of its focus.
    @State private var editing: NotebookStore.LineEditingSession?
    @State private var textSelection = FormulaSelectionState()
    /// How the bar reaches the mathematical editor of the edited line.
    @State private var mathKeys = MathKeyHandler()
    @State private var editMode = EditMode.inactive
    @State private var showsHelp = false
    @State private var showsSettings = false
    @State private var showsTextEditor = false
    @State private var showsReferences = false
    @State private var plotRequest: PlotRequest?
    @State private var showsClearConfirmation = false
    @State private var renaming: SheetRecord?
    @State private var canUndo = false
    @State private var canRedo = false

    private var isEmpty: Bool {
        notebook.formulaLines.isEmpty
    }

    /// The row « Nouvelle ligne » stands in for a blank last line being edited,
    /// whose field shows the same placeholder in the same place.
    private var showsNewLineRow: Bool {
        guard !editMode.isEditing else { return false }
        guard let editing, let last = notebook.formulaLines.last, last.id == editing.lineID else { return true }
        return !last.entry.source.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let issue = notebook.sheetIssue {
                    Section {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                if !isEmpty {
                    sheetSection
                    constantsSection
                    symbolUnitsSection
                }
            }
            .warmPage()
            .environment(\.editMode, $editMode)
            .scrollDismissesKeyboard(.interactively)
            // The keyboard bar of the edited line floats above the keyboard, which the list keeps avoiding.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if editing != nil {
                    LineKeyboardBar(mode: inputMode, keyboard: lineKeyboard)
                }
            }
            .animation(.snappy, value: editing != nil)
            .overlay {
                if isEmpty { emptyState }
            }
            .onChange(of: notebook.revealRequest) { _, request in
                guard let request else { return }
                withAnimation { proxy.scrollTo(request.lineID, anchor: .center) }
            }
            .task(id: focusedLineID) {
                // Once the keyboard is up, the edited line moves into view above it.
                guard let lineID = focusedLineID else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                withAnimation { proxy.scrollTo(lineID, anchor: UnitPoint(x: 0.5, y: 0.6)) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleMenu {
            Button("Renommer", systemImage: "character.cursor.ibeam") { renaming = notebook.record }
            Button("Dupliquer", systemImage: "plus.square.on.square") {
                if let copy = library.duplicateSheet(id: notebook.id) { open(copy) }
            }
            ShareLink(item: notebook.sharedText(includingResults: true),
                      subject: Text("Feuille Eval"),
                      preview: SharePreview("Feuille Eval", image: Image(systemName: "function"))) {
                Label("Partager la feuille", systemImage: "square.and.arrow.up")
            }
        }
        .toolbar { toolbarContent }
        .environment(\.editMode, $editMode)
        .focusedSceneValue(\.notebookActions, commandActions)
        .sheet(isPresented: $showsHelp) { HelpView() }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .sheet(isPresented: $showsTextEditor) { TextSheetEditor(notebook: notebook, undoManager: undoManager) }
        .sheet(isPresented: $showsReferences, onDismiss: {
            // The line keeps its session while the catalog is open: it gets the keyboard back.
            if let editing { focusedLineID = editing.lineID }
        }) {
            ReferencePickerView { snippet in insertIntoLine(snippet) }
        }
        .sheet(item: $plotRequest) { request in
            PlotView(notebook: notebook, request: request)
        }
        .confirmationDialog("Effacer la feuille ?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { notebook.clear(undoManager: undoManager) }
        }
        .sheetRenameAlert($renaming)
        .onAppear {
            undoManager?.levelsOfUndo = 50
            refreshUndoState()
        }
        .onChange(of: focusedLineID) { old, new in
            focusDidChange(from: old, to: new)
        }
        .onChange(of: editMode) { _, mode in
            if mode.isEditing {
                focusedLineID = nil
                finishEditing()
                notebook.activeRulerLineID = nil
            }
        }
        .onDisappear { finishEditing() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in refreshUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in refreshUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in refreshUndoState() }
    }

    private func createFromExample(_ example: ExampleSheet) {
        open(library.createSheet(from: example))
    }

    /// The title in the bar, renamed in place from its menu, with the same
    /// rules as the Renommer alert.
    private var title: Binding<String> {
        Binding {
            notebook.displayTitle
        } set: { title in
            library.renameSheet(id: notebook.id, to: title)
        }
    }

    private func refreshUndoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    /// The sheet’s commands for the menu bar and the shortcut overlay.
    private var commandActions: NotebookActions {
        NotebookActions(canClear: !isEmpty, newLine: newLine, editAsText: editAsText,
                        clear: { showsClearConfirmation = true })
    }

    // MARK: Editing in place

    /// A line starts its session when touched; the focus follows.
    private func startEditing(_ lineID: UUID) {
        guard !editMode.isEditing else { return }
        if editing?.lineID == lineID {
            focusedLineID = lineID
            return
        }
        finishEditing()
        guard let session = notebook.beginEditing(lineID: lineID) else { return }
        textSelection = FormulaSelectionState()
        editing = session
        focusedLineID = lineID
    }

    /// Ends the session of the edited line: one undo step, and a blank line goes away.
    private func finishEditing() {
        guard let session = editing else { return }
        editing = nil
        notebook.endEditing(session, undoManager: undoManager)
    }

    /// The focus leaving the edited line ends its session, unless the catalog
    /// of constants took it for a moment. A field focused by other means starts one.
    private func focusDidChange(from old: UUID?, to new: UUID?) {
        if let old, old != new, editing?.lineID == old, !showsReferences {
            finishEditing()
        }
        if let new, editing?.lineID != new {
            startEditing(new)
        }
    }

    /// A new blank line at the end of the sheet, edited at once.
    private func newLine() {
        if editMode.isEditing { editMode = .inactive }
        finishEditing()
        guard let session = notebook.insertLines([""], at: nil) else { return }
        textSelection = FormulaSelectionState()
        editing = session
        focusedLineID = session.lineID
    }

    /// A Return, or a paste of several lines, in the edited line: the line keeps
    /// the text before the break, the rest goes to new lines below, and the last
    /// of them is edited. A Return on a blank line only closes it.
    private func breakLine(_ text: String, lineID: UUID) {
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard let first = parts.first, let position = notebook.lineIndex(of: lineID) else { return }
        let rest = Array(parts.dropFirst())
        let isBlank = { (line: String) in line.trimmingCharacters(in: .whitespaces).isEmpty }
        notebook.updateLine(first, lineID: lineID)
        if isBlank(first) && rest.allSatisfy(isBlank) {
            focusedLineID = nil
            return
        }
        finishEditing()
        // A blank first part has just been removed, so the new lines take its place.
        let removed = notebook.lineIndex(of: lineID) == nil
        guard let session = notebook.insertLines(rest, at: removed ? position : position + 1) else { return }
        textSelection = FormulaSelectionState()
        editing = session
        // The keyboard moves to the new line through a moment without focus: a direct
        // move between fields leaves the keyboard without its bar.
        focusedLineID = nil
        Task {
            await Task.yield()
            if editing?.lineID == session.lineID { focusedLineID = session.lineID }
        }
    }

    /// The keyboard bar of the edited line.
    private var lineKeyboard: LineKeyboard {
        LineKeyboard(mathKeys: mathKeys, variableNames: notebook.declaredNames, insert: insertIntoLine,
                     showReferences: { showsReferences = true }, done: { focusedLineID = nil })
    }

    private func insertIntoLine(_ snippet: FormulaInsertion.Snippet) {
        guard let lineID = editing?.lineID, var text = notebook.lineSource(of: lineID) else { return }
        textSelection.insert(snippet, into: &text)
        notebook.updateLine(text, lineID: lineID)
    }

    private func editAsText() {
        focusedLineID = nil
        finishEditing()
        showsTextEditor = true
    }

    /// Undo and Redo of the menu apply to whole lines: the line being edited is validated first.
    private func undo() {
        focusedLineID = nil
        finishEditing()
        undoManager?.undo()
    }

    private func redo() {
        focusedLineID = nil
        finishEditing()
        undoManager?.redo()
    }

    // MARK: Sheet

    private var sheetSection: some View {
        Section {
            ForEach(notebook.formulaLines) { item in
                FormulaRowView(notebook: notebook, item: item, isEditing: editing?.lineID == item.id,
                               inputMode: inputMode, focus: $focusedLineID, selection: textSelection,
                               keyboard: lineKeyboard, edit: startEditing,
                               breakLine: { breakLine($0, lineID: item.id) },
                               plot: { plotRequest = $0 })
            }
            .onMove { offsets, destination in
                notebook.moveLines(fromOffsets: offsets, toOffset: destination, undoManager: undoManager)
            }
            .onDelete { offsets in
                notebook.removeLines(atOffsets: offsets, undoManager: undoManager)
            }
            if showsNewLineRow {
                Button(action: newLine) {
                    Label("Nouvelle ligne", systemImage: "plus")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ajoute une ligne à la fin de la feuille.")
            }
        } footer: {
            Text(sheetFooter)
        }
    }

    private var sheetFooter: LocalizedStringKey {
        if editMode.isEditing {
            return "Faites glisser les lignes pour les réorganiser, puis touchez Terminé. L’ordre n’influe pas sur le calcul."
        }
        return "Touchez une ligne pour la modifier. Terminez-la par = pour afficher sa valeur, comme E =. Maintenez une valeur teintée pour la régler avec la réglette."
    }

    // MARK: Empty sheet

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Feuille vide", systemImage: "function")
        } description: {
            Text("Écrivez une formule ou partez d’un exemple.")
        } actions: {
            Button("Ajouter une formule", action: newLine)
                .buttonStyle(.borderedProminent)
            Menu("Partir d’un exemple") {
                ExampleMenuContent(choose: createFromExample)
            }
        }
    }

    // MARK: Constants and units

    @ViewBuilder
    private var constantsSection: some View {
        if !notebook.constants.isEmpty {
            Section {
                ForEach(notebook.constants) { constant in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(constant.symbol).font(.body.monospaced())
                            Text(constant.name).foregroundStyle(.secondary)
                        }
                        Text(QuantityFormatter.string(constant.quantity, significantDigits: QuantityFormatter.preciseDigits))
                            .font(.callout.monospacedDigit())
                            .textSelection(.enabled)
                            .accessibilityLabel(QuantityFormatter.spokenString(constant.quantity))
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Label("Constantes reconnues", systemImage: "sparkle.magnifyingglass")
            } footer: {
                Text("Ces valeurs sont proposées pour les symboles non déclarés. Une déclaration explicite, comme c = 12 m/s, les remplace dans cette feuille.")
            }
        }
    }

    @ViewBuilder
    private var symbolUnitsSection: some View {
        if !notebook.symbolUnits.isEmpty {
            Section {
                ForEach(notebook.symbolUnits) { unit in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(unit.symbol).font(.body.monospaced())
                            Text(unit.name).foregroundStyle(.secondary)
                        }
                        Text(QuantityFormatter.string(unit.quantity, significantDigits: QuantityFormatter.preciseDigits))
                            .font(.callout.monospacedDigit())
                            .accessibilityLabel(QuantityFormatter.spokenString(unit.quantity))
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Label("Symboles lus comme des unités", systemImage: "ruler")
            } footer: {
                Text("Ces symboles ne sont pas déclarés dans la feuille et ont été interprétés comme des unités. S’il s’agit de variables, déclarez-les, par exemple T = 300 K.")
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if notebook.isEvaluating {
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView()
                    .accessibilityLabel("Calcul en cours")
            }
        }
        if editMode.isEditing {
            // The way out of reordering; it starts from the actions menu.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Terminé") { editMode = .inactive }
                    .fontWeight(.semibold)
                    .tint(.primary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Nouvelle ligne", systemImage: "plus", action: newLine)
                .tint(.primary)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section {
                    Button("Annuler", systemImage: "arrow.uturn.backward", action: undo)
                        .disabled(!canUndo && editing == nil)
                    Button("Rétablir", systemImage: "arrow.uturn.forward", action: redo)
                        .disabled(!canRedo)
                }
                Section {
                    if !isEmpty {
                        Button("Réorganiser", systemImage: "arrow.up.arrow.down") { editMode = .active }
                    }
                    Button("Modifier en texte", systemImage: "text.alignleft", action: editAsText)
                    Button("Renommer", systemImage: "character.cursor.ibeam") { renaming = notebook.record }
                    Menu("Nouvelle à partir d’un exemple", systemImage: "text.book.closed") {
                        ExampleMenuContent(choose: createFromExample)
                    }
                }
                Section {
                    ShareLink(item: notebook.sharedText(includingResults: true),
                              subject: Text("Feuille Eval"),
                              preview: SharePreview("Feuille Eval", image: Image(systemName: "function"))) {
                        Label("Partager la feuille", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: notebook.sharedText(includingResults: false), subject: Text("Feuille Eval")) {
                        Label("Partager sans les résultats", systemImage: "square.and.arrow.up")
                    }
                    Button("Effacer la feuille", systemImage: "trash", role: .destructive) {
                        showsClearConfirmation = true
                    }
                    .disabled(isEmpty)
                }
                Section {
                    Button("Réglages", systemImage: "gearshape") { showsSettings = true }
                    Button("Aide", systemImage: "questionmark.circle") { showsHelp = true }
                }
            } label: {
                Label("Actions de la feuille", systemImage: "ellipsis.circle")
            }
            .tint(.primary)
        }
    }
}

