import EvalCore
import SwiftUI

struct NotebookView: View {
    @ObservedObject var notebook: NotebookStore
    @FocusState private var isEditing: Bool
    @State private var showsHelp = false
    @State private var pendingExample: NotebookExample?
    @State private var showsReplacementConfirmation = false
    @State private var showsClearConfirmation = false

    private var resultLines: [EvaluatedLine] {
        notebook.evaluation.lines.filter { $0.kind != .empty && $0.kind != .comment }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextEditor(text: $notebook.source)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 210)
                        .focused($isEditing)
                        .accessibilityLabel("Feuille de formules")
                        .accessibilityHint("Une formule ou une déclaration par ligne. Exemple : a égale 7 virgule 2 mètres par seconde carrée.")
                } header: {
                    Text("Feuille de calcul")
                } footer: {
                    Text("Une ligne par formule ou variable. Les déclarations peuvent être placées au-dessus ou au-dessous des formules. La feuille est enregistrée automatiquement.")
                }

                Section {
                    if resultLines.isEmpty {
                        ContentUnavailableView {
                            Label("Votre premier calcul", systemImage: "function")
                        } description: {
                            Text("Saisissez une formule, puis donnez une valeur et une unité à ses variables.")
                        } actions: {
                            Button("Essayer un exemple") {
                                notebook.source = NotebookExample.freeFall.source
                            }
                        }
                    } else {
                        ForEach(resultLines) { line in
                            ResultRow(line: line)
                        }
                    }
                } header: {
                    HStack {
                        Text("Résultats")
                        if notebook.isEvaluating {
                            ProgressView().controlSize(.mini)
                                .accessibilityLabel("Calcul en cours")
                        }
                    }
                } footer: {
                    Text("Les résultats sont exprimés en unités SI. Sans unité, une valeur est considérée comme sans dimension.")
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
                        Menu("Charger un exemple", systemImage: "text.book.closed") {
                            ForEach(NotebookExample.allCases) { example in
                                Button(example.title) {
                                    pendingExample = example
                                    if notebook.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        notebook.source = example.source
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
            .confirmationDialog("Remplacer la feuille par cet exemple ?", isPresented: $showsReplacementConfirmation, titleVisibility: .visible) {
                Button("Charger l’exemple") {
                    if let example = pendingExample { notebook.source = example.source }
                }
            } message: {
                Text("Le contenu actuel de la feuille sera remplacé.")
            }
            .confirmationDialog("Effacer la feuille ?", isPresented: $showsClearConfirmation, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { notebook.source = "" }
            }
        }
    }
}

private struct ResultRow: View {
    let line: EvaluatedLine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(line.id + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Ligne \(line.id + 1)")
                Text(line.source)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
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
