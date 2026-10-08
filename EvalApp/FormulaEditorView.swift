import EvalCore
import SwiftUI

struct FormulaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var showsResult: Bool
    /// Once the user flips the switch, the default no longer follows the formula.
    @State private var choseResult = false
    @State private var component: FormulaComponent?
    /// The dimension of the draft’s value, once the sheet has evaluated it.
    @State private var dimension: EvalCore.Dimension?
    @State private var showsReferences = false
    @State private var selection = FormulaSelectionState()
    @FocusState private var isEditing: Bool
    let isNew: Bool
    let variableNames: [String]
    /// Evaluates a draft within its sheet, to know the dimension of its value.
    let evaluate: @MainActor (String) async -> EvaluatedLine?
    let onSave: (String, Bool) -> Void

    init(source: String, showsResult: Bool = false, isNew: Bool = false, variableNames: [String] = [],
         evaluate: @escaping @MainActor (String) async -> EvaluatedLine? = { _ in nil },
         onSave: @escaping (String, Bool) -> Void) {
        _draft = State(initialValue: source)
        _showsResult = State(initialValue: showsResult)
        self.isNew = isNew
        self.variableNames = variableNames
        self.evaluate = evaluate
        self.onSave = onSave
    }

    private var cleanedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNote: Bool {
        cleanedDraft.hasPrefix("#") || cleanedDraft.hasPrefix("//")
    }

    private var canSave: Bool {
        !cleanedDraft.isEmpty
    }

    /// A new line shows its value, unless it only sets a number, which the ruler already shows.
    /// A conversion or an unknown asks for the value, so it is shown.
    private var showsResultSwitch: Binding<Bool> {
        Binding {
            if isNew && !choseResult {
                return AdjustableVariable(source: cleanedDraft) == nil || LineSyntax(cleanedDraft).requestsValue
            }
            return showsResult
        } set: { newValue in
            choseResult = true
            showsResult = newValue
        }
    }

    /// The unit after the arrow of the draft; nil when the result stays in SI.
    private var conversion: String? {
        LineSyntax(draft).conversion.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var displayUnits: [String] {
        let current = conversion
        guard let dimension else { return current.map { [$0] } ?? [] }
        return DisplayUnitMenu.symbols(for: dimension, current: current)
    }

    private var displayUnitSelection: Binding<String?> {
        Binding {
            conversion
        } set: { symbol in
            draft = LineSyntax(draft).replacingConversion(symbol)
        }
    }

    /// A conversion applies to a value: not to a note or to a comparison.
    private var offersDisplayUnit: Bool {
        !isNote && !LineSyntax(draft).isComparison && !displayUnits.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Aperçu") {
                    if cleanedDraft.isEmpty {
                        Text("Votre formule apparaît ici.")
                            .foregroundStyle(.secondary)
                    } else {
                        FormulaView(source: draft)
                    }
                }

                Section {
                    FormulaTextField(title: "Ex. F = m * a", text: $draft, selection: selection, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(1...5)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isEditing)
                        .accessibilityLabel("Formule ou déclaration")
                        .onChange(of: draft) { oldValue, newValue in
                            // Return validates, as in a single-line field; long formulas still wrap.
                            // A pasted block becomes one line instead.
                            guard newValue.contains(where: \.isNewline) else { return }
                            let typedReturn = newValue.count == oldValue.count + 1
                            draft = typedReturn ? newValue.filter { !$0.isNewline }
                                : newValue.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: " ")
                            if typedReturn { save() }
                        }
                } header: {
                    Text("Formule ou variable")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Vous pouvez écrire F = m * a ou simplement m * a. Ajoutez les unités aux valeurs : a = 7,2 m/s². La touche Retour enregistre la ligne.")
                        Text("Écrivez v = ? m/s et une relation avec == pour calculer v.")
                    }
                }

                Section {
                    Button("Fraction", systemImage: "divide") {
                        show(.fraction)
                    }
                    Button("Puissance", systemImage: "textformat.superscript") {
                        show(.power)
                    }
                    Button("Racine carrée", systemImage: "x.squareroot") {
                        show(.radical)
                    }
                    Button("Constante ou unité…", systemImage: "books.vertical") {
                        isEditing = false
                        showsReferences = true
                    }
                } header: {
                    Text("Insérer")
                } footer: {
                    Text("Composez une fraction, une puissance ou une racine avec des champs dédiés, ou cherchez une constante ou une unité du catalogue. L’aperçu se met à jour pendant la saisie.")
                }
                .disabled(isNote)

                if offersDisplayUnit {
                    Section {
                        Picker("Afficher en", selection: displayUnitSelection) {
                            Text("Unités SI").tag(String?.none)
                            ForEach(displayUnits, id: \.self) { symbol in
                                Text(symbol).tag(Optional(symbol))
                            }
                        }
                        .pickerStyle(.menu)
                    } footer: {
                        Text("Le résultat est converti dans cette unité. La formule reste inchangée : Eval ajoute → et l’unité à la fin de la ligne.")
                    }
                }

                Section {
                    Toggle("Afficher dans Résultats", isOn: showsResultSwitch)
                        .disabled(isNote)
                } footer: {
                    Text("Choisissez les formules et les variables dont vous souhaitez voir le résultat numérique.")
                }
            }
            .navigationTitle(isNew ? "Nouvelle ligne" : "Modifier la ligne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26, *) {
                        Button("Annuler", role: .close) { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    } else {
                        Button("Annuler") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if #available(iOS 26, *) {
                        Button("Enregistrer", role: .confirm, action: save)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(!canSave)
                    } else {
                        Button("Enregistrer", action: save)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(!canSave)
                    }
                }
                FormulaKeyboardToolbar(variableNames: variableNames, insert: insert,
                                       showReferences: { isEditing = false; showsReferences = true },
                                       done: { isEditing = false })
            }
            .navigationDestination(item: $component) { selected in
                FormulaComponentView(component: selected, source: draft) { updated in
                    draft = updated
                }
            }
            .sheet(isPresented: $showsReferences) {
                ReferencePickerView(insert: insert)
            }
            .task(id: cleanedDraft) {
                // The sheet evaluates the draft once typing pauses.
                guard !cleanedDraft.isEmpty, !isNote else { return }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                if let value = await evaluate(cleanedDraft)?.quantity { dimension = value.dimension }
            }
            .task {
                // The keyboard bar belongs to the field that has the focus, so the
                // focus waits until the sheet has its toolbar.
                try? await Task.sleep(for: .milliseconds(400))
                isEditing = true
                // The field chooses its caret when it takes the focus: the end comes after.
                try? await Task.sleep(for: .milliseconds(150))
                selection.placeCaretAtEnd(of: draft)
            }
        }
    }

    private func save() {
        guard canSave else { return }
        onSave(cleanedDraft, showsResultSwitch.wrappedValue && !isNote)
        dismiss()
    }

    private func insert(_ snippet: FormulaInsertion.Snippet) {
        selection.insert(snippet, into: &draft)
    }

    private func show(_ selected: FormulaComponent) {
        isEditing = false
        component = selected
    }
}

