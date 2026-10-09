import Foundation

/// A child row of a structure.
public enum MathSlot: String, Sendable, Hashable, CaseIterable {
    case numerator, denominator, exponent, radicand, index
}

/// One step down the editing tree: the structure at `item` in a row, then its `slot`.
public struct MathPathStep: Sendable, Hashable {
    public var item: Int
    public var slot: MathSlot

    public init(item: Int, slot: MathSlot) {
        self.item = item
        self.slot = slot
    }
}

/// The insertion point: a row reached by `path` from the root, and a position
/// between its items (0 before the first item, `items.count` after the last).
public struct MathCursor: Sendable, Hashable {
    public var path: [MathPathStep]
    public var offset: Int

    public init(path: [MathPathStep] = [], offset: Int = 0) {
        self.path = path
        self.offset = offset
    }
}

/// A horizontal sequence of symbols and structures.
public struct MathRow: Sendable, Hashable {
    public var items: [MathItem]

    public init(_ items: [MathItem] = []) {
        self.items = items
    }

    /// One symbol per character.
    public init(text: String) {
        items = text.map(MathItem.symbol)
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Whether the exponent at `index` has nothing to raise: no operand before it, and no
    /// other exponent, which the exponent is stacked on. It then stands over an empty base.
    public func lacksBase(at index: Int) -> Bool {
        guard items.indices.contains(index), case .superscript = items[index] else { return false }
        if index > 0, case .superscript = items[index - 1] { return false }
        return MathEditorState.operandStart(in: items, before: index) == index
    }

    /// The row reached by `path`, or nil when the path does not exist.
    public func row(at path: [MathPathStep]) -> MathRow? {
        var row = self
        for step in path {
            guard row.items.indices.contains(step.item), let child = row.items[step.item].row(step.slot) else { return nil }
            row = child
        }
        return row
    }

    /// Edits the row reached by a path known to exist.
    mutating func update<Result>(at path: ArraySlice<MathPathStep>, _ body: (inout MathRow) -> Result) -> Result {
        guard let step = path.first else { return body(&self) }
        var child = items[step.item].row(step.slot) ?? MathRow()
        let result = child.update(at: path.dropFirst(), body)
        items[step.item].setRow(child, for: step.slot)
        return result
    }
}

/// A symbol, typed or copied verbatim from the source, or a 2D structure.
public indirect enum MathItem: Sendable, Hashable {
    case symbol(Character)
    case fraction(MathRow, MathRow)
    /// An exponent, raised over the item before it.
    case superscript(MathRow)
    case radical(MathRow)
    case root(index: MathRow, radicand: MathRow)

    /// The child rows in reading order: empty for a symbol.
    public var slots: [MathSlot] {
        switch self {
        case .symbol: []
        case .fraction: [.numerator, .denominator]
        case .superscript: [.exponent]
        case .radical: [.radicand]
        case .root: [.index, .radicand]
        }
    }

    public func row(_ slot: MathSlot) -> MathRow? {
        switch (self, slot) {
        case (.fraction(let numerator, _), .numerator): numerator
        case (.fraction(_, let denominator), .denominator): denominator
        case (.superscript(let exponent), .exponent): exponent
        case (.radical(let radicand), .radicand): radicand
        case (.root(let index, _), .index): index
        case (.root(_, let radicand), .radicand): radicand
        default: nil
        }
    }

    mutating func setRow(_ row: MathRow, for slot: MathSlot) {
        switch (self, slot) {
        case (.fraction(_, let denominator), .numerator): self = .fraction(row, denominator)
        case (.fraction(let numerator, _), .denominator): self = .fraction(numerator, row)
        case (.superscript, .exponent): self = .superscript(row)
        case (.radical, .radicand): self = .radical(row)
        case (.root(_, let radicand), .index): self = .root(index: row, radicand: radicand)
        case (.root(let index, _), .radicand): self = .root(index: index, radicand: row)
        default: break
        }
    }

    var isStructure: Bool {
        if case .symbol = self { return false }
        return true
    }

    /// True for a structure whose rows are all empty.
    var isEmptyStructure: Bool {
        isStructure && slots.allSatisfy { row($0)?.isEmpty ?? true }
    }
}

/// The pure model of the structured math editor: a tree of rows edited at a
/// cursor, read from and written back to a sheet line.
public struct MathEditorState: Sendable, Hashable {
    public private(set) var root: MathRow
    /// Always designates an existing row and offset; change it with `setCursor(_:)` or the moves.
    public private(set) var cursor: MathCursor
    /// The comment with the spacing before it, kept out of the tree and appended verbatim.
    public var comment: String

