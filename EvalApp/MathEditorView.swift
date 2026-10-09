import EvalCore
import SwiftUI

/// A line edited in its mathematical form, for the setting « Écriture mathématique »:
/// fractions, exponents and roots are typed where they are drawn. The user asked for
/// this editor; SwiftUI has no native control for 2D math, so it stays a small
/// composition of native text, stacks and a hidden native text field.
///
/// The keyboard types into a hidden `TextField` that starts with a run of invisible
/// characters: what is added to its text goes to the editing tree, each character
/// removed is a backspace, a line break is a Return. Every change writes the line, so its value
/// stays up to date; a Return writes a line break, which the sheet turns into a new line.
struct MathEditorView: View {
    @Binding var source: String
    let lineID: UUID
    let focus: FocusState<UUID?>.Binding
    let keyboard: LineKeyboard

    @State private var state: MathEditorState
    /// The text last read from or written to the line: another value comes from
    /// elsewhere, such as a constant inserted from the catalog.
    @State private var syncedSource: String
    @State private var buffer = Self.filler
    /// The text of the hidden field that the editing tree has taken into account. `onChange` of the
    /// field fires after the action that follows a key, so an action first takes the pending text
    /// (see `flushBuffer()`): the order of the keys is kept.
    @State private var processed = Self.filler
    @ScaledMetric(relativeTo: .title3) private var pointSize = 21.0

    /// The invisible characters of the hidden field, before its caret: deleting one is a backspace.
    private static let sentinel = "\u{200B}"
    private static let filler = String(repeating: sentinel, count: 64)

    init(source: Binding<String>, lineID: UUID, focus: FocusState<UUID?>.Binding, keyboard: LineKeyboard) {
        _source = source
        self.lineID = lineID
        self.focus = focus
        self.keyboard = keyboard
        _state = State(initialValue: Self.editingState(source.wrappedValue))
        _syncedSource = State(initialValue: source.wrappedValue)
    }

    /// A note alone on its line is edited as plain symbols, like the rest of a line.
    private static func editingState(_ text: String) -> MathEditorState {
        let state = MathEditorState(source: text)
        guard state.root.isEmpty, !state.comment.isEmpty else { return state }
        return MathEditorState(root: MathRow(text: state.comment))
    }

