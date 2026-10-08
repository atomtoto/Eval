import Foundation

/// Reordering of the visible lines of a sheet.
public enum LineReordering {
    /// The order of the entries after moving some visible lines, as the old
    /// index of the entry now at each position. `visible` lists the entry
    /// indices that are shown; hidden entries, such as blank lines, keep their
    /// position and the visible lines move among the visible positions.
    /// `offsets` and `destination` have the meaning of `List` `onMove`: offsets
    /// into `visible`, and a destination in the list before the move.
    /// Returns nil if the arguments do not describe a move.
    public static func order(count: Int, visible: [Int], moving offsets: IndexSet, to destination: Int) -> [Int]? {
        guard visible.allSatisfy({ (0..<count).contains($0) }), Set(visible).count == visible.count,
              !offsets.isEmpty, offsets.allSatisfy({ visible.indices.contains($0) }),
              (0...visible.count).contains(destination) else { return nil }
        let moved = offsets.map { visible[$0] }
        let remaining = visible.indices.filter { !offsets.contains($0) }.map { visible[$0] }
        let insertion = destination - offsets.filter { $0 < destination }.count
        let arranged = Array(remaining[..<insertion]) + moved + Array(remaining[insertion...])
        var order = Array(0..<count)
        for (slot, entry) in zip(visible, arranged) { order[slot] = entry }
        return order
    }
}

extension ResultSelection {
    /// The entries rearranged so that position `i` holds the entry that was at
    /// `order[i]`. Identities, choices and sources follow their lines. Returns
    /// nil unless `order` is a permutation of the entry indices.
    public func rearranged(by order: [Int]) -> ResultSelection? {
        guard order.count == entries.count, Set(order) == Set(entries.indices) else { return nil }
        return replacingEntries(order.map { entries[$0] })
    }

    /// The selection with `entry` inserted at `index` (clamped to the ends).
    public func inserting(_ entry: Entry, at index: Int) -> ResultSelection? {
        var updated = entries
        updated.insert(entry, at: max(0, min(index, updated.count)))
        return replacingEntries(updated)
    }
}

/// The text of a result when it is copied or shared.
public enum ResultText {
    /// A line with its value: `E = 1000 J` for a declaration, `m * v = 400 kg·m/s`
    /// for an expression. A conversion (`→ km/h`) and a comment after the formula
    /// are left out: `value` already is the converted value.
    public static func line(source: String, value: String) -> String {
        let content = LineSyntax(source).body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return value }
        if content.contains("==") { return "\(content) → \(value)" }
        if let name = declaredName(in: source) { return "\(name) = \(value)" }
        return "\(content) = \(value)"
    }

    /// The name a line declares with `name = …`; nil for expressions and `==` comparisons.
    public static func declaredName(in source: String) -> String? {
        let content = withoutComment(source)
        guard !content.contains("=="), let separator = content.firstIndex(of: "=") else { return nil }
        let name = content[..<separator].trimmingCharacters(in: .whitespaces)
        return ExpressionParser.isIdentifier(name) ? name : nil
    }

    /// The sheet as text for sharing. Each line with a value gets it as a
    /// trailing note, `E = 0,5 * m * v²  # = 1000 J`, so the text still opens
    /// as a sheet. Lines that already have a note keep it.
    public static func sharedSheet(_ lines: [(source: String, value: String?)]) -> String {
        lines.map { line in
            guard let value = line.value, !hasComment(line.source),
                  !line.source.trimmingCharacters(in: .whitespaces).isEmpty else { return line.source }
            let trimmed = line.source.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
            return "\(trimmed)  # = \(value)"
        }.joined(separator: "\n")
    }

    private static func hasComment(_ source: String) -> Bool {
        source.contains("#") || source.contains("//")
    }

    private static func withoutComment(_ source: String) -> String {
        var end = source.endIndex
        if let marker = source.firstIndex(of: "#") { end = min(end, marker) }
        if let marker = source.range(of: "//")?.lowerBound { end = min(end, marker) }
        return String(source[..<end])
    }
}
