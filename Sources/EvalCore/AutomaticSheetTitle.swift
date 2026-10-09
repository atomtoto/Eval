import Foundation

/// The rules of automatic titles: which sheets may be named from their content,
/// what part of the sheet describes it, and how a proposed title is cleaned up.
/// The proposal itself comes from a language model, outside this module.
public enum AutomaticSheetTitle {
    /// The longest title kept, in characters; a longer one is cut between words.
    public static let maximumLength = 40
    /// The part of the sheet read to propose a title, in characters.
    public static let maximumContentLength = 1500

    /// A sheet still called « Nouvelle feuille », never offered a title, with
    /// enough content to describe.
    public static func isEligible(_ record: SheetRecord) -> Bool {
        guard !record.automaticTitleAttempted else { return false }
        if let title = record.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return false
        }
        return SheetRecord.noteTitle(in: record.source) == nil && hasMeaningfulContent(record.source)
    }

    /// At least ten visible characters, two of them letters: `x = 2` or `1 + 1 =`
    /// say too little to name a sheet.
    public static func hasMeaningfulContent(_ source: String) -> Bool {
        var visible = 0
        var letters = 0
        for character in source where !character.isWhitespace {
            visible += 1
            if character.isLetter { letters += 1 }
        }
        return visible >= 10 && letters >= 2
    }

    /// The non-blank lines of the sheet, trimmed, up to `maximumContentLength`
    /// characters and never cutting a line.
    public static func content(for source: String) -> String {
        var lines: [String] = []
        var length = 0
        for line in source.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            guard length + text.count <= maximumContentLength else {
                if lines.isEmpty { lines.append(String(text.prefix(maximumContentLength))) }
                break
            }
            lines.append(text)
            length += text.count + 1
        }
        return lines.joined(separator: "\n")
    }

    /// The proposed title on one line, without quotes, marker or final period,
    /// with a capital first letter and at most `maximumLength` characters.
    /// Nil when nothing usable remains.
    public static func sanitized(_ proposal: String) -> String? {
        guard let line = proposal.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty }) else { return nil }
        // Double quotes go wherever they are; single ones only around the title,
        // since ’ is also the French apostrophe.
        var title = String(line.filter { !doubleQuotes.contains($0) })
        title = collapsingSpaces(title)
        title = String(title.drop { $0 == "#" || $0.isWhitespace })
        if let range = title.range(of: #"^titre\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            title.removeSubrange(range)
        }
        title = trimming(title) { singleQuotes.contains($0) || trailingPunctuation.contains($0) || $0.isWhitespace }
        title = shortened(title)
        guard title.contains(where: \.isLetter),
              title.compare(SheetRecord.untitledTitle, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        else { return nil }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    private static let doubleQuotes: Set<Character> = ["\"", "«", "»", "“", "”", "„", "‹", "›"]
    private static let singleQuotes: Set<Character> = ["'", "‘", "’", "`"]
    private static let trailingPunctuation: Set<Character> = [".", "…", ":", ";", ",", "!"]

    /// Single spaces between words, whatever their kind.
    private static func collapsingSpaces(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Removes leading quotes, and trailing quotes and punctuation.
    private static func trimming(_ text: String, trailing isRemoved: (Character) -> Bool) -> String {
        var result = text[...]
        while let first = result.first, singleQuotes.contains(first) || first.isWhitespace {
            result = result.dropFirst()
        }
        while let last = result.last, isRemoved(last) {
            result = result.dropLast()
        }
        return String(result)
    }

    /// Cuts a long title after its last whole word that fits.
    private static func shortened(_ title: String) -> String {
        guard title.count > maximumLength else { return title }
        let prefix = title.prefix(maximumLength + 1)
        let cut = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix.prefix(maximumLength)
        return trimming(String(cut)) { trailingPunctuation.contains($0) || $0.isWhitespace || $0 == "-" || $0 == "–" }
    }
}
