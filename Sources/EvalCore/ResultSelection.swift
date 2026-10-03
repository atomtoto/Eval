import Foundation

/// The results chosen by the user, attached to sheet lines rather than their
/// current positions. Reconcile this value before evaluating an edited sheet.
public struct ResultSelection: Codable, Sendable, Equatable {
    public struct Entry: Identifiable, Codable, Sendable, Equatable {
        public let id: UUID
        public let source: String
        public let isSelected: Bool

        public init(id: UUID = UUID(), source: String, isSelected: Bool = false) {
            self.id = id
            self.source = source
            self.isSelected = isSelected
        }
    }

    public private(set) var entries: [Entry]

    public init(source: String, initiallySelectedLineIDs: Set<Int> = []) {
        entries = Self.sourceLines(source).enumerated().map { index, line in
            Entry(source: line, isSelected: initiallySelectedLineIDs.contains(index))
        }
    }

    /// Keeps choices through insertions, removals, moves and ordinary edits.
    /// Equal lines and duplicate declarations match in occurrence order.
    /// New lines start unselected.
    public mutating func reconcile(source: String) {
        let lines = Self.sourceLines(source)
        guard entries.map(\.source) != lines else { return }
        let previous = entries
        var matches: [Int: Int] = [:] // New index → previous index.
        var available = Set(previous.indices)

        // Exact matches also keep choices when an existing line is moved.
        var occurrences: [String: [Int]] = [:]
        for index in previous.indices {
            occurrences[previous[index].source, default: []].append(index)
        }
        var offsets: [String: Int] = [:]
        for index in lines.indices {
            let line = lines[index]
            let offset = offsets[line, default: 0]
            if let candidates = occurrences[line], offset < candidates.count {
                let oldIndex = candidates[offset]
                matches[index] = oldIndex
                available.remove(oldIndex)
                offsets[line] = offset + 1
            }
        }

        // A declaration still denotes the same result after its value changes.
        var declarations: [String: [Int]] = [:]
        for index in previous.indices where available.contains(index) {
            if let name = Self.definitionName(previous[index].source) {
                declarations[name, default: []].append(index)
            }
        }
        var declarationOffsets: [String: Int] = [:]
        for index in lines.indices where matches[index] == nil {
            guard let name = Self.definitionName(lines[index]) else { continue }
            let offset = declarationOffsets[name, default: 0]
            if let candidates = declarations[name], offset < candidates.count {
                let oldIndex = candidates[offset]
                matches[index] = oldIndex
                available.remove(oldIndex)
                declarationOffsets[name] = offset + 1
            }
        }

        // Use the longest sequence of ordered matches as edit boundaries.
        // Matched lines moved elsewhere are excluded from those boundaries.
        let anchors = Self.orderedAnchors(matches)
        var oldStart = 0
        var newStart = 0
        for anchor in anchors + [(old: previous.count, new: lines.count)] {
            let oldIndices = (oldStart..<anchor.old).filter { available.contains($0) }
            let newIndices = (newStart..<anchor.new).filter { matches[$0] == nil }
            if oldIndices.count == newIndices.count {
                for (oldIndex, newIndex) in zip(oldIndices, newIndices) {
                    if Self.editKind(previous[oldIndex].source) == Self.editKind(lines[newIndex]) {
                        matches[newIndex] = oldIndex
                        available.remove(oldIndex)
                    }
                }
            } else {
                // When insertion and editing happen together, only related
                // formulas can retain a choice; an inserted unrelated result
                // must not inherit the choice of a nearby line.
                Self.matchRelatedEdits(oldIndices: oldIndices, newIndices: newIndices,
                                       previous: previous, lines: lines,
                                       matches: &matches, available: &available)
            }
            oldStart = anchor.old + 1
            newStart = anchor.new + 1
        }

        entries = lines.enumerated().map { index, line in
            guard let oldIndex = matches[index] else { return Entry(source: line) }
            let old = previous[oldIndex]
            return Entry(id: old.id, source: line, isSelected: old.isSelected)
        }
    }

    public mutating func setSelected(_ selected: Bool, at lineIndex: Int) {
        guard entries.indices.contains(lineIndex) else { return }
        let entry = entries[lineIndex]
        entries[lineIndex] = Entry(id: entry.id, source: entry.source, isSelected: selected)
    }

    /// Replaces a known line while retaining its identity. Use this before
    /// changing the sheet source in an editor that already knows which row
    /// was edited, so an identical neighboring formula remains independent.
    /// Invalid indexes and multiline replacements are ignored.
    public mutating func updateSource(_ source: String, at lineIndex: Int) {
        guard entries.indices.contains(lineIndex),
              source.rangeOfCharacter(from: .newlines) == nil else { return }
        let entry = entries[lineIndex]
        let kind = Self.editKind(source)
        entries[lineIndex] = Entry(id: entry.id, source: source,
                                  isSelected: entry.isSelected && kind != .empty && kind != .comment)
    }