    /// An invalid cursor is replaced by the end of the root row.
    public init(root: MathRow = MathRow(), cursor: MathCursor? = nil, comment: String = "") {
        self.root = root
        self.comment = comment
        self.cursor = MathCursor(offset: root.items.count)
        if let cursor { setCursor(cursor) }
    }

    /// The row holding the cursor.
    public var cursorRow: MathRow { root.row(at: cursor.path) ?? root }

    /// The cursor's offset when it is in the row at `path`, for drawing it there.
    public func cursorOffset(at path: [MathPathStep]) -> Int? {
        cursor.path == path ? cursor.offset : nil
    }

    /// Moves the cursor if its row exists; the offset is clamped to that row.
    @discardableResult
    public mutating func setCursor(_ cursor: MathCursor) -> Bool {
        guard let row = root.row(at: cursor.path) else { return false }
        self.cursor = MathCursor(path: cursor.path, offset: min(max(cursor.offset, 0), row.items.count))
        return true
    }

    private mutating func editCurrentRow<Result>(_ body: (inout MathRow) -> Result) -> Result {
        root.update(at: cursor.path[...], body)
    }

    /// Enters `slot` of the structure at `item` of the current row.
    private mutating func enter(_ item: Int, _ slot: MathSlot, atEnd: Bool) {
        let path = cursor.path + [MathPathStep(item: item, slot: slot)]
        cursor = MathCursor(path: path, offset: atEnd ? root.row(at: path)?.items.count ?? 0 : 0)
    }
}

// MARK: - Editing

extension MathEditorState {
    /// Types `text` at the cursor: `/` and `÷` make a fraction of the operand
    /// before the cursor, `^` an exponent, `√` a square root, superscript digits
    /// an exponent. Line breaks are ignored: the app handles Return.
    public mutating func insert(_ text: String) {
        for character in text where !character.isNewline {
            switch character {
            case "/", "÷": insertFraction()
            case "^": insertPower()
            case "√": insertRadical()
            default:
                if let plain = MathSerialization.superscriptCharacters[character] {
                    insertExponentCharacter(plain)
                } else {
                    let offset = cursor.offset
                    editCurrentRow { $0.items.insert(.symbol(character), at: offset) }
                    cursor.offset += 1
                }
            }
        }
    }

    /// Makes a fraction whose numerator is the operand just before the cursor
    /// (a name or number, a parenthesized group with its function name, a
    /// structure, each with its exponents), then edits the denominator; with no
    /// such operand, edits the empty numerator.
    public mutating func insertFraction() {
        let items = cursorRow.items, end = cursor.offset
        // Spaces between the operand and the slash are dropped: a / b reads a/b.
        var operandEnd = end
        while operandEnd > 0, items[operandEnd - 1] == .symbol(" ") { operandEnd -= 1 }
        var start = Self.operandStart(in: items, before: operandEnd)
        if start == operandEnd { (start, operandEnd) = (end, end) }
        let numerator = MathRow(Array(items[start..<operandEnd]))
        editCurrentRow { $0.items.replaceSubrange(start..<end, with: [.fraction(numerator, MathRow())]) }
        cursor.offset = start
        enter(start, numerator.isEmpty ? .numerator : .denominator, atEnd: false)
    }

    /// Inserts an empty exponent and edits it.
    public mutating func insertPower() {
        insertStructure(.superscript(MathRow()), editing: .exponent)
    }

