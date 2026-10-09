import EvalCore
import SwiftUI
import UIKit

/// Example sheets grouped by domain, as nested native menus.
struct ExampleMenuContent: View {
    let choose: (ExampleSheet) -> Void

    var body: some View {
        ForEach(ExampleDomain.allCases) { domain in
            Menu(domain.title) {
                ForEach(ExampleLibrary.examples(in: domain)) { example in
                    Button(example.title) { choose(example) }
                }
            }
        }
    }
}

/// « Afficher en »: the units a result can be shown in, and SI to remove the arrow.
/// Choosing one rewrites the line with `→`, so the choice is part of the sheet.
struct DisplayUnitMenu: View {
    /// The last evaluation of the line.
    let line: EvaluatedLine?
    /// The line as it is now; the menu waits for the evaluation of this text.
    let source: String
    let choose: (String?) -> Void

    var body: some View {
        if let options = Self.options(line: line, source: source) {
            Menu("Afficher en", systemImage: "arrow.left.arrow.right") {
                Picker("Afficher en", selection: Binding(get: { options.current }, set: { choose($0) })) {
                    Text("Unités SI").tag(String?.none)
                    ForEach(options.symbols, id: \.self) { symbol in
                        Text(symbol).tag(Optional(symbol))
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }

    /// The units a line can be shown in, nil while it has no value to convert.
    static func options(line: EvaluatedLine?, source: String) -> (current: String?, symbols: [String])? {
        guard let line, line.source == source, line.status == .success, line.kind != .equation,
              let quantity = line.quantity else { return nil }
        let current = line.displayUnit?.symbol
        let symbols = symbols(for: quantity.dimension, current: current)
        return symbols.isEmpty ? nil : (current, symbols)
    }
}

/// The same choices as `DisplayUnitMenu`, as VoiceOver and Voice Control actions.
struct DisplayUnitActions: View {
    let line: EvaluatedLine?
    let source: String
    let choose: (String?) -> Void

    var body: some View {
        if let options = DisplayUnitMenu.options(line: line, source: source) {
            ForEach(options.symbols.filter { $0 != options.current }, id: \.self) { symbol in
                Button("Afficher en \(symbol)") { choose(symbol) }
            }
            if options.current != nil {
                Button("Afficher en unités SI") { choose(nil) }
            }
        }
    }
}

extension DisplayUnitMenu {
    /// The suggestions for a dimension, with the unit already chosen when it is not among them.
    static func symbols(for dimension: EvalCore.Dimension, current: String?) -> [String] {
        var symbols = UnitCatalog.displaySuggestions(compatibleWith: dimension)
        if let current, !symbols.contains(current) { symbols.insert(current, at: 0) }
        return symbols
    }
}

/// A request to plot one result against one ruler variable.
struct PlotRequest: Identifiable {
    let id = UUID()
    let resultLineID: UUID
    let variableLineID: UUID
}

/// « Tracer en fonction de »: the adjustable variables a computed line can be plotted against.
struct PlotMenu: View {
    let notebook: NotebookStore
    let lineID: UUID
    let source: String
    let plot: (PlotRequest) -> Void

    var body: some View {
        let line = notebook.result(for: lineID)
        let variables = notebook.plotVariables(for: lineID)
        if let line, line.source == source, line.status == .success, line.quantity != nil,
           line.kind == .expression || line.kind == .definition, !variables.isEmpty {
            Menu("Tracer en fonction de", systemImage: "chart.xyaxis.line") {
                ForEach(variables) { item in
                    Button(item.variable.name) {
                        plot(PlotRequest(resultLineID: lineID, variableLineID: item.id))
                    }
                }
            }
        }
    }
}

/// Copy and share actions for the value of a line, for a context menu.
/// Values are copied as displayed, in SI or in the unit chosen with →, and paste back as valid input.
struct ResultCopyItems: View {
    let source: String
    let line: EvaluatedLine?
    /// Incremented on every copy, to trigger haptic feedback in the caller.
    @Binding var copies: Int

    var body: some View {
        if let value = line?.formattedValue {
            ResultCopyButtons(source: source, line: line, copies: $copies)
            ShareLink(item: ResultText.line(source: source, value: value), preview: SharePreview("Résultat Eval")) {
                Label("Partager le résultat", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// « Copier la valeur » and « Copier la ligne », for menus and accessibility actions.
struct ResultCopyButtons: View {
    let source: String
    let line: EvaluatedLine?
    @Binding var copies: Int

    var body: some View {
        if let value = line?.formattedValue {
            Button("Copier la valeur", systemImage: "doc.on.doc") { copy(value) }
            Button("Copier la ligne", systemImage: "text.alignleft") {
                copy(ResultText.line(source: source, value: value))
            }
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copies += 1
    }
}