    /// Removes a known line before updating the sheet source. This preserves
    /// the identities and choices of surviving identical formulas.
    public mutating func removeEntry(at lineIndex: Int) {
        guard entries.indices.contains(lineIndex) else { return }
        entries.remove(at: lineIndex)
    }

    /// Applies the choice to the supplied evaluable lines, clearing choices on
    /// lines that are no longer eligible for the Results section.
    public mutating func setAllSelected(_ selected: Bool, selectableLineIDs: Set<Int>) {
        entries = entries.enumerated().map { index, entry in
            Entry(id: entry.id, source: entry.source,
                  isSelected: selected && selectableLineIDs.contains(index))
        }
    }

    public func isSelected(at lineIndex: Int) -> Bool {
        entries.indices.contains(lineIndex) && entries[lineIndex].isSelected
    }

    private static func sourceLines(_ source: String) -> [String] {
        source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }

    private static func content(_ source: String) -> String {
        var end = source.endIndex
        if let marker = source.firstIndex(of: "#") { end = min(end, marker) }
        if let marker = source.range(of: "//")?.lowerBound { end = min(end, marker) }
        return source[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func definitionName(_ source: String) -> String? {
        let text = content(source)
        guard let separator = text.firstIndex(of: "=") else { return nil }
        let next = text.index(after: separator)
        guard next == text.endIndex || text[next] != "=" else { return nil }
        let name = text[..<separator].trimmingCharacters(in: .whitespaces)
        return ExpressionParser.isIdentifier(name) ? name : nil
    }

    private enum EditKind: Equatable {
        case empty, comment, formula, definition(String)
    }

    private static func editKind(_ source: String) -> EditKind {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        if content(source).isEmpty { return .comment }
        if let name = definitionName(source) { return .definition(name) }
        return .formula
    }

    /// Longest increasing subsequence of previous indexes in the new order.
    /// This uses O(n log n) time and O(n) memory even for a large pasted sheet.
    private static func orderedAnchors(_ matches: [Int: Int]) -> [(old: Int, new: Int)] {
        let pairs = matches.map { (old: $0.value, new: $0.key) }.sorted { $0.new < $1.new }
        var tails: [Int] = []
        var predecessors = Array(repeating: -1, count: pairs.count)
        for index in pairs.indices {
            var lower = 0
            var upper = tails.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if pairs[tails[middle]].old < pairs[index].old { lower = middle + 1 }
                else { upper = middle }
            }
            if lower > 0 { predecessors[index] = tails[lower - 1] }
            if lower == tails.count { tails.append(index) }
            else { tails[lower] = index }
        }
        var result: [(old: Int, new: Int)] = []
        var cursor = tails.last ?? -1
        while cursor >= 0 {
            result.append(pairs[cursor])
            cursor = predecessors[cursor]
        }
        return result.reversed()
    }

    private static func matchRelatedEdits(
        oldIndices: [Int], newIndices: [Int], previous: [Entry], lines: [String],
        matches: inout [Int: Int], available: inout Set<Int>
    ) {
        // An invalid, oversized pasted sheet should still remain responsive.
        // Exact and declaration matches above are retained in this case.
        guard !oldIndices.isEmpty, !newIndices.isEmpty,
              oldIndices.count <= 250_000 / newIndices.count else { return }
        // Work in source order and use only a clear best match. Avoid guessing
        // when a batch edit has created several equally plausible formulas.
        var lastNewIndex = -1
        for oldIndex in oldIndices {
            let kind = editKind(previous[oldIndex].source)
            guard kind == .formula else { continue }
            var best: (index: Int, score: Double)?
            var tied = false
            for newIndex in newIndices where newIndex > lastNewIndex && matches[newIndex] == nil {
                guard editKind(lines[newIndex]) == kind else { continue }
                let score = editSimilarity(previous[oldIndex].source, lines[newIndex])
                guard score >= 0.6 else { continue }
                if best == nil || score > best!.score {
                    best = (newIndex, score)
                    tied = false
                } else if score == best!.score {
                    tied = true
                }
            }
            guard let best, !tied else { continue }
            matches[best.index] = oldIndex
            available.remove(oldIndex)
            lastNewIndex = best.index
        }
    }

    private static func editSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(content(lhs).filter { !$0.isWhitespace })
        let right = Array(content(rhs).filter { !$0.isWhitespace })
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        // Count the unchanged prefix and suffix. Formula edits made while
        // typing generally add a term or replace a small middle fragment.
        let limit = min(left.count, right.count)
        var prefix = 0
        while prefix < limit && left[prefix] == right[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix && left[left.count - 1 - suffix] == right[right.count - 1 - suffix] {
            suffix += 1
        }
        return Double(prefix + suffix) / Double(max(left.count, right.count))
    }
}