    /// Inserts an empty square root and edits its radicand.
    public mutating func insertRadical() {
        insertStructure(.radical(MathRow()), editing: .radicand)
    }

    /// Inserts an empty n-th root and edits its index, which comes first in reading order.
    public mutating func insertRoot() {
        insertStructure(.root(index: MathRow(), radicand: MathRow()), editing: .index)
    }

    private mutating func insertStructure(_ item: MathItem, editing slot: MathSlot) {
        let offset = cursor.offset
        editCurrentRow { $0.items.insert(item, at: offset) }
        enter(offset, slot, atEnd: false)
    }

    /// A typed `²` extends an exponent of plain digits just before the cursor,
    /// so that `⁻¹` stays one exponent; otherwise it adds a new one.
    private mutating func insertExponentCharacter(_ character: Character) {
        let offset = cursor.offset
        if offset > 0, case .superscript(var exponent) = cursorRow.items[offset - 1],
           exponent.items.allSatisfy({ if case .symbol(let symbol) = $0 { "0123456789-+".contains(symbol) } else { false } }) {
            exponent.items.append(.symbol(character))
            editCurrentRow { $0.items[offset - 1] = .superscript(exponent) }
        } else {
            editCurrentRow { $0.items.insert(.superscript(MathRow([.symbol(character)])), at: offset) }
            cursor.offset += 1
        }
    }

    /// Deletes backwards:
    /// - a symbol before the cursor is removed;
    /// - an empty structure before the cursor is removed, a filled one is entered at the end of its last row;
    /// - at the start of a later row of a structure (denominator, radicand of a root), moves to the end of the previous row;
    /// - at the start of a structure's first row, unwraps the structure: its rows' items take its place, in reading order;
    /// - at the start of the whole formula, does nothing.
    public mutating func deleteBackward() {
        let offset = cursor.offset
        if offset > 0 {
            let previous = cursorRow.items[offset - 1]
            if previous.isStructure, !previous.isEmptyStructure, let last = previous.slots.last {
                cursor.offset -= 1
                enter(offset - 1, last, atEnd: true)
            } else {
                editCurrentRow { _ = $0.items.remove(at: offset - 1) }
                cursor.offset -= 1
            }
            return
        }
        guard let step = cursor.path.last else { return }
        let parentPath = Array(cursor.path.dropLast())
        guard let structure = root.row(at: parentPath)?.items[step.item],
              let slotIndex = structure.slots.firstIndex(of: step.slot) else { return }
        if slotIndex > 0 {
            cursor.path = parentPath
            cursor.offset = step.item
            enter(step.item, structure.slots[slotIndex - 1], atEnd: true)
            return
        }
        let contents = structure.slots.flatMap { structure.row($0)?.items ?? [] }
        cursor = MathCursor(path: parentPath, offset: step.item)
        editCurrentRow { $0.items.replaceSubrange(step.item...step.item, with: contents) }
    }