private enum FormulaComponent: String, Identifiable, Hashable {
    case fraction, power, radical

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .fraction: "Fraction"
        case .power: "Puissance"
        case .radical: "Racine carrée"
        }
    }

    var firstLabel: LocalizedStringResource {
        switch self {
        case .fraction: "Numérateur"
        case .power: "Base"
        case .radical: "Expression sous la racine"
        }
    }

    var secondLabel: LocalizedStringResource {
        self == .fraction ? "Dénominateur" : "Exposant"
    }
}

private enum FormulaComposition: String, CaseIterable, Identifiable {
    case replace, add, subtract, multiply, divide

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .replace: "Remplacer l’expression"
        case .add: "Additionner"
        case .subtract: "Soustraire"
        case .multiply: "Multiplier"
        case .divide: "Diviser"
        }
    }

    func apply(_ component: String, to expression: String) -> String {
        guard !expression.isEmpty, self != .replace else { return component }
        let operation: String
        switch self {
        case .replace: return component
        case .add: operation = "+"
        case .subtract: operation = "-"
        case .multiply: operation = "*"
        case .divide: operation = "/"
        }
        return "(\(expression)) \(operation) (\(component))"
    }
}

/// Retains the left member of a declaration or equality while editing its right member,
/// and what follows the formula: the conversion `→ unit` and the comment.
private struct FormulaMembers {
    let prefix: String
    let expression: String
    /// ` → unit # comment`, spacing normalised, or empty.
    let suffix: String