    private var isFocused: Bool { focus.wrappedValue == lineID }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    MathRowView(row: state.root, path: [], pointSize: pointSize,
                                cursor: isFocused ? state.cursor : nil, place: place)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onChange(of: state.cursor) {
                    proxy.scrollTo(MathCaret.id)
                }
            }
            if !state.comment.isEmpty {
                Text(state.comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        // Beside the formula, the caret goes to the end of the line.
        .onTapGesture { place(MathCursor(offset: state.root.items.count)) }
        .background(alignment: .topLeading) { inputField }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(cursorDescription)
        .accessibilityHint("La touche Retour valide la ligne et en crée une nouvelle en dessous.")
        .accessibilityAction { focus.wrappedValue = lineID }
        .accessibilityActions {
            ForEach(MathKey.structureKeys, id: \.self) { key in
                Button(key.title) { apply(key) }
            }
        }
        .onChange(of: source) { _, newValue in adopt(newValue) }
    }

    // MARK: Keyboard

    /// The field that has the keyboard, invisible: the formula above shows what is typed.
    private var inputField: some View {
        TextField("", text: $buffer, axis: .vertical)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused(focus, equals: lineID)
            .onChange(of: buffer) { _, new in if new != processed { receive(new) } }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                switch press.key {
                case .leftArrow: apply(.left)
                case .rightArrow: apply(.right)
                case .upArrow: apply(.up)
                default: apply(.down)
                }
                return .handled
            }
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                // The bar of the sheet reaches this editor for the keys of the structures.
                keyboard.mathKeys.apply = apply
                // The field takes the focus once it exists, like the text field of a line.
                if focus.wrappedValue != lineID { focus.wrappedValue = lineID }
            }
    }

    /// What the hidden field received: typed text, backspaces or a Return. The field
    /// keeps its text, so that it never lags behind a text set from here while keys
    /// arrive; only an almost empty or long text is replaced, between two keys.
    private func receive(_ new: String) {
        let before = Array(processed), after = Array(new)
        processed = new
        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < before.count - prefix, suffix < after.count - prefix,
              before[before.count - 1 - suffix] == after[after.count - 1 - suffix] { suffix += 1 }
        // A character removed, typed or invisible, is a backspace; a replacement, such as
        // a suggestion of the keyboard, deletes the word it replaces.
        for _ in 0..<(before.count - prefix - suffix) { state.deleteBackward() }
        let typed = String(after[prefix..<(after.count - suffix)]).replacingOccurrences(of: Self.sentinel, with: "")
        if let lineBreak = typed.firstIndex(where: \.isNewline) {
            state.insert(String(typed[..<lineBreak]))
            // The sheet validates the line and edits a new one below; pasted lines follow it.
            let text = state.source + typed[lineBreak...]
            syncedSource = text
            source = text
            return
        }
        state.insert(typed)
        write()
        if after.count < 16 || after.count > 256 {
            Task { @MainActor in
                flushBuffer()
                resetField()
            }
        }
    }

    /// Takes the text that the field received and `onChange` has not delivered yet.
    private func flushBuffer() {
        if buffer != processed { receive(buffer) }
    }

    private func resetField() {
        processed = Self.filler
        buffer = Self.filler
    }

    /// The line follows every change of the formula, so its value is computed as it is typed.
    private func write() {
        let text = state.source
        syncedSource = text
        if source != text { source = text }
    }

    /// A text changed from elsewhere. Text added at the end, such as a name from the
    /// catalog, goes to the caret; any other change is read again.
    private func adopt(_ text: String) {
        guard text != syncedSource else { return }
        let isAtEnd = state.cursor == MathCursor(offset: state.root.items.count)
        if !isAtEnd, state.comment.isEmpty, text.hasPrefix(syncedSource) {
            state.insert(String(text.dropFirst(syncedSource.count)))
            write()
        } else {
            state = Self.editingState(text)
            syncedSource = text
        }
    }

    private func place(_ cursor: MathCursor) {
        flushBuffer()
        state.setCursor(cursor)
        clearField()
        if !isFocused { focus.wrappedValue = lineID }
    }

    /// After a move or a key of the bar, the keyboard’s suggestions no longer
    /// continue the text of the hidden field: it starts again.
    private func clearField() {
        guard buffer != Self.filler || processed != Self.filler else { return }
        resetField()
    }

    fileprivate func apply(_ key: MathKey) {
        flushBuffer()
        switch key {
        case .fraction: state.insertFraction()
        case .power: state.insertPower()
        case .radical: state.insertRadical()
        case .root: state.insertRoot()
        case .left: state.moveLeft()
        case .right: state.moveRight()
        case .up: state.moveUp()
        case .down: state.moveDown()
        case .text(let text): state.insert(text)
        case .name(let name): insertName(name)
        }
        clearField()
        write()
    }

    /// A name never fuses with its neighbours: after an operand it is multiplied.
    private func insertName(_ name: String) {
        let items = state.cursorRow.items, offset = state.cursor.offset
        var text = name
        if offset > 0 {
            switch items[offset - 1] {
            case .symbol(let character):
                if character.isLetter || character.isNumber || character == "_" || character == ")" { text = " * " + text }
            default:
                text = " * " + text
            }
        }
        if offset < items.count, case .symbol(let character) = items[offset], character.isLetter || character.isNumber {
            text += " "
        }
        state.insert(text)
    }

    // MARK: Accessibility

    private var accessibilityLabel: String {
        let text = state.source
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Ligne vide") }
        return MathSpeech.description(text) ?? text
    }

    /// Where the caret is, simply: in which part of a structure, or where on the line.
    private var cursorDescription: String {
        let cursor = state.cursor, row = state.cursorRow
        guard let slot = cursor.path.last?.slot else {
            if row.isEmpty { return "" }
            if cursor.offset == 0 { return String(localized: "Début de ligne") }
            if cursor.offset == row.items.count { return String(localized: "Fin de ligne") }
            if case .symbol(let character) = row.items[cursor.offset - 1], !character.isWhitespace {
                return String(localized: "Après « \(String(character)) »")
            }
            return String(localized: "Dans la ligne")
        }
        let place: String = switch slot {
        case .numerator: String(localized: "Au numérateur")
        case .denominator: String(localized: "Au dénominateur")
        case .exponent: String(localized: "En exposant")
        case .radicand: String(localized: "Sous la racine")
        case .index: String(localized: "Dans l’indice de la racine")
        }
        if row.isEmpty { return String(localized: "\(place), vide") }
        if cursor.offset == row.items.count { return String(localized: "\(place), à la fin") }
        return place
    }
}