    /// The first item of the operand that ends at `end`, or `end` when there is none.
    static func operandStart(in items: [MathItem], before end: Int) -> Int {
        var start = end
        while start > 0, items[start - 1] == .symbol("!") { start -= 1 }
        guard start > 0 else { return end }
        switch items[start - 1] {
        case .superscript:
            let base = operandStart(in: items, before: start - 1)
            return base == start - 1 ? end : base
        case .fraction, .radical, .root:
            return start - 1
        case .symbol(")"):
            var depth = 0, index = start - 1
            while index >= 0 {
                if items[index] == .symbol(")") { depth += 1 }
                if items[index] == .symbol("(") {
                    depth -= 1
                    if depth == 0 { break }
                }
                index -= 1
            }
            guard index >= 0 else { return end }
            // A function name before the group belongs to the operand: sin(x).
            while index > 0, case .symbol(let character) = items[index - 1], MathSerialization.isNameCharacter(character) {
                index -= 1
            }
            return index
        case .symbol(let character) where MathSerialization.isOperandCharacter(character):
            var index = start - 1
            while index > 0, case .symbol(let previous) = items[index - 1], MathSerialization.isOperandCharacter(previous) {
                index -= 1
            }
            return index
        default:
            return end
        }
    }
}

// MARK: - Moving

extension MathEditorState {
    /// Moves one step left, entering a structure at the end of its last row and
    /// leaving a row for the previous row of its structure, or for the parent row.
    @discardableResult
    public mutating func moveLeft() -> Bool {
        let offset = cursor.offset
        if offset > 0 {
            let previous = cursorRow.items[offset - 1]
            cursor.offset -= 1
            if let last = previous.slots.last { enter(offset - 1, last, atEnd: true) }
            return true
        }
        guard let step = cursor.path.last else { return false }
        let parentPath = Array(cursor.path.dropLast())
        cursor = MathCursor(path: parentPath, offset: step.item)
        if let slots = root.row(at: parentPath)?.items[step.item].slots,
           let index = slots.firstIndex(of: step.slot), index > 0 {
            enter(step.item, slots[index - 1], atEnd: true)
        }
        return true
    }

    /// Moves one step right, entering a structure at the start of its first row
    /// and leaving a row for the next row of its structure, or for the parent row.
    @discardableResult
    public mutating func moveRight() -> Bool {
        let offset = cursor.offset, items = cursorRow.items
        if offset < items.count {
            if let first = items[offset].slots.first {
                enter(offset, first, atEnd: false)
            } else {
                cursor.offset += 1
            }
            return true
        }
        guard let step = cursor.path.last else { return false }
        let parentPath = Array(cursor.path.dropLast())
        cursor = MathCursor(path: parentPath, offset: step.item + 1)
        if let slots = root.row(at: parentPath)?.items[step.item].slots,
           let index = slots.firstIndex(of: step.slot), index + 1 < slots.count {
            cursor.offset = step.item
            enter(step.item, slots[index + 1], atEnd: false)
        }
        return true
    }

    /// Moves into an exponent next to the cursor, else from a denominator to its
    /// numerator or from a root's radicand to its index, at the nearest level.
    @discardableResult
    public mutating func moveUp() -> Bool {
        let items = cursorRow.items, offset = cursor.offset
        if offset < items.count, case .superscript = items[offset] {
            enter(offset, .exponent, atEnd: false)
            return true
        }
        if offset > 0, case .superscript = items[offset - 1] {
            enter(offset - 1, .exponent, atEnd: true)
            return true
        }
        return moveVertically([.denominator: .numerator, .radicand: .index], exitingExponent: false)
    }

    /// Moves from a numerator to its denominator, from a root's index to its
    /// radicand, or out of an exponent to just after it, at the nearest level.
    @discardableResult
    public mutating func moveDown() -> Bool {
        moveVertically([.numerator: .denominator, .index: .radicand], exitingExponent: true)
    }

    private mutating func moveVertically(_ targets: [MathSlot: MathSlot], exitingExponent: Bool) -> Bool {
        for level in cursor.path.indices.reversed() {
            let step = cursor.path[level]
            let parentPath = Array(cursor.path[..<level])
            guard let structure = root.row(at: parentPath)?.items[step.item] else { return false }
            if exitingExponent, step.slot == .exponent {
                cursor = MathCursor(path: parentPath, offset: step.item + 1)
                return true
            }
            guard let target = targets[step.slot], structure.slots.contains(target) else { continue }
            let offset = level == cursor.path.count - 1 ? cursor.offset : Int.max
            cursor.path = parentPath + [MathPathStep(item: step.item, slot: target)]
            cursor.offset = min(offset, root.row(at: cursor.path)?.items.count ?? 0)
            return true
        }
        return false
    }

    public mutating func moveToStart() {
        cursor = MathCursor()
    }

