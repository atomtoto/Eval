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
    /// Formulas and declarations removed by recent edits, most recent last.
    /// A line cut in one edit and pasted in the next gets its identity back.
    private var detached: [Entry] = []
    private static let detachedLimit = 20

    /// Identities of current lines and of recently removed ones that may
    /// still return. Keep data attached to a line for all of these.
    public var retainedIDs: Set<UUID> { Set(entries.map(\.id) + detached.map(\.id)) }

    /// The same selection with other current entries: the recently removed
    /// lines stay remembered, unless they are among the new entries.
    func replacingEntries(_ newEntries: [Entry]) -> ResultSelection {
        var copy = self
        copy.entries = newEntries
        let current = Set(newEntries.map(\.id))
        copy.detached = detached.filter { !current.contains($0.id) }
        return copy
    }

    public init(source: String, initiallySelectedLineIDs: Set<Int> = []) {
        entries = Self.sourceLines(source).enumerated().map { index, line in
            Entry(source: line, isSelected: initiallySelectedLineIDs.contains(index))
        }
    }

    /// Keeps choices through insertions, removals, moves and ordinary edits.
    /// Equal lines match between the same unchanged neighbours, then in
    /// occurrence order. New lines start unselected unless they restore a
    /// recently removed line or declaration.
    public mutating func reconcile(source: String) {
        let lines = Self.sourceLines(source)
        guard entries.map(\.source) != lines else { return }
        let previous = entries
        var matches: [Int: Int] = [:] // New index → previous index.
        var available = Set(previous.indices)

        // Lines found once in each version anchor the edit, so a duplicate
        // keeps the identity of the copy between the same neighbours.
        let previousOccurrences = Self.occurrences(previous.map(\.source))
        var uniqueMatches: [Int: Int] = [:]
        for (line, indices) in Self.occurrences(lines) where indices.count == 1 {
            if let old = previousOccurrences[line], old.count == 1 { uniqueMatches[indices[0]] = old[0] }
        }
        var gapStart = (old: 0, new: 0)
        for anchor in Self.orderedAnchors(uniqueMatches) + [(old: previous.count, new: lines.count)] {
            Self.matchEqualLines(old: gapStart.old..<anchor.old, new: gapStart.new..<anchor.new,
                                 previous: previous, lines: lines, matches: &matches, available: &available)
            if anchor.old < previous.count {
                matches[anchor.new] = anchor.old
                available.remove(anchor.old)
            }
            gapStart = (anchor.old + 1, anchor.new + 1)
        }
        // Remaining exact matches also keep choices when a line is moved.
        Self.matchEqualLines(old: previous.indices, new: lines.indices,
                             previous: previous, lines: lines, matches: &matches, available: &available)

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

        // A line removed by an earlier edit, such as a cut, returns as it was.
        var detached = self.detached
        var restored: [Int: Entry] = [:]
        for index in lines.indices where matches[index] == nil {
            if let position = detached.lastIndex(where: { $0.source == lines[index] }) {
                restored[index] = detached.remove(at: position)
            }
        }

        // Use the longest sequence of ordered matches as edit boundaries.
        // Matched lines moved elsewhere are excluded from those boundaries.
        let anchors = Self.orderedAnchors(matches)
        var oldStart = 0
        var newStart = 0
        for anchor in anchors + [(old: previous.count, new: lines.count)] {
            let oldIndices = (oldStart..<anchor.old).filter { available.contains($0) }
            let newIndices = (newStart..<anchor.new).filter { matches[$0] == nil && restored[$0] == nil }
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

        // A declaration retyped after being cleared returns with its identity.
        var detachedNames = detached.map { Self.definitionName($0.source) }
        for index in lines.indices where matches[index] == nil && restored[index] == nil && !detached.isEmpty {
            guard let name = Self.definitionName(lines[index]),
                  let position = detachedNames.lastIndex(of: name) else { continue }
            detachedNames.remove(at: position)
            restored[index] = detached.remove(at: position)
        }

        entries = lines.enumerated().map { index, line in
            guard let old = matches[index].map({ previous[$0] }) ?? restored[index] else { return Entry(source: line) }
            return Entry(id: old.id, source: line, isSelected: old.isSelected)
        }
        let removed = previous.indices.filter { available.contains($0) }.map { previous[$0] }
        self.detached = Self.remembered(detached + removed)
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
        detached = Self.remembered(detached + [entries.remove(at: lineIndex)])
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

    private enum CodingKeys: String, CodingKey { case entries, detachedEntries }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decode([Entry].self, forKey: .entries)
        // Selections saved before removed lines were remembered have none.
        let current = Set(entries.map(\.id))
        detached = Self.remembered((try values.decodeIfPresent([Entry].self, forKey: .detachedEntries) ?? [])
            .filter { !current.contains($0.id) })
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(entries, forKey: .entries)
        try values.encode(detached, forKey: .detachedEntries)
    }

    /// Keeps the most recent formulas and declarations; blank lines and
    /// comments carry no choice worth restoring.
    private static func remembered(_ entries: [Entry]) -> [Entry] {
        var kept: [Entry] = []
        for entry in entries.reversed() {
            guard kept.count < detachedLimit else { break }
            let kind = editKind(entry.source)
            if kind != .empty && kind != .comment { kept.append(entry) }
        }
        return kept.reversed()
    }

    private static func occurrences(_ lines: [String]) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for index in lines.indices { result[lines[index], default: []].append(index) }
        return result
    }

    /// Pairs equal lines in occurrence order among those still unmatched.
    private static func matchEqualLines(
        old oldRange: Range<Int>, new newRange: Range<Int>, previous: [Entry], lines: [String],
        matches: inout [Int: Int], available: inout Set<Int>
    ) {
        var candidates: [String: [Int]] = [:]
        for index in oldRange.reversed() where available.contains(index) {
            candidates[previous[index].source, default: []].append(index)
        }
        guard !candidates.isEmpty else { return }
        for index in newRange where matches[index] == nil {
            guard let oldIndex = candidates[lines[index]]?.popLast() else { continue }
            matches[index] = oldIndex
            available.remove(oldIndex)
        }
    }

    private static func sourceLines(_ source: String) -> [String] {
        source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }

    private static func content(_ source: String) -> String {
        LineSyntax(source).content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func definitionName(_ source: String) -> String? {
        LineSyntax(source).definitionName
    }

    private enum EditKind: Equatable {
        case empty, comment, formula, definition(String)
    }

    private static func editKind(_ source: String) -> EditKind {
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        let line = LineSyntax(source)
        if line.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .comment }
        if let name = line.definitionName { return .definition(name) }
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

    /// The largest number of old/new line pairs compared after an edit. A bigger
    /// batch, such as a large paste, keeps only exact and declaration matches.
    static let relatedEditPairLimit = 20_000

    private static func matchRelatedEdits(
        oldIndices: [Int], newIndices: [Int], previous: [Entry], lines: [String],
        matches: inout [Int: Int], available: inout Set<Int>
    ) {
        // An invalid, oversized pasted sheet should still remain responsive.
        guard !oldIndices.isEmpty, !newIndices.isEmpty,
              oldIndices.count <= relatedEditPairLimit / newIndices.count else { return }
        // Parse every line once, not once per pair.
        let oldFormulas = oldIndices.compactMap { index -> (index: Int, text: [Character])? in
            editKind(previous[index].source) == .formula ? (index, compactContent(previous[index].source)) : nil
        }
        let newFormulas = newIndices.compactMap { index -> (index: Int, text: [Character])? in
            editKind(lines[index]) == .formula ? (index, compactContent(lines[index])) : nil
        }
        // Work in source order and use only a clear best match. Avoid guessing
        // when a batch edit has created several equally plausible formulas.
        var lastNewIndex = -1
        for old in oldFormulas {
            var best: (index: Int, score: Double)?
            var tied = false
            for new in newFormulas where new.index > lastNewIndex && matches[new.index] == nil {
                let score = editSimilarity(old.text, new.text)
                guard score >= 0.6 else { continue }
                if best == nil || score > best!.score {
                    best = (new.index, score)
                    tied = false
                } else if score == best!.score {
                    tied = true
                }
            }
            guard let best, !tied else { continue }
            matches[best.index] = old.index
            available.remove(old.index)
            lastNewIndex = best.index
        }
    }

    private static func compactContent(_ source: String) -> [Character] {
        Array(content(source).filter { !$0.isWhitespace })
    }

    private static func editSimilarity(_ left: [Character], _ right: [Character]) -> Double {
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
