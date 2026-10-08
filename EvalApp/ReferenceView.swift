import EvalCore
import SwiftUI
import UIKit

/// The Références tab: the catalogs of constants and units, to browse and search.
struct ReferenceView: View {
    /// Each change asks the search field to take focus.
    var searchRequest = 0
    /// Adds a constant or a unit to the sheet: what to insert, and its name.
    let insert: (String, String) -> Void

    var body: some View {
        NavigationStack {
            ReferenceCatalogView(mode: .browse(addToSheet: insert), searchRequest: searchRequest)
        }
    }
}

/// A search over the catalogs that inserts the chosen constant or unit into the
/// formula being written.
struct ReferencePickerView: View {
    let insert: (FormulaInsertion.Snippet) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReferenceCatalogView(mode: .pick(insert: insert))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The reference data, prepared once: what each constant matches in a search
/// and how its value is written. Searching then only compares text.
private enum ReferenceIndex {
    struct Entry: Identifiable, Sendable {
        let definition: ConstantDefinition
        let haystack: String
        let valueText: String
        /// « 299 792 458 mètres par seconde » as words.
        let spokenValue: String
        var id: String { definition.id }
    }

    static let constants: [Entry] = ConstantCatalog.all.map { constant in
        let aliases = ConstantCatalog.aliases(for: constant).joined(separator: " ")
        return Entry(
            definition: constant,
            haystack: "\(constant.symbol) \(constant.id) \(constant.name) \(constant.detail) \(constant.category.title) \(constant.sourceName) \(aliases)",
            valueText: QuantityFormatter.string(constant.quantity, significantDigits: QuantityFormatter.preciseDigits),
            spokenValue: QuantityFormatter.spokenString(constant.quantity))
    }
}

private enum ReferenceKind: String, CaseIterable, Identifiable {
    case constants = "Constantes"
    case units = "Unités"
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .constants: "Constantes"
        case .units: "Unités"
        }
    }
}

enum ReferenceMode {
    /// Browsing, with the option to add a constant or unit as a line of the sheet.
    case browse(addToSheet: (_ text: String, _ name: String) -> Void)
    /// Choosing something to insert into a formula; choosing closes the picker.
    case pick(insert: (FormulaInsertion.Snippet) -> Void)
}

/// The searchable list shared by the tab and the picker. It sits in a navigation stack.
struct ReferenceCatalogView: View {
    let mode: ReferenceMode
    var searchRequest = 0
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var kind = ReferenceKind.constants
    @State private var category: ConstantCategory?
    @State private var copies = 0

    private var picks: Bool {
        if case .pick = mode { true } else { false }
    }

    private func matches(_ text: String) -> Bool {
        search.isEmpty || text.localizedStandardContains(search)
    }

