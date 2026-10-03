import SwiftUI

struct FormulaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var showsResult: Bool
    @State private var component: FormulaComponent?
    @FocusState private var isEditing: Bool
    let onSave: (String, Bool) -> Void

    init(source: String, showsResult: Bool = false, onSave: @escaping (String, Bool) -> Void) {
        _draft = State(initialValue: source)
        _showsResult = State(initialValue: showsResult)
        self.onSave = onSave
    }

    private var cleanedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNote: Bool {
        cleanedDraft.hasPrefix("#") || cleanedDraft.hasPrefix("//")
    }

    private var canSave: Bool {
        !cleanedDraft.isEmpty && draft.rangeOfCharacter(from: .newlines) == nil
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
                    TextField("Ex. F = m * a", text: $draft, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(2...5)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isEditing)
                        .accessibilityLabel("Formule ou déclaration")
                } header: {
                    Text("Formule ou variable")
                } footer: {
                    if draft.rangeOfCharacter(from: .newlines) != nil {
                        Text("Saisissez une seule formule par ligne.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Vous pouvez écrire F = m * a ou simplement m * a. Ajoutez les unités aux valeurs : a = 7,2 m/s².")
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
                } header: {
                    Text("Écriture mathématique")
                } footer: {
                    Text("Composez la formule avec des champs pour le numérateur, le dénominateur, l’exposant ou la racine. L’aperçu se met à jour pendant la saisie.")
                }
                .disabled(isNote)

                Section {
                    Toggle("Afficher dans Résultats", isOn: $showsResult)
                        .disabled(isNote)
                } footer: {
                    Text("Choisissez les formules et les variables dont vous souhaitez voir le résultat numérique.")
                }
            }
            .navigationTitle("Éditer une formule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(cleanedDraft, showsResult && !isNote)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { isEditing = false }
                }
            }
            .sheet(item: $component) { selected in
                FormulaComponentSheet(component: selected, source: draft) { updated in
                    draft = updated
                }
            }
        }
    }

    private func show(_ selected: FormulaComponent) {
        isEditing = false
        component = selected
    }
}

private enum FormulaComponent: String, Identifiable {
    case fraction, power, radical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fraction: "Fraction"
        case .power: "Puissance"
        case .radical: "Racine carrée"
        }
    }

    var firstLabel: String {
        switch self {
        case .fraction: "Numérateur"
        case .power: "Base"
        case .radical: "Expression sous la racine"
        }
    }

    var secondLabel: String {
        self == .fraction ? "Dénominateur" : "Exposant"
    }
}

private enum FormulaComposition: String, CaseIterable, Identifiable {
    case replace, add, subtract, multiply, divide

    var id: String { rawValue }

    var title: String {
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

/// Retains the left member of a declaration or equality while editing its right member.
private struct FormulaMembers {
    let prefix: String
    let expression: String
    let comment: String

    init(_ source: String) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let commentMarkers = [trimmed.firstIndex(of: "#"), trimmed.range(of: "//")?.lowerBound].compactMap { $0 }
        let commentStart = commentMarkers.min() ?? trimmed.endIndex
        let formula = String(trimmed[..<commentStart]).trimmingCharacters(in: .whitespaces)
        comment = commentStart == trimmed.endIndex ? "" : " " + String(trimmed[commentStart...])
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

private struct FormulaComponentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var first: String
    @State private var second: String
    @State private var composition: FormulaComposition = .replace
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
            && first.rangeOfCharacter(from: .newlines) == nil
            && second.rangeOfCharacter(from: .newlines) == nil
            && !firstValue.contains("=") && !secondValue.contains("=")
            && !firstValue.contains("#") && !secondValue.contains("#")
            && !firstValue.contains("//") && !secondValue.contains("//")
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
        return members.prefix + composition.apply(constructed, to: members.expression) + members.comment
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Aperçu de la formule") {
                    if canInsert {
                        FormulaView(source: updatedSource)
                    } else {
                        Text("Complétez les champs pour voir la formule.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    expressionField(component.firstLabel, placeholder: "Ex. m * a", text: $first)
                        .focused($focusedField, equals: 0)
                    if component != .radical {
                        expressionField(component.secondLabel, placeholder: component == .power ? "Ex. 2" : "Ex. t", text: $second)
                            .focused($focusedField, equals: 1)
                    }
                } header: {
                    Text(component.title)
                } footer: {
                    Text("Chaque champ accepte des variables, des valeurs avec unités et des expressions, comme m * a ou 2 s.")
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
            .navigationTitle(component.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insérer") {
                        onInsert(updatedSource)
                        dismiss()
                    }
                    .disabled(!canInsert)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { focusedField = nil }
                }
            }
        }
    }

    private func expressionField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(1...3)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(label)
        }
    }
}