/// What the keys of the bar, and the matching accessibility actions, do.
enum MathKey: Hashable {
    case fraction, power, radical, root, left, right, up, down
    case text(String)
    case name(String)

    static let structureKeys: [MathKey] = [.fraction, .power, .radical, .root, .left, .right, .up, .down]

    var title: LocalizedStringKey {
        switch self {
        case .fraction: "Fraction"
        case .power: "Puissance"
        case .radical: "Racine carrée"
        case .root: "Racine n-ième"
        case .left: "Gauche"
        case .right: "Droite"
        case .up: "Monter"
        case .down: "Descendre"
        case .text(let text): "\(text)"
        case .name(let name): "\(name)"
        }
    }
}

/// The keys of the bar for the mathematical editor: the structures, the caret moves
/// most used, and a menu for the rest. « Terminé » is not among them, so that it is
/// always visible.
struct MathKeys: View {
    let variableNames: [String]
    let apply: (MathKey) -> Void
    let showReferences: () -> Void

    var body: some View {
        Menu("Insérer", systemImage: "plus.circle") {
            Section {
                Button("Fraction", systemImage: "divide") { apply(.fraction) }
                Button("Racine n-ième ⁿ√") { apply(.root) }
                Button("Au carré ²") { apply(.text("²")) }
                Button("Inverse ⁻¹") { apply(.text("⁻¹")) }
            }
            Section {
                Button("Monter", systemImage: "arrow.up") { apply(.up) }
                Button("Descendre", systemImage: "arrow.down") { apply(.down) }
            }
            Section {
                Button("Égal =") { apply(.text(" = ")) }
                Button("Multiplier ×") { apply(.text(" * ")) }
                Button("π") { apply(.name("π")) }
                Button("Degrés (deg)") { apply(.text(" deg")) }
            }
            if !variableNames.isEmpty {
                Section("Variables de la feuille") {
                    ForEach(variableNames, id: \.self) { name in
                        Button(name) { apply(.name(name)) }
                    }
                }
            }
            Button("Constantes et unités…", systemImage: "books.vertical", action: showReferences)
        }
        .labelStyle(.iconOnly)
        // The fraction is in the menu: the / of the keyboard makes one too.
        key(.power, systemImage: "textformat.superscript")
        key(.radical, systemImage: "x.squareroot")
        key(.left, systemImage: "chevron.left")
        key(.right, systemImage: "chevron.right")
    }

    private func key(_ key: MathKey, systemImage: String) -> some View {
        Button { apply(key) } label: {
            Label(key.title, systemImage: systemImage)
        }
        .labelStyle(.iconOnly)
    }
}

// MARK: - Drawing

/// A row of the editing tree, drawn like `FormulaContent`: serif symbols on the
/// math axis, with the caret between them. A tap on a symbol puts the caret on
/// the nearer side of it; a tap elsewhere in the row, at its end.
private struct MathRowView: View {
    let row: MathRow
    let path: [MathPathStep]
    let pointSize: Double
    /// The caret, drawn where it is, or nil while the line has no keyboard.
    let cursor: MathCursor?
    let place: (MathCursor) -> Void

    private var caretOffset: Int? {
        cursor?.path == path ? cursor?.offset : nil
    }

    var body: some View {
        HStack(alignment: .mathAxis, spacing: 0) {
            if row.isEmpty {
                emptyRow
            } else {
                ForEach(row.items.indices, id: \.self) { index in
                    if caretOffset == index { MathCaret(pointSize: pointSize) }
                    item(at: index)
                }
                if caretOffset == row.items.count { MathCaret(pointSize: pointSize) }
            }
        }
        .contentShape(.rect)
        .onTapGesture { place(MathCursor(path: path, offset: row.items.count)) }
    }