    var body: some View {
        // One pass per change of the search or the filter.
        let constants = ReferenceIndex.constants.filter {
            (category == nil || $0.definition.category == category) && matches($0.haystack)
        }
        let grouped = Dictionary(grouping: constants, by: \.definition.category)
        let categories = ConstantCategory.allCases.filter { grouped[$0] != nil }
        let units = UnitCatalog.all.filter { matches("\($0.symbol) \($0.name)") }

        List {
            if kind == .constants {
                ForEach(categories) { category in
                    Section {
                        ForEach(grouped[category] ?? []) { entry in
                            constantRow(entry)
                        }
                    } header: {
                        Text(category.title)
                    } footer: {
                        if category == categories.last { constantsFooter(count: constants.count) }
                    }
                }
            } else {
                Section {
                    ForEach(units) { unit in
                        unitRow(unit)
                    }
                } header: {
                    Text("Unités reconnues")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Séparez la valeur de son unité par un espace : 7,2 m/s². Combinez les unités avec des opérateurs sans espaces : kg*m/s². Utilisez K pour une température absolue.")
                        Text("Pour afficher un résultat dans une autre unité, ajoutez → et l’unité en fin de ligne : E → kWh. Les préfixes SI (k, m, µ…) s’ajoutent aux unités qui les acceptent.")
                        Text("Les lettres t, d, a et u ne sont pas des unités : elles restent libres comme noms de variables. Pour une durée, écrivez s, min, h, jour ou an.")
                    }
                }
            }
        }
        .overlay {
            if (kind == .constants && constants.isEmpty) || (kind == .units && units.isEmpty) {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle(picks ? "Insérer" : "Références")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Nom, symbole ou domaine")
        .focusesSearch(on: searchRequest)
        .navigationDestination(for: ConstantDefinition.self) { constant in
            ConstantDetailView(constant: constant, mode: mode)
        }
        .sensoryFeedback(.success, trigger: copies)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Référence", selection: $kind) {
                    ForEach(ReferenceKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if kind == .constants {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Domaine", selection: $category) {
                            Text("Tous les domaines").tag(Optional<ConstantCategory>.none)
                            ForEach(ConstantCategory.allCases) { category in
                                Text(category.title).tag(Optional(category))
                            }
                        }
                    } label: {
                        Label("Domaine", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private func constantsFooter(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Localizable.xcstrings provides the singular form.
            Text("\(count) constantes")
            if !picks {
                Text("Les valeurs de référence sont incluses dans l’application et disponibles hors ligne. Chaque constante précise sa nature et sa source.")
                Text("Les symboles respectent la casse : g et G représentent deux constantes différentes. Une variable déclarée a priorité sur une constante.")
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func constantRow(_ entry: ReferenceIndex.Entry) -> some View {
        let constant = entry.definition
        let label = VStack(alignment: .leading, spacing: 4) {
            Text(constant.name)
            Text("\(constant.symbol) = \(entry.valueText)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(MathSpeech.description(constant.symbol) ?? constant.symbol) égale \(entry.spokenValue)")
        }
        switch mode {
        case .pick(let insert):
            Button {
                insert(.name(constant.id))
                dismiss()
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityHint("Insère \(constant.id) dans la formule.")
        case .browse(let addToSheet):
            NavigationLink(value: constant) {
                label
            }
            .swipeActions(edge: .leading) {
                Button("Ajouter à la feuille", systemImage: "plus.circle") { addToSheet(constant.id, constant.name) }
                    .tint(.accentColor)
            }
            .contextMenu {
                Button("Ajouter à la feuille", systemImage: "plus.circle") { addToSheet(constant.id, constant.name) }
                Button("Copier la valeur", systemImage: "doc.on.doc") { copy(entry.valueText) }
                Button("Copier l’identifiant", systemImage: "textformat") { copy(constant.id) }
            }
        }
    }

    @ViewBuilder
    private func unitRow(_ unit: UnitDefinition) -> some View {
        let label = LabeledContent {
            Text(unit.symbol).font(.body.monospaced())
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(unit.name)
                Text(QuantityFormatter.string(unit.quantity, significantDigits: QuantityFormatter.preciseDigits))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(QuantityFormatter.spokenString(unit.quantity))
            }
        }
        switch mode {
        case .pick(let insert):
            Button {
                insert(.unit(unit.symbol))
                dismiss()
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityHint("Insère \(unit.symbol) dans la formule.")
        case .browse(let addToSheet):
            label
                .contextMenu {
                    Button("Ajouter à la feuille", systemImage: "plus.circle") { addToSheet(unit.symbol, unit.name) }
                    Button("Copier le symbole", systemImage: "doc.on.doc") { copy(unit.symbol) }
                }
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copies += 1
    }
}

/// Everything about one constant: its input name, aliases, value, nature and source.
struct ConstantDetailView: View {
    let constant: ConstantDefinition
    let mode: ReferenceMode

    var body: some View {
        let aliases = ConstantCatalog.aliases(for: constant)
        Form {
            Section {
                Text(constant.detail).foregroundStyle(.secondary)
                LabeledContent("Valeur", value: QuantityFormatter.string(constant.quantity, significantDigits: QuantityFormatter.preciseDigits))
                    .textSelection(.enabled)
                    .accessibilityValue(QuantityFormatter.spokenString(constant.quantity))
                LabeledContent("Saisie") {
                    Text(constant.id)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                if !aliases.isEmpty {
                    LabeledContent("Alias") {
                        Text(aliases.joined(separator: ", "))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
                LabeledContent("Nature", value: constant.nature.title)
                if let sourceURL = constant.sourceURL {
                    Link("Source : \(constant.sourceName)", destination: sourceURL)
                } else {
                    LabeledContent("Source", value: constant.sourceName)
                }
            }
        }
        .navigationTitle(constant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .browse(let addToSheet) = mode {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ajouter à la feuille", systemImage: "plus.circle") { addToSheet(constant.id, constant.name) }
                        .accessibilityLabel("Ajouter \(constant.name) à la feuille")
                }
            }
        }
    }
}