    init(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = LineSyntax(trimmed)
        let formula = line.body.trimmingCharacters(in: .whitespaces)
        let tail = String(trimmed[line.bodyRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        suffix = tail.isEmpty ? "" : " " + tail
        if let equality = formula.range(of: "==") {
            prefix = String(formula[..<equality.upperBound]) + " "
            expression = String(formula[equality.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else if let assignment = formula.firstIndex(of: "=") {
            let end = formula.index(after: assignment)
            prefix = String(formula[..<end]) + " "
            expression = String(formula[end...]).trimmingCharacters(in: .whitespaces)
        } else {
            prefix = ""
            expression = formula
        }
    }
}

/// Composes a fraction, a power or a root in the editor’s navigation stack.
/// The back button cancels; Insérer puts the construction in the formula.
private struct FormulaComponentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var first: String
    @State private var second: String
    @State private var composition: FormulaComposition = .replace
    @State private var firstSelection = FormulaSelectionState()
    @State private var secondSelection = FormulaSelectionState()
    @FocusState private var focusedField: Int?
    let component: FormulaComponent
    let members: FormulaMembers
    let onInsert: (String) -> Void

    init(component: FormulaComponent, source: String, onInsert: @escaping (String) -> Void) {
        let members = FormulaMembers(source)
        self.component = component
        self.members = members
        self.onInsert = onInsert
        _first = State(initialValue: members.expression)
        _second = State(initialValue: component == .power ? "2" : "")
    }

    private var firstValue: String { first.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var secondValue: String { second.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canInsert: Bool {
        !firstValue.isEmpty && (component == .radical || !secondValue.isEmpty)
            && !firstValue.contains("=") && !secondValue.contains("=")
            && !firstValue.contains("#") && !secondValue.contains("#")
            && !firstValue.contains("//") && !secondValue.contains("//")
            && !firstValue.contains("→") && !secondValue.contains("→")
            && !firstValue.contains("->") && !secondValue.contains("->")
    }

    private var updatedSource: String {
        let constructed: String
        switch component {
        case .fraction:
            constructed = "(\(firstValue)) / (\(secondValue))"
        case .power:
            constructed = "(\(firstValue)) ^ (\(secondValue))"
        case .radical:
            constructed = "sqrt(\(firstValue))"
        }
        return members.prefix + composition.apply(constructed, to: members.expression) + members.suffix
    }

    var body: some View {
        Form {
            Section("Aperçu de la formule") {
                if canInsert {
                    FormulaView(source: updatedSource)
                } else {
                    Text("Remplissez les champs pour voir la formule.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                expressionField(component.firstLabel, placeholder: "Ex. m * a", text: $first,
                                selection: firstSelection, field: 0)
                if component != .radical {
                    expressionField(component.secondLabel, placeholder: component == .power ? "Ex. 2" : "Ex. t",
                                    text: $second, selection: secondSelection, field: 1)
                }
            } header: {
                Text(component.title)
            } footer: {
                Text("Chaque champ accepte des variables, des valeurs avec unités et des expressions, comme m * a ou 2 s. La touche Retour passe au champ suivant, puis insère.")
            }

            if !members.expression.isEmpty {
                Section {
                    Picker("Appliquer à la formule", selection: $composition) {
                        ForEach(FormulaComposition.allCases) { operation in
                            Text(operation.title).tag(operation)
                        }
                    }
                } footer: {
                    Text(members.prefix.isEmpty ? "La construction remplace l’expression ou se combine avec elle." : "Le membre de gauche est conservé. La construction s’applique au membre de droite.")
                }
            }
        }
        .navigationTitle(Text(component.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Insérer", action: insertAndClose)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canInsert)
            }
            FormulaKeyboardToolbar(insert: insertSnippet, done: { focusedField = nil })
        }
        .onAppear { focusedField = 0 }
    }

    private var lastField: Int { component == .radical ? 0 : 1 }

    private func insertAndClose() {
        guard canInsert else { return }
        onInsert(updatedSource)
        dismiss()
    }

    /// Inserts into the field that has the keyboard.
    private func insertSnippet(_ snippet: FormulaInsertion.Snippet) {
        if focusedField == 1 {
            secondSelection.insert(snippet, into: &second)
        } else {
            firstSelection.insert(snippet, into: &first)
        }
    }

    private func expressionField(_ label: LocalizedStringResource, placeholder: LocalizedStringKey,
                                 text: Binding<String>, selection: FormulaSelectionState, field: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            FormulaTextField(title: placeholder, text: text, selection: selection, axis: .vertical)
                .lineLimit(1...3)
                .font(.body.monospaced())
                .submitLabel(field == lastField ? .done : .next)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .accessibilityLabel(Text(label))
                .onChange(of: text.wrappedValue) { oldValue, newValue in
                    // Return moves on to the next field and, from the last one, inserts.
                    guard newValue.contains(where: \.isNewline) else { return }
                    let typedReturn = newValue.count == oldValue.count + 1
                    text.wrappedValue = newValue.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                        .joined(separator: typedReturn ? "" : " ")
                    guard typedReturn else { return }
                    if field < lastField { focusedField = field + 1 } else { insertAndClose() }
                }
        }
    }
}