    public mutating func moveToEnd() {
        cursor = MathCursor(offset: root.items.count)
    }
}

// MARK: - Reading and writing a line

extension MathEditorState {
    /// Reads a sheet line. The comment (first `#` or `//`) stays outside the
    /// tree. The content is split at `=`, `==` and the `→`/`->` arrow; each
    /// member that parses has its divisions, powers and roots (`sqrt`, `√`,
    /// `cbrt`, `root`) made into structures, while every other character is
    /// kept as a symbol, spaces included. Unit suffixes (`5 m/s`), conversion
    /// targets and members that do not parse stay plain symbols. The cursor
    /// starts at the end.
    public init(source: String) {
        let characters = Array(source.filter { !$0.isNewline })
        var contentEnd = characters.count
        if let hash = characters.firstIndex(of: "#") { contentEnd = hash }
        if let slashes = characters.indices.dropLast().first(where: { characters[$0] == "/" && characters[$0 + 1] == "/" }) {
            contentEnd = min(contentEnd, slashes)
        }
        if contentEnd < characters.count {
            while contentEnd > 0, characters[contentEnd - 1].isWhitespace { contentEnd -= 1 }
        }

        var spans: [ExpressionSyntax] = []
        var memberStart = 0, isConversion = false, index = 0
        func parseMember(_ end: Int) {
            defer { memberStart = end }
            guard !isConversion, end > memberStart,
                  let nodes = ExpressionParser.syntax(of: String(characters[memberStart..<end])) else { return }
            spans += nodes.map { node in
                ExpressionSyntax(kind: node.kind, range: node.range.shifted(by: memberStart),
                                 parts: node.parts.map { $0.shifted(by: memberStart) })
            }
        }
        while index < contentEnd {
            let character = characters[index]
            if character == "=" || character == "→" || (character == "-" && index + 1 < contentEnd && characters[index + 1] == ">") {
                parseMember(index)
                isConversion = character != "="
                index += character == "-" ? 2 : 1
                while character == "=", index < contentEnd, characters[index] == "=" { index += 1 }
                memberStart = index
            } else {
                index += 1
            }
        }
        parseMember(contentEnd)

        let builder = MathTreeBuilder(characters: characters, spans: spans)
        self.init(root: builder.row(0..<contentEnd), comment: String(characters[contentEnd...]))
    }

    /// The line as text: equivalent to the tree for the engine (see `MathSerialization`), followed by the comment.
    public var source: String {
        let content = MathSerialization.text(of: root)
        // A content ending in "/" must not fuse with a "//" comment.
        if content.hasSuffix("/"), comment.hasPrefix("/") { return content + " " + comment }
        return content + comment
    }
}

private extension Range<Int> {
    func shifted(by offset: Int) -> Range<Int> { lowerBound + offset..<upperBound + offset }
}

/// Builds the tree of a line from its characters and the parser's structural nodes.
private struct MathTreeBuilder {
    let characters: [Character]
    /// Outer nodes first among nodes that start together.
    let spans: [ExpressionSyntax]

    init(characters: [Character], spans: [ExpressionSyntax]) {
        self.characters = characters
        self.spans = spans.filter(Self.isStructural).sorted {
            $0.range.lowerBound != $1.range.lowerBound ? $0.range.lowerBound < $1.range.lowerBound
                : $0.range.upperBound > $1.range.upperBound
        }
    }

    private static func isStructural(_ span: ExpressionSyntax) -> Bool {
        switch span.kind {
        case .division, .power, .radical: true
        case .call(let name): (name == "sqrt" || name == "cbrt") && span.parts.count == 1 || name == "root" && span.parts.count == 2
        }
    }

    func row(_ range: Range<Int>) -> MathRow { MathRow(items(range)) }

    private func items(_ range: Range<Int>) -> [MathItem] {
        var result: [MathItem] = [], position = range.lowerBound
        for span in spans where span.range.lowerBound >= position && span.range.upperBound <= range.upperBound {
            result += symbols(position..<span.range.lowerBound)
            result += structure(span)
            position = span.range.upperBound
        }
        return result + symbols(position..<range.upperBound)
    }

    private func symbols(_ range: Range<Int>) -> [MathItem] {
        characters[range].map(MathItem.symbol)
    }

