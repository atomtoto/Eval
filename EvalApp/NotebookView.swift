import EvalCore
import SwiftUI

/// One sheet. In regular width, its results occupy an inspector column beside
/// the formulas; in compact width, Formules mode shows each value under its
/// formula and Texte mode lists the results after the text.
struct NotebookView: View {
    @Bindable var notebook: NotebookStore
    let createFromExample: (ExampleSheet) -> Void
    @AppStorage("eval.notebook.editorMode.v1") private var editorMode = NotebookEditorMode.formulas
    @SceneStorage("eval.showsResults") private var showsResultsColumn = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.undoManager) private var undoManager
    @FocusState private var isTextFocused: Bool
    @State private var editMode = EditMode.inactive
    @State private var showsHelp = false
    @State private var showsResultSelection = false
    @State private var showsReferences = false
    @State private var formulaDraft: FormulaDraft?
    @State private var plotRequest: PlotRequest?
    @State private var showsClearConfirmation = false
    @State private var renaming: SheetRecord?
    @State private var textSelection = FormulaSelectionState()
    @State private var canUndo = false
    @State private var canRedo = false

    private var usesResultsColumn: Bool {
        horizontalSizeClass == .regular && showsResultsColumn
    }

    /// A narrow window never turns the column into a sheet: the results return to the list.
    private var resultsColumnPresentation: Binding<Bool> {
        Binding(get: { usesResultsColumn }, set: { isPresented in
            if horizontalSizeClass == .regular { showsResultsColumn = isPresented }
        })
    }

    private var isEmpty: Bool {
        notebook.source.allSatisfy(\.isWhitespace)
    }

    /// The text editor keeps its own undo history for typing, so the sheet’s
    /// undo steps exist only in Formules mode.
    private var sheetUndoManager: UndoManager? {
        editorMode == .formulas ? undoManager : nil
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
                if editorMode == .text || !isEmpty {
                    sheetSection
                }
                if editorMode == .text && !isEmpty {
                    if !usesResultsColumn {
                        resultsSection
                        correctionsSection
                    }
                    variablesSection
                }
                if !isEmpty && !usesResultsColumn {
                    constantsSection
                    symbolUnitsSection
                }
            }
            .environment(\.editMode, $editMode)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if editorMode == .formulas && isEmpty { emptyState }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if editorMode == .text && isTextFocused { textResultsStrip }
            }
            .inspector(isPresented: resultsColumnPresentation) {
                List {
                    if !isEmpty {
                        resultsSection
                        if editorMode == .text { correctionsSection }
                        constantsSection
                        symbolUnitsSection
                    }
                }
                .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
            }
            .onChange(of: notebook.revealRequest) { _, request in
                guard let request else { return }
                withAnimation { proxy.scrollTo(request.lineID, anchor: .center) }
            }
        }
        .navigationTitle(notebook.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .environment(\.editMode, $editMode)
        .focusedSceneValue(\.notebookActions, commandActions)
        .sheet(isPresented: $showsHelp) { HelpView() }
        .sheet(isPresented: $showsResultSelection) { ResultSelectionView(notebook: notebook, undoManager: sheetUndoManager) }
        .sheet(isPresented: $showsReferences) {
            ReferencePickerView { snippet in insertIntoText(snippet) }
        }
        .sheet(item: $formulaDraft) { draft in
            FormulaEditorView(source: draft.source, showsResult: draft.showsResult, isNew: draft.lineID == nil,
                              variableNames: notebook.declaredNames,
                              evaluate: { await notebook.evaluatedLine(for: $0, replacing: draft.lineID) }) { expression, showsResult in
                notebook.saveFormula(expression, lineID: draft.lineID, showsResult: showsResult,
                                     undoManager: sheetUndoManager)
            }
        }
        .sheet(item: $plotRequest) { request in
            PlotView(notebook: notebook, request: request)
        }
        .confirmationDialog("Effacer la feuille ?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { notebook.clear(undoManager: sheetUndoManager) }
        }
        .sheetRenameAlert($renaming)
        .onAppear {
            undoManager?.levelsOfUndo = 50
            refreshUndoState()
        }
        .onChange(of: editorMode) {
            editMode = .inactive
            notebook.removeUndoSteps(from: undoManager)
            refreshUndoState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup)) { _ in refreshUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange)) { _ in refreshUndoState() }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange)) { _ in refreshUndoState() }
    }

    private func refreshUndoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    /// The sheet’s commands for the menu bar and the shortcut overlay.
    private var commandActions: NotebookActions {
        NotebookActions(
            editorMode: editorMode,
            canChooseResults: !notebook.selectableLines.isEmpty,
            canClear: !isEmpty,
            toggleResultsColumn: horizontalSizeClass == .regular ? { showsResultsColumn.toggle() } : nil,
            newLine: newLine,
            chooseResults: { showsResultSelection = true },
            setEditorMode: { editorMode = $0 },
            clear: { showsClearConfirmation = true })
    }

    private func newLine() {
        isTextFocused = false
        formulaDraft = FormulaDraft()
    }

    private func insertIntoText(_ snippet: FormulaInsertion.Snippet) {
        var text = notebook.source
        textSelection.insert(snippet, into: &text)
        notebook.source = text
    }

    // MARK: Sheet

    private var sheetSection: some View {
        Section {
            if editorMode == .text {
                // A vertical field grows with its text instead of scrolling inside a fixed box.
                FormulaTextField(title: "Une formule par ligne", text: $notebook.source,
                                 selection: textSelection, axis: .vertical)
                    .font(.body.monospaced())
                    .lineLimit(6...)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isTextFocused)
                    .accessibilityLabel("Feuille de formules")
                    .accessibilityHint("Une formule ou une déclaration par ligne. Les unités suivent les valeurs, séparées par un espace.")
            } else {
                ForEach(notebook.formulaLines) { item in
                    FormulaRowView(notebook: notebook, item: item, showsInlineResult: !usesResultsColumn,
                                   edit: { formulaDraft = $0 }, plot: { plotRequest = $0 })
                }
                .onMove { offsets, destination in
                    notebook.moveLines(fromOffsets: offsets, toOffset: destination, undoManager: sheetUndoManager)
                }
                .onDelete { offsets in
                    notebook.removeLines(atOffsets: offsets, undoManager: sheetUndoManager)
                }
            }
        } header: {
            Text("Feuille de calcul")
        } footer: {
            Text(sheetFooter)
        }
    }

    private var sheetFooter: LocalizedStringKey {
        if editorMode == .text {
            return "Une ligne par formule ou variable. Les déclarations peuvent précéder ou suivre les formules. Choisissez les lignes à afficher dans Résultats."
        }
        if editMode.isEditing {
            return "Faites glisser les lignes pour les réorganiser, puis touchez Terminé. L’ordre n’influe pas sur le calcul."
        }
        return "Touchez une ligne pour la modifier ou composer une fraction. Appuyez longuement pour afficher son résultat, la copier ou la dupliquer. Glissez le curseur d’une variable pour ajuster sa valeur."
    }

    private var variablesSection: some View {
        Section {
            if !notebook.adjustableVariables.isEmpty {
                ForEach(notebook.adjustableVariables) { item in
                    NotebookVariableControl(notebook: notebook, id: item.id, variable: item.variable)
                }
            }
        } header: {
            if !notebook.adjustableVariables.isEmpty { Text("Ajuster les variables") }
        } footer: {
            if !notebook.adjustableVariables.isEmpty {
                Text("Glissez pour modifier les valeurs numériques. Les unités saisies sont conservées et les résultats se mettent à jour pendant le réglage.")
            }
        }
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

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
        Section {
            if notebook.displayedResults.isEmpty && !notebook.hasEvaluation {
                ProgressView("Mise à jour des résultats…")
            } else if notebook.displayedResults.isEmpty {
                ContentUnavailableView {
                    Label("Aucun résultat choisi", systemImage: "checklist")
                } description: {
                    Text("Choisissez les formules ou variables dont vous souhaitez voir le résultat.")
                } actions: {
                    Button("Choisir les résultats") { showsResultSelection = true }
                        .disabled(notebook.selectableLines.isEmpty)
                }
            } else {
                ForEach(notebook.displayedResults) { result in
                    ResultRow(result: result, showsLineNumber: editorMode == .formulas)
                        .contextMenu {
                            Button("Masquer ce résultat", systemImage: "eye.slash") {
                                notebook.setResultDisplayed(false, lineID: result.id, undoManager: sheetUndoManager)
                            }
                            DisplayUnitMenu(line: result.line, source: result.entry.source) { symbol in
                                notebook.setDisplayUnit(symbol, lineID: result.id, undoManager: sheetUndoManager)
                            }
                            PlotMenu(notebook: notebook, lineID: result.id, source: result.entry.source) {
                                plotRequest = $0
                            }
                        }
                        .accessibilityActions {
                            Button("Masquer ce résultat") {
                                notebook.setResultDisplayed(false, lineID: result.id, undoManager: sheetUndoManager)
                            }
                            DisplayUnitActions(line: result.line, source: result.entry.source) { symbol in
                                notebook.setDisplayUnit(symbol, lineID: result.id, undoManager: sheetUndoManager)
                            }
                        }
                }
            }
        } header: {
            Text("Résultats")
        } footer: {
            Text("Seules les lignes choisies sont affichées ici. Les autres continuent de participer au calcul. Les résultats sont exprimés en unités SI, sauf conversion demandée avec →.")
        }
    }

    @ViewBuilder
    private var correctionsSection: some View {
        if !notebook.hiddenErrors.isEmpty {
            Section("À corriger") {
                ForEach(notebook.hiddenErrors) { result in
                    ResultRow(result: result, showsLineNumber: editorMode == .formulas)
                }
            }
        }
    }

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

    /// While typing in Texte mode the keyboard hides the results below the
    /// editor, so the values stay within sight above it.
    @ViewBuilder
    private var textResultsStrip: some View {
        let failures = notebook.hiddenErrors.count
            + notebook.displayedResults.filter { $0.line?.status == .error }.count
        let values = notebook.displayedResults.compactMap { result -> (id: UUID, text: String, spoken: String)? in
            guard let line = result.line, let value = line.formattedValue else { return nil }
            return (result.id, ResultText.line(source: result.entry.source, value: value),
                    ResultText.spokenLine(source: result.entry.source, spokenValue: line.spokenResult ?? value))
        }
        if !values.isEmpty || failures > 0 {
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(values, id: \.id) { value in
                        Text(value.text)
                            .font(.callout.monospacedDigit())
                            .accessibilityLabel(value.spoken)
                    }
                    if failures > 0 {
                        Label("\(failures) à corriger", systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if horizontalSizeClass == .regular {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $showsResultsColumn) {
                    Label("Résultats", systemImage: "sidebar.trailing")
                }
                .toggleStyle(.button)
                .accessibilityHint("Affiche les résultats dans une colonne à côté de la feuille.")
            }
        }
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
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Nouvelle ligne", systemImage: "plus", action: newLine)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if editorMode == .formulas {
                    Section {
                        Button("Annuler", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
                            .disabled(!canUndo)
                        Button("Rétablir", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
                            .disabled(!canRedo)
                    }
                }
                Picker("Mode de saisie", selection: $editorMode) {
                    ForEach(NotebookEditorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                Section {
                    if editorMode == .formulas && !isEmpty {
                        Button("Réorganiser", systemImage: "arrow.up.arrow.down") { editMode = .active }
                    }
                    Button("Choisir les résultats", systemImage: "checklist") { showsResultSelection = true }
                        .disabled(notebook.selectableLines.isEmpty)
                    Button("Renommer", systemImage: "pencil") { renaming = notebook.record }
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
                    Button("Aide", systemImage: "questionmark.circle") { showsHelp = true }
                }
            } label: {
                Label("Actions de la feuille", systemImage: "ellipsis.circle")
            }
        }
        FormulaKeyboardToolbar(insertsSymbols: FormulaSelectionState.tracksCaret && editorMode == .text,
                               variableNames: notebook.declaredNames, insert: insertIntoText,
                               showReferences: { isTextFocused = false; showsReferences = true },
                               done: { isTextFocused = false })
    }
}