    /// An empty line shows its placeholder; an empty part of a structure, a dotted box.
    @ViewBuilder
    private var emptyRow: some View {
        if path.isEmpty {
            if caretOffset != nil { MathCaret(pointSize: pointSize) }
            Text("Nouvelle ligne")
                .font(.system(size: pointSize, design: .serif))
                .foregroundStyle(.tertiary)
                .alignmentGuide(.mathAxis) { $0[.firstTextBaseline] - pointSize * 0.25 }
        } else {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: pointSize * 0.55, height: pointSize * 0.75)
                .overlay(alignment: .leading) {
                    if caretOffset != nil { MathCaret(pointSize: pointSize).padding(.leading, 2) }
                }
                .padding(.horizontal, 1)
                .alignmentGuide(.mathAxis) { $0.height / 2 + pointSize * 0.1 }
        }
    }

    // Type erasure breaks the recursive view type, as in `FormulaContent`.
    private func item(at index: Int) -> AnyView {
        switch row.items[index] {
        case .symbol(let character):
            return AnyView(symbol(character, at: index))
        case .fraction(let numerator, let denominator):
            return AnyView(VStack(spacing: pointSize * 0.12) {
                slot(numerator, index, .numerator, scale: 0.9)
                    .padding(.horizontal, pointSize * 0.22)
                // The bar is the axis of the fraction.
                Rectangle()
                    .frame(height: 1)
                    .alignmentGuide(.mathAxis) { $0[VerticalAlignment.center] }
                slot(denominator, index, .denominator, scale: 0.9)
                    .padding(.horizontal, pointSize * 0.22)
            }
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, pointSize * 0.1)
            .contentShape(.rect)
            .onTapGesture { place(MathCursor(path: path, offset: index + 1)) })
        case .superscript(let exponent):
            // Raised by its own alignment, as an exponent of `FormulaContent`.
            return AnyView(slot(exponent, index, .exponent, scale: 0.65)
                .padding(.leading, pointSize * 0.06)
                .alignmentGuide(.mathAxis) { $0.height + pointSize * 0.15 })
        case .radical(let radicand):
            return AnyView(radical(slot(radicand, index, .radicand, scale: 1), at: index))
        case .root(let rootIndex, let radicand):
            return AnyView(radical(slot(radicand, index, .radicand, scale: 1), at: index)
                .overlay(alignment: .topLeading) {
                    slot(rootIndex, index, .index, scale: 0.55)
                        .fixedSize()
                        .padding(.leading, pointSize * 0.04)
                })
        }
    }

    private func slot(_ row: MathRow, _ index: Int, _ slot: MathSlot, scale: Double) -> MathRowView {
        MathRowView(row: row, path: path + [MathPathStep(item: index, slot: slot)],
                    pointSize: pointSize * scale, cursor: cursor, place: place)
    }

    /// The sign is drawn behind the radicand, so it stretches with it.
    private func radical(_ radicand: MathRowView, at index: Int) -> some View {
        radicand
            .padding(.leading, pointSize * 0.75)
            .padding(.trailing, pointSize * 0.1)
            .padding(.top, 3)
            .background {
                RadicalSign(hookWidth: pointSize * 0.7)
                    .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }
            .contentShape(.rect)
            .onTapGesture { place(MathCursor(path: path, offset: index + 1)) }
    }

    /// A typed character, with the signs and spacing of the rendered formula: · for *,
    /// − for -, room around the operators, so that a typed space adds little.
    private func symbol(_ character: Character, at index: Int) -> some View {
        let shown: String = switch character {
        case "*": "·"
        case "-": "−"
        default: String(character)
        }
        let size = character == " " ? pointSize * 0.5 : pointSize
        return Text(verbatim: shown)
            .font(.system(size: size, design: .serif))
            .padding(.horizontal, "=+-*×÷→<>".contains(character) ? pointSize * 0.15 : 0)
            .alignmentGuide(.mathAxis) { $0[.firstTextBaseline] - size * 0.25 }
            .overlay {
                // Each half of the symbol puts the caret on its side.
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { place(MathCursor(path: path, offset: index)) }
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { place(MathCursor(path: path, offset: index + 1)) }
                }
            }
    }
}

/// The insertion point: a tinted bar that blinks, steady with Reduce Motion. It
/// takes no width, so the formula does not move under it.
private struct MathCaret: View {
    let pointSize: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(width: 0, height: pointSize * 1.15)
            .overlay {
                Rectangle()
                    .fill(.tint)
                    .frame(width: 2)
                    .phaseAnimator(reduceMotion ? [true] : [true, false]) { bar, isVisible in
                        bar.opacity(isVisible ? 1 : 0)
                    } animation: { isVisible in
                        .easeInOut(duration: 0.15).delay(isVisible ? 0.35 : 0.5)
                    }
            }
            .alignmentGuide(.mathAxis) { $0.height / 2 + pointSize * 0.1 }
            .id(Self.id)
    }

    static let id = "caret"
}