    private func structure(_ span: ExpressionSyntax) -> [MathItem] {
        switch span.kind {
        case .division:
            // A leading sign stays before the fraction: -a/b is −(a/b). In -a/b/c,
            // the sign belongs to the inner fraction.
            var numerator = span.parts[0], sign: [MathItem] = []
            if "+-−–".contains(characters[numerator.lowerBound]),
               !spans.contains(where: { $0.kind == .division && $0.range.lowerBound == numerator.lowerBound && $0.range.upperBound <= numerator.upperBound }) {
                var start = numerator.lowerBound + 1
                while start < numerator.upperBound, characters[start].isWhitespace { start += 1 }
                sign = symbols(numerator.lowerBound..<start)
                numerator = start..<numerator.upperBound
            }
            return sign + [.fraction(row(unwrapped(numerator)), row(unwrapped(span.parts[1])))]
        case .power:
            let exponent = span.parts[1], base = span.parts[0]
            let superscripts = characters[exponent].compactMap { MathSerialization.superscriptCharacters[$0] }
            let row = superscripts.count == exponent.count ? MathRow(superscripts.map(MathItem.symbol)) : row(unwrapped(exponent))
            // In x²^3 the parser reads x^(2^3): the base of the inner power is the exponent
            // `²`, which the row shows as the plain digit it stands for.
            let digits = characters[base].compactMap { MathSerialization.superscriptCharacters[$0] }
            let baseItems = !base.isEmpty && digits.count == base.count ? digits.map(MathItem.symbol) : items(base)
            return baseItems + [.superscript(row)]
        case .radical:
            return [.radical(row(unwrapped(span.parts[0])))]
        case .call("root"):
            return [.root(index: row(span.parts[1]), radicand: row(span.parts[0]))]
        case .call("cbrt"):
            return [.root(index: MathRow(text: "3"), radicand: row(span.parts[0]))]
        case .call:
            return [.radical(row(span.parts[0]))]
        }
    }

