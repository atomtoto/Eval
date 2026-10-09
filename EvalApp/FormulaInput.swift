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

/// The keys of the bar for the mathematical editor, which owns the editing state:
/// the editor of the line being edited registers what a key does.
final class MathKeyHandler {
    var apply: ((MathKey) -> Void)?
}

/// What the keyboard bar of a line edited in place does. Each field carries its
/// own bar, so that the keyboard keeps one when Return moves the focus to a new line.
struct LineKeyboard {
    /// Where the mathematical editor of the edited line lets the bar reach it.
    var mathKeys = MathKeyHandler()
    var variableNames: [String] = []
    var insert: (FormulaInsertion.Snippet) -> Void = { _ in }
    var showReferences: () -> Void = {}
    var done: () -> Void = {}
}

/// A line of the sheet edited in place: a native text field that grows with its
/// text. A Return reaches the binding as a line break, which the sheet turns
/// into a new line.
struct LineTextField: View {
    let lineID: UUID
    @Binding var text: String
    let selection: FormulaSelectionState
    let focus: FocusState<UUID?>.Binding
    let keyboard: LineKeyboard

    var body: some View {
        FormulaTextField(title: "Nouvelle ligne", text: $text, selection: selection, axis: .vertical)
            .font(.body.monospaced())
            .lineLimit(1...8)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.return)
            .focused(focus, equals: lineID)
            .accessibilityLabel("Ligne en cours de modification")
            .accessibilityHint("La touche Retour valide la ligne et en crée une nouvelle en dessous.")
            .task {
                // The field takes the focus once it exists, then the caret goes to the end.
                if focus.wrappedValue != lineID { focus.wrappedValue = lineID }
                try? await Task.sleep(for: .milliseconds(150))
                selection.placeCaretAtEnd(of: text)
            }
    }
}

/// The keys of the bar for a formula typed as text: a menu of names and structures, then
/// the operators within reach. Only the most common keys: more would push « Terminé » out.
struct FormulaKeys: View {
    var variableNames: [String] = []
    var insert: (FormulaInsertion.Snippet) -> Void = { _ in }
    var showReferences: (() -> Void)?

    var body: some View {
        Menu("Insérer", systemImage: "plus.circle") {
            Section {
                // Templates wrap the selection: a selected `a + b` becomes the numerator.
                Button("Fraction", systemImage: "divide") { insert(.fraction) }
                Button("Puissance", systemImage: "textformat.superscript") { insert(.power) }
                Button("Racine", systemImage: "x.squareroot") { insert(.function("sqrt")) }
            }
            Section {
                Button("Égal =") { insert(.operator("=")) }
                Button("Diviser ÷") { insert(.operator("/")) }
                Button("Exposant ^") { insert(.literal("^")) }
                Button("Au carré ²") { insert(.literal("²")) }
                Button("Au cube ³") { insert(.literal("³")) }
                Button("Inverse ⁻¹") { insert(.literal("⁻¹")) }
            }
            Section {
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
        key("+", .operator("+"), label: "Plus")
        key("−", .operator("-"), label: "Moins")
        key("×", .operator("*"), label: "Multiplier")
        key("( )", .parentheses, label: "Parenthèses")
    }

    private func key(_ title: String, _ snippet: FormulaInsertion.Snippet, label: LocalizedStringKey) -> some View {
        Button(title) { insert(snippet) }
            .accessibilityLabel(label)
    }
}

/// The keyboard bar of every field that takes a formula outside a sheet’s lines
/// (the text editor of a whole sheet): the keys, and the way out of the keyboard.
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
                FormulaKeys(variableNames: variableNames, insert: insert, showReferences: showReferences)
                    .tint(.primary)
            }
        }
        // Apart from the symbols, so that « Terminé » never goes into the overflow of the bar.
        ToolbarItem(placement: .keyboard) {
            Button("Terminé", action: done)
                .tint(.primary)
        }
    }
}

/// The bar of a sheet’s line being edited. The system bar of the keyboard sits against
/// the keyboard and cannot be moved, so the sheet shows its own above it, in a safe-area
/// inset: it floats a little over the keyboard, which keeps avoiding the list. It holds
/// the same keys as the keyboard toolbar, and « Terminé » is always visible.
struct LineKeyboardBar: View {
    let mode: FormulaInputMode
    let keyboard: LineKeyboard

    var body: some View {
        HStack(spacing: 0) {
            switch mode {
            case .text:
                if FormulaSelectionState.tracksCaret {
                    FormulaKeys(variableNames: keyboard.variableNames, insert: keyboard.insert,
                                showReferences: keyboard.showReferences)
                        .frame(maxWidth: .infinity)
                }
            case .math:
                MathKeys(variableNames: keyboard.variableNames,
                         apply: { keyboard.mathKeys.apply?($0) },
                         showReferences: keyboard.showReferences)
                    .frame(maxWidth: .infinity)
            }
            Button("Terminé", action: keyboard.done)
                .fontWeight(.semibold)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 12)
        }
        .buttonStyle(.borderless)
        // The keys of the bar are system controls, not accented content.
        .tint(.primary)
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .keyboardBarMaterial()
        .padding(.horizontal, 16)
        // A comfortable gap above the keyboard.
        .padding(.bottom, 10)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private extension View {
    /// Liquid Glass from iOS 26, a system material before.
    @ViewBuilder
    func keyboardBarMaterial() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}
