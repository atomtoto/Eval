import EvalCore
import SwiftUI

struct ReferenceView: View {
    let insert: (String) -> Void
    @State private var search = ""
    @State private var selection = ReferenceKind.constants

    private enum ReferenceKind: String, CaseIterable, Identifiable {
        case constants = "Constantes"
        case units = "Unités"
        var id: String { rawValue }
    }

    private func matches(_ text: String) -> Bool {
        search.isEmpty || text.localizedStandardContains(search)
    }

    private var filteredConstants: [ConstantDefinition] {
        ConstantCatalog.all.filter { matches("\($0.symbol) \($0.id) \($0.name)") }
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
                        if filteredConstants.isEmpty { ContentUnavailableView.search(text: search) }
                        ForEach(filteredConstants) { constant in
                            DisclosureGroup {
                                Text(constant.detail).foregroundStyle(.secondary)
                                LabeledContent("Valeur", value: QuantityFormatter.string(constant.quantity))
                                    .textSelection(.enabled)
                                LabeledContent("Nature", value: constant.isExact ? "Valeur exacte" : "Valeur de référence")
                                Button("Ajouter \(constant.symbol) à la feuille", systemImage: "plus.circle") {
                                    insert(constant.symbol)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(constant.name)
                                    Text("\(constant.symbol) = \(QuantityFormatter.string(constant.quantity))")
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Valeurs physiques et mathématiques")
                    } footer: {
                        Text("Les symboles respectent la casse : g et G représentent deux constantes différentes. Une variable déclarée a priorité sur une constante.")
                    }
                    Section {
                        Link("Constantes de référence du NIST", destination: URL(string: "https://physics.nist.gov/cuu/Constants/")!)
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
            .searchable(text: $search, prompt: "Nom ou symbole")
        }
    }
}
