import EvalCore
import Foundation

/// A row of the math editor: the items between two places of the cursor.
public struct MathEditRow: Hashable, Sendable {
    public let items: [MathEditItem]
}

/// An item of a row: a symbol, or a structure with its rows (`slots`).
public struct MathEditItem: Hashable, Sendable {
    /// `symbol`, `fraction`, `power`, `radical` or `root`.
    public let kind: String
    /// The character of a symbol; empty for a structure.
    public let text: String
    /// A fraction's numerator and denominator, a power's exponent, a radical's
    /// radicand, a root's index and radicand.
    public let slots: [MathEditRow]
}

/// The line edited in mathematical notation (iOS `MathEditorView`, over EvalCore's
/// `MathEditorState`). A place of the cursor is a path, pairs of an item index and
/// a slot index from the outer row inward, and an offset in the innermost row.
public final class MathLineEditor {
    private var state: MathEditorState

    /// A note alone on its line is edited as plain symbols, like the rest of a line.
    public init(source: String) {
        let state = MathEditorState(source: source)
        self.state = state.root.isEmpty && !state.comment.isEmpty ? MathEditorState(root: MathRow(text: state.comment)) : state
    }

    /// The line as text, the formula followed by its comment.
    public var source: String { state.source }
    public var root: MathEditRow { Self.row(state.root) }
    public var cursorPath: [Int] {
        var row = state.root
        var path: [Int] = []
        for step in state.cursor.path {
            let item = row.items[step.item]
            path += [step.item, item.slots.firstIndex(of: step.slot) ?? 0]
            row = item.row(step.slot) ?? row
        }
        return path
    }
    public var cursorOffset: Int { state.cursor.offset }
    /// The comment kept out of the formula, shown under it.
    public var comment: String { state.comment }

    /// Types text at the cursor: `/` makes a fraction, `^` an exponent, `√` a root.
    public func type(_ text: String) { state.insert(text) }

    public func deleteBackward() { state.deleteBackward() }

    /// A name never fuses with its neighbours: after an operand it is multiplied.
    public func insertName(_ name: String) {
        let items = state.cursorRow.items, offset = state.cursor.offset
        var text = name
        if offset > 0 {
            if case .symbol(let character) = items[offset - 1] {
                if character.isLetter || character.isNumber || character == "_" || character == ")" { text = " * " + text }
            } else {
                text = " * " + text
            }
        }
        if offset < items.count, case .symbol(let character) = items[offset], character.isLetter || character.isNumber {
            text += " "
        }
        state.insert(text)
    }

    /// A key of the bar or the keyboard: `fraction`, `power`, `radical`, `root`,
    /// `left`, `right`, `up`, `down`, `start` or `end`. Returns false when it did nothing.
    @discardableResult
    public func key(_ name: String) -> Bool {
        switch name {
        case "fraction": state.insertFraction()
        case "power": state.insertPower()
        case "radical": state.insertRadical()
        case "root": state.insertRoot()
        case "left": return state.moveLeft()
        case "right": return state.moveRight()
        case "up": return state.moveUp()
        case "down": return state.moveDown()
        case "start": state.moveToStart()
        case "end": state.moveToEnd()
        default: return false
        }
        return true
    }

    /// Places the cursor, as a tap on the formula does. Returns false for a place that does not exist.
    @discardableResult
    public func setCursor(path: [Int], offset: Int) -> Bool {
        var steps: [MathPathStep] = []
        var row = state.root
        var index = 0
        while index + 1 < path.count {
            let item = path[index]
            guard row.items.indices.contains(item) else { return false }
            let slots = row.items[item].slots
            guard slots.indices.contains(path[index + 1]), let inner = row.items[item].row(slots[path[index + 1]]) else { return false }
            steps.append(MathPathStep(item: item, slot: slots[path[index + 1]]))
            row = inner
            index += 2
        }
        return state.setCursor(MathCursor(path: steps, offset: offset))
    }

    /// Where the cursor is, as VoiceOver says it on iOS: « Au dénominateur », « Fin de ligne »…
    public var cursorDescription: String {
        let row = state.cursorRow, offset = state.cursor.offset
        switch state.cursor.path.last?.slot {
        case .numerator: return "Au numérateur"
        case .denominator: return "Au dénominateur"
        case .exponent: return "Dans l’exposant"
        case .radicand: return "Sous la racine"
        case .index: return "Dans l’indice de la racine"
        case nil:
            if row.isEmpty { return "" }
            if offset == 0 { return "Début de ligne" }
            if offset == row.items.count { return "Fin de ligne" }
            if case .symbol(let character) = row.items[offset - 1], !character.isWhitespace {
                return "Après « \(String(character)) »"
            }
            return "Dans la ligne"
        }
    }

    private static func row(_ row: MathRow) -> MathEditRow {
        MathEditRow(items: row.items.map { item in
            if case .symbol(let character) = item { return MathEditItem(kind: "symbol", text: String(character), slots: []) }
            let kind = switch item {
            case .fraction: "fraction"
            case .superscript: "power"
            case .radical: "radical"
            default: "root"
            }
            return MathEditItem(kind: kind, text: "", slots: item.slots.compactMap { item.row($0) }.map(Self.row))
        })
    }
}
