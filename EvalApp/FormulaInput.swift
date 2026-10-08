import EvalCore
import Observation
import SwiftUI

/// Where the caret or selection is in a formula field. TextSelection needs
/// iOS 18; on iOS 17 an insertion goes to the end of the text. A plain class
/// keeps the iOS 18 type out of every view that only passes this value on.
/// Observable, so that a caret set from code reaches the field.
@Observable
final class FormulaSelectionState {
    private var storage: Any?

    @available(iOS 18, *)
    var selection: TextSelection? {
        get { storage as? TextSelection }
        set { storage = newValue }
    }

    /// Whether insertions land at the caret rather than at the end.
    static var tracksCaret: Bool {
        if #available(iOS 18, *) { true } else { false }
    }

    /// Puts the caret after the last character, where a field that opens with
    /// its text gets it, instead of leaving the choice to the system.
    func placeCaretAtEnd(of text: String) {
        if #available(iOS 18, *) {
            selection = TextSelection(insertionPoint: text.endIndex)
        }
    }

    /// Inserts the snippet over the selection of `text`, and moves the caret after it.
    func insert(_ snippet: FormulaInsertion.Snippet, into text: inout String) {
        var range = text.endIndex..<text.endIndex
        if #available(iOS 18, *), let selection, let selected = selectedRange(selection) {
            range = selected
        }
        let result = FormulaInsertion.insert(snippet, into: text, replacing: range)
        text = result.text
        if #available(iOS 18, *) {
            selection = TextSelection(insertionPoint: result.caret)
        }
    }

    @available(iOS 18, *)
    private func selectedRange(_ selection: TextSelection) -> Range<String.Index>? {
        switch selection.indices {
        case .selection(let range): range
        case .multiSelection(let ranges): ranges.ranges.first
        @unknown default: nil
        }
    }
}

/// A native text field that reports its selection when the system allows it.
struct FormulaTextField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let selection: FormulaSelectionState
    var axis: Axis = .horizontal

    var body: some View {
        if #available(iOS 18, *) {
            TextField(title, text: $text, selection: Binding(get: { selection.selection },
                                                             set: { selection.selection = $0 }),
                      axis: axis)
        } else {
            TextField(title, text: $text, axis: axis)
        }
    }
}

/// The keyboard bar of every field that takes a formula: operators within
/// reach, a menu of names, and the way out of the keyboard.
struct FormulaKeyboardToolbar: ToolbarContent {
    /// False where the caret is unknown, which leaves only the way out.
    var insertsSymbols = true
    var variableNames: [String] = []
    var insert: (FormulaInsertion.Snippet) -> Void = { _ in }
    var showReferences: (() -> Void)?
    let done: () -> Void

    var body: some ToolbarContent {
        if insertsSymbols {
            ToolbarItemGroup(placement: .keyboard) {
                Menu("Insérer", systemImage: "plus.circle") {
                    Section {
                        Button("Égal =") { insert(.operator("=")) }
                        Button("Diviser ÷") { insert(.operator("/")) }
                        Button("Puissance ^") { insert(.literal("^")) }
                        Button("Au carré ²") { insert(.literal("²")) }
                        Button("Au cube ³") { insert(.literal("³")) }
                        Button("Inverse ⁻¹") { insert(.literal("⁻¹")) }
                    }
                    Section {
                        Button("Racine carrée √( )") { insert(.function("sqrt")) }
                        Button("π") { insert(.name("π")) }
                        Button("Degrés (deg)") { insert(.unit("deg")) }
                    }
                    if !variableNames.isEmpty {
                        Section("Variables de la feuille") {
                            ForEach(variableNames, id: \.self) { name in
                                Button(name) { insert(.name(name)) }
                            }
                        }
                    }
                    if let showReferences {
                        Button("Constantes et unités…", systemImage: "books.vertical", action: showReferences)
                    }
                }
                .labelStyle(.iconOnly)
                // Only the most common keys: more would push « Terminé » out of the bar.
                key("+", .operator("+"), label: "Plus")
                key("−", .operator("-"), label: "Moins")
                key("×", .operator("*"), label: "Multiplier")
                key("( )", .parentheses, label: "Parenthèses")
            }
        }
        // Apart from the symbols, so that « Terminé » never goes into the overflow of the bar.
        ToolbarItem(placement: .keyboard) {
            Button("Terminé", action: done)
        }
    }

    private func key(_ title: String, _ snippet: FormulaInsertion.Snippet, label: LocalizedStringKey) -> some View {
        Button(title) { insert(snippet) }
            .accessibilityLabel(label)
    }
}
