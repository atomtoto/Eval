import EvalCore
import SwiftUI

struct ReferenceView: View {
    let insert: (String) -> Void
    @State private var search = ""
    @State private var selection = ReferenceKind.constants
    @State private var category: ConstantCategory?

    private enum ReferenceKind: String, CaseIterable, Identifiable {
        case constants = "Constantes"
        case units = "Unités"
        var id: String { rawValue }
    }

    private func matches(_ text: String) -> Bool {
        search.isEmpty || text.localizedStandardContains(search)
    }

    private var filteredConstants: [ConstantDefinition] {
        ConstantCatalog.all.filter {
            (category == nil || $0.category == category)
                && matches("\($0.symbol) \($0.id) \($0.name) \($0.detail) \($0.category.title) \($0.sourceName) \(ConstantCatalog.aliases(for: $0).joined(separator: " "))")
        }
    }

    private var visibleCategories: [ConstantCategory] {
        ConstantCategory.allCases.filter { category in
            filteredConstants.contains { $0.category == category }
        }
    }

    private var filteredUnits: [UnitDefinition] {
        UnitCatalog.all.filter { matches("\($0.symbol) \($0.name)") }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Référence", selection: $selection) {
                        ForEach(ReferenceKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if selection == .constants {
                    Section {
                        Picker("Domaine", selection: $category) {
                            Text("Tous les domaines").tag(Optional<ConstantCategory>.none)
                            ForEach(ConstantCategory.allCases) { category in
                                Text(category.title).tag(Optional(category))
                            }
                        }
                        .pickerStyle(.menu)
                    } footer: {
                        Text(filteredConstants.count == 1
                             ? "1 constante"
                             : "\(filteredConstants.count) constantes")
                    }

                    if filteredConstants.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }

                    ForEach(visibleCategories) { category in
                        Section(category.title) {
                            ForEach(filteredConstants.filter { $0.category == category }) { constant in
                                constantRow(constant)
                            }
                        }
                    }

                    Section {
                        Text("Les valeurs de référence sont incluses dans l’application et disponibles hors ligne. Chaque constante précise sa nature et sa source.")
                            .foregroundStyle(.secondary)
                        Text("Les symboles respectent la casse : g et G représentent deux constantes différentes. Une variable déclarée a priorité sur une constante.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        if filteredUnits.isEmpty { ContentUnavailableView.search(text: search) }
                        ForEach(filteredUnits) { unit in
                            LabeledContent {
                                Text(unit.symbol).font(.body.monospaced())
                                    .textSelection(.enabled)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(unit.name)
                                    Text(QuantityFormatter.string(unit.quantity))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Unités reconnues")
                    } footer: {
                        Text("Séparez la valeur de son unité par un espace : 7,2 m/s². Combinez les unités avec des opérateurs sans espaces : kg*m/s². Utilisez K pour une température absolue.")
                    }
                }
            }
            .navigationTitle("Références")
            .searchable(text: $search, prompt: "Nom, symbole ou domaine")
        }
    }

    private func constantRow(_ constant: ConstantDefinition) -> some View {
        let aliases = ConstantCatalog.aliases(for: constant)
        return DisclosureGroup {
            Text(constant.detail).foregroundStyle(.secondary)
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
            LabeledContent("Valeur", value: QuantityFormatter.string(constant.quantity))
                .textSelection(.enabled)
            LabeledContent("Nature", value: constant.nature.title)
            if let sourceURL = constant.sourceURL {
                Link("Source : \(constant.sourceName)", destination: sourceURL)
            } else {
                LabeledContent("Source", value: constant.sourceName)
            }
            Button("Ajouter à la feuille", systemImage: "plus.circle") {
                insert(constant.id)
            }
            .accessibilityLabel("Ajouter \(constant.name) à la feuille")
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(constant.name)
                Text("\(constant.symbol) = \(QuantityFormatter.string(constant.quantity))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
