import EvalCore
import SwiftUI

struct NotebookView: View {
    @ObservedObject var notebook: NotebookStore
    @FocusState private var isEditing: Bool
    @State private var showsHelp = false
    @State private var showsResultSelection = false
    @State private var formulaDraft: FormulaDraft?
    @State private var pendingExample: NotebookExample?
    @State private var showsReplacementConfirmation = false
    @State private var showsClearConfirmation = false

    private var formulaLines: [IndexedFormulaLine] {
        notebook.resultSelection.entries.enumerated().compactMap { index, entry in
            guard !entry.source.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return IndexedFormulaLine(index: index, entry: entry)
        }
    }

    private var hiddenErrors: [EvaluatedLine] {
        notebook.selectableLines.filter { $0.status == .error && !notebook.resultSelection.isSelected(at: $0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode de saisie", selection: $notebook.editorMode) {
                        ForEach(NotebookEditorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if notebook.editorMode == .text {
                        TextEditor(text: $notebook.source)
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(minHeight: 210)
                            .focused($isEditing)
                            .accessibilityLabel("Feuille de formules")
                            .accessibilityHint("Une formule ou une déclaration par ligne. Les unités suivent les valeurs, séparées par un espace.")
                    } else {
                        ForEach(formulaLines) { item in
                            formulaRow(item)
                        }
                    }
                    Button("Ajouter une formule", systemImage: "plus") {
                        isEditing = false
                        formulaDraft = FormulaDraft()
                    }
                } header: {
                    Text("Feuille de calcul")
                } footer: {
                    Text(notebook.editorMode == .formulas
                         ? "Touchez une ligne pour la modifier ou composer une fraction. Glissez le curseur d’une variable pour ajuster sa valeur ; son bouton de réglage change les bornes et le pas."
                         : "Une ligne par formule ou variable. Les déclarations peuvent précéder ou suivre les formules. Choisissez les lignes à afficher dans Résultats.")
                }

                if notebook.editorMode == .text && !notebook.adjustableVariables.isEmpty {
                    Section {
                        ForEach(notebook.adjustableVariables) { item in
                            variableSlider(item.variable, id: item.id)
                        }
                    } header: {
                        Text("Ajuster les variables")
                    } footer: {
                        Text("Glissez pour modifier les valeurs numériques. Les unités saisies sont conservées et les résultats se mettent à jour pendant le réglage.")
                    }
                }

                Section {
                    if notebook.displayedResultLines.isEmpty && notebook.isEvaluating {
                        ProgressView("Mise à jour des résultats…")
                    } else if notebook.displayedResultLines.isEmpty {
                        ContentUnavailableView {
                            Label("Aucun résultat choisi", systemImage: "checklist")
                        } description: {
                            Text("Choisissez les formules ou variables dont vous souhaitez voir le résultat.")
                        } actions: {
                            Button("Choisir les résultats") { showsResultSelection = true }
                                .disabled(notebook.selectableLines.isEmpty)
                        }
                    } else {
                        ForEach(notebook.displayedResultLines) { line in
                            ResultRow(line: line)
                                .contextMenu {
                                    Button("Masquer ce résultat", systemImage: "eye.slash") {
                                        notebook.setResultDisplayed(false, at: line.id)
                                    }
                                }
                        }
                    }
                } header: {
                    HStack {
                        Text("Résultats")
                        if notebook.isEvaluating {
                            ProgressView().controlSize(.mini)
                                .accessibilityLabel("Calcul en cours")
                        }
                        Spacer()
                        Button("Choisir", systemImage: "checklist") { showsResultSelection = true }
                            .textCase(nil)
                    }
                } footer: {
                    Text("Seules les lignes choisies sont affichées ici. Les autres continuent de participer au calcul. Les résultats sont exprimés en unités SI.")
                }

                if notebook.editorMode == .text && !hiddenErrors.isEmpty {
                    Section("À corriger") {
                        ForEach(hiddenErrors) { line in
                            ResultRow(line: line)
                        }
                    }
                }

                if !notebook.evaluation.constants.isEmpty {
                    Section {
                        ForEach(notebook.evaluation.constants) { constant in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(constant.symbol).font(.body.monospaced())
                                    Text(constant.name).foregroundStyle(.secondary)
                                }
                                Text(QuantityFormatter.string(constant.quantity))
                                    .font(.callout.monospacedDigit())
                                    .textSelection(.enabled)
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
            .navigationTitle("Eval")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Aide", systemImage: "questionmark.circle") { showsHelp = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Choisir les résultats", systemImage: "checklist") { showsResultSelection = true }
                        Menu("Charger un exemple", systemImage: "text.book.closed") {
                            ForEach(NotebookExample.allCases) { example in
                                Button(example.title) {
                                    pendingExample = example
                                    if notebook.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        notebook.loadExample(example)
                                    } else {
                                        showsReplacementConfirmation = true
                                    }
                                }
                            }
                        }
                        ShareLink(item: notebook.source) {
                            Label("Partager la feuille", systemImage: "square.and.arrow.up")
                        }
                        Button("Effacer la feuille", systemImage: "trash", role: .destructive) {
                            showsClearConfirmation = true
                        }
                    } label: {
                        Label("Actions de la feuille", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { isEditing = false }
                }
            }
            .sheet(isPresented: $showsHelp) { HelpView() }
            .sheet(isPresented: $showsResultSelection) { ResultSelectionView(notebook: notebook) }
            .sheet(item: $formulaDraft) { draft in
                FormulaEditorView(source: draft.source, showsResult: draft.showsResult) { expression, showsResult in
                    notebook.saveFormula(expression, lineID: draft.lineID, showsResult: showsResult)
                }
            }
            .confirmationDialog("Remplacer la feuille par cet exemple ?", isPresented: $showsReplacementConfirmation, titleVisibility: .visible) {
                Button("Charger l’exemple") {
                    if let example = pendingExample { notebook.loadExample(example) }
                }
            } message: {
                Text("Le contenu actuel de la feuille sera remplacé.")
            }
            .confirmationDialog("Effacer la feuille ?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { notebook.source = "" }
            }
        }
    }