    /// Without the parentheses that wrap the whole range, which the layout shows instead.
    private func unwrapped(_ range: Range<Int>) -> Range<Int> {
        guard range.count >= 2, characters[range.lowerBound] == "(", characters[range.upperBound - 1] == ")" else { return range }
        var depth = 0
        for index in range {
            if characters[index] == "(" { depth += 1 }
            if characters[index] == ")" { depth -= 1 }
            if depth == 0 { return index == range.upperBound - 1 ? range.lowerBound + 1..<index : range }
        }
        return range
    }
}

/// Writes a tree as text that the engine reads with the meaning of the layout:
/// - a fraction is `N/D`; N or D is parenthesized unless it is one operand (a
///   name, a number, a call, a parenthesized group, possibly with an exponent);
///   the whole fraction is parenthesized when it touches an operand, follows
///   `/`, `÷`, `^` or `√`, precedes an exponent, or precedes a spaced operand
///   (so that `1/2 m` stays (1/2)·m and is not read as 1/(2 m));
/// - an integer exponent uses superscript digits (`²`, `⁻¹`, `¹⁰`); any other
///   is `^x` for one operand followed by an operator, else `^(…)`;
/// - a square root is `√(x)`, a call, so `√(2) m` is (√2)·m;
/// - an n-th root, including a cube root read from `cbrt`, is `root(x; n)`;
/// - an empty row, and the missing base of an exponent, read as `()`, so that an unfinished structure reports an error.
enum MathSerialization {
    static let superscriptCharacters: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
        "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁻": "-", "⁺": "+"
    ]
    private static let superscriptDigits: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "-": "⁻", "−": "⁻", "+": "⁺"
    ]
    /// Characters after which a structure keeps its own meaning without parentheses.
    private static let operators: Set<Character> = ["+", "-", "−", "–", "*", "×", "·", "⋅", "/", "÷", ";", "=", "→", ">", "<"]

    static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || "_°µΩℏπ".contains(character)
    }

    /// A character of a name or a number, including its decimal separator.
    static func isOperandCharacter(_ character: Character) -> Bool {
        isNameCharacter(character) || character == "." || character == "," || character == "%"
    }

    static func text(of row: MathRow) -> String {
        var output = ""
        let items = row.items
        // Where each item starts in `output`, to parenthesize the base of a second exponent.
        let tracksStarts = items.indices.dropFirst().contains { index in
            if case .superscript = items[index], case .superscript = items[index - 1] { true } else { false }
        }
        var starts: [Int] = []
        for (index, item) in items.enumerated() {
            if tracksStarts { starts.append(output.count) }
            if case .superscript = item, index > 0, case .superscript = items[index - 1] {
                // x, ^2, ^3 is (x²)³; the text x²^3 would read x^(2³).
                let start = MathEditorState.operandStart(in: items, before: index)
                if start < index {
                    output.insert("(", at: output.index(output.startIndex, offsetBy: starts[start]))
                    output.append(")")
                    for later in (start + 1)..<starts.count { starts[later] += 1 }
                }
            }
            // An exponent over nothing reads as an empty base, never as a leading `^`.
            if row.lacksBase(at: index) { output += "()" }
            switch item {
            case .symbol(let character):
                output.append(character)
            case .fraction(let numerator, let denominator):
                let fraction = member(numerator) + "/" + member(denominator)
                output += needsGrouping(after: output, before: items[(index + 1)...]) ? "(" + fraction + ")" : fraction
            case .superscript(let exponent):
                output += self.exponent(exponent, after: output, before: items[(index + 1)...])
            case .radical(let radicand):
                output += "√(" + text(of: radicand) + ")"
            case .root(let rootIndex, let radicand):
                if let last = output.last, isOperandCharacter(last) { output += " " }
                output += "root(" + filled(radicand) + "; " + filled(rootIndex) + ")"
            }
        }
        return output
    }

    /// An empty argument is written `()`, so the engine reports the unfinished box.
    private static func filled(_ row: MathRow) -> String {
        row.isEmpty ? "()" : text(of: row)
    }

    private static func member(_ row: MathRow) -> String {
        let text = text(of: row)
        return ExpressionParser.isSingleOperand(text) ? text : "(" + text + ")"
    }

    private static func exponent(_ row: MathRow, after output: String, before next: ArraySlice<MathItem>) -> String {
        let text = text(of: row)
        let digits = text.compactMap { superscriptDigits[$0] }
        let isInteger = digits.count == text.count && text.contains(where: \.isNumber)
            && !text.dropFirst().contains { "-−+".contains($0) }
        let touchesDigits = output.last.map { superscriptCharacters[$0] != nil } ?? false
            || next.first.map { if case .symbol(let character) = $0 { character.isNumber || character == "." || character == "," } else { false } } ?? false
        if isInteger, !touchesDigits { return String(digits) }
        let operatorFollows = next.first.map { if case .symbol(let character) = $0 { character.isWhitespace || operators.contains(character) || character == ")" } else { false } } ?? true
        if operatorFollows, ExpressionParser.isSingleOperand(text) { return "^" + text }
        return "^(" + text + ")"
    }

    /// Whether a fraction needs parentheses to keep its meaning between `output` and `next`.
    private static func needsGrouping(after output: String, before next: ArraySlice<MathItem>) -> Bool {
        if let last = output.last, !last.isWhitespace, !operators.contains(last), last != "(" { return true }
        if let previous = output.last(where: { !$0.isWhitespace && !"+-−–".contains($0) }), "/÷^√".contains(previous) { return true }
        guard let following = next.first else { return false }
        guard case .symbol(let character) = following else { return true }
        if character.isWhitespace {
            guard let operand = next.first(where: { if case .symbol(let symbol) = $0 { !symbol.isWhitespace } else { true } }) else { return false }
            guard case .symbol(let symbol) = operand else { return true }
            return isOperandCharacter(symbol) || symbol == "(" || symbol == "√"
        }
        return !operators.contains(character) && character != ")"
    }
}