    private func formulaRow(_ item: IndexedFormulaLine) -> some View {
        let line = notebook.evaluation.lines.first { $0.id == item.index && $0.source == item.entry.source }
        let trimmed = item.entry.source.trimmingCharacters(in: .whitespaces)
        let isComment = trimmed.hasPrefix("#") || trimmed.hasPrefix("//")
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                formulaDraft = FormulaDraft(lineID: item.entry.id, source: item.entry.source, showsResult: item.entry.isSelected)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        Text("\(item.index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        FormulaView(source: item.entry.source)
                    }
                    if item.entry.isSelected && !isComment {
                        Label("Résultat affiché", systemImage: "pin.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if line?.status == .error, let message = line?.message {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.red)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Modifier la formule et choisir si son résultat doit être affiché.")
            if let variable = AdjustableVariable(source: item.entry.source) {
                variableSlider(variable, id: item.entry.id)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if !isComment {
                Button(item.entry.isSelected ? "Masquer le résultat" : "Afficher le résultat",
                       systemImage: item.entry.isSelected ? "eye.slash" : "eye") {
                    notebook.setResultDisplayed(!item.entry.isSelected, at: item.index)
                }
            }
            Button("Modifier", systemImage: "pencil") {
                formulaDraft = FormulaDraft(lineID: item.entry.id, source: item.entry.source, showsResult: item.entry.isSelected)
            }
            Button("Supprimer", systemImage: "trash", role: .destructive) {
                notebook.removeLine(id: item.entry.id)
            }
        }
        .swipeActions {
            if AdjustableVariable(source: item.entry.source) == nil {
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    notebook.removeLine(id: item.entry.id)
                }
            }
        }
    }

    @ViewBuilder
    private func variableSlider(_ variable: AdjustableVariable, id: UUID) -> some View {
        if let range = notebook.adjustmentRange(for: id, variable: variable) {
            VariableSliderView(variable: variable, range: range, usesAutomaticStep: !notebook.manualStepIDs.contains(id)) { value in
                notebook.adjustVariable(value, lineID: id, range: range)
            } onChangeRange: { configured, automatic in
                notebook.setAdjustmentRange(configured, for: id, automaticStep: automatic)
                let bounded = min(configured.upperBound, max(configured.lowerBound, variable.value))
                notebook.adjustVariable(bounded, lineID: id, range: configured)
            }
        }
    }
}

private struct FormulaDraft: Identifiable {
    let id = UUID()
    var lineID: UUID?
    var source = ""
    var showsResult = false
}

private struct IndexedFormulaLine: Identifiable {
    var id: UUID { entry.id }
    let index: Int
    let entry: ResultSelection.Entry
}

private struct ResultSelectionView: View {
    @ObservedObject var notebook: NotebookStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if notebook.selectableLines.isEmpty && notebook.isEvaluating {
                    ProgressView("Mise à jour des formules…")
                } else if notebook.selectableLines.isEmpty {
                    ContentUnavailableView("Aucune formule à choisir", systemImage: "function",
                                           description: Text("Ajoutez une formule ou une variable dans la feuille."))
                } else {
                    Section {
                        ForEach(notebook.selectableLines) { line in
                            Toggle(isOn: Binding(
                                get: { notebook.resultSelection.isSelected(at: line.id) },
                                set: { notebook.setResultDisplayed($0, at: line.id) }
                            )) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Ligne \(line.id + 1)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    FormulaView(source: line.source)
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
                        Button("Tout afficher") { notebook.selectAllResults(true) }
                        Button("Tout masquer") { notebook.selectAllResults(false) }
                    }
                    .disabled(notebook.isEvaluating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }
}

private struct ResultRow: View {
    let line: EvaluatedLine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("\(line.id + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Ligne \(line.id + 1)")
                FormulaView(source: line.source)
            }
            if let quantity = line.quantity {
                Text(QuantityFormatter.string(quantity))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .textSelection(.enabled)
            }
            if let message = line.message {
                Label(message, systemImage: line.status == .error ? "exclamationmark.triangle" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(line.status == .error ? Color.red : Color.secondary)
            }
            if let dimensionMessage = line.dimensionMessage {
                Label(dimensionMessage, systemImage: dimensionMessage.hasPrefix("Homogène") ? "checkmark.circle" : "ruler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
