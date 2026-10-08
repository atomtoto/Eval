import Foundation

/// One calculation sheet and the metadata attached to its lines: the chosen
/// results and the ruler settings. A library stores one record per file.
public struct SheetRecord: Identifiable, Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let untitledTitle = "Nouvelle feuille"

    public let id: UUID
    /// A title chosen by the user. When absent, the first note of the sheet names it.
    public var customTitle: String?
    public var source: String
    public var resultSelection: ResultSelection
    /// Ruler bounds and steps, keyed by the line identities of `resultSelection`.
    public var adjustmentRanges: [UUID: VariableAdjustmentRange]
    /// Lines whose ruler uses a manual step instead of the entered precision.
    public var manualStepIDs: Set<UUID>
    public var createdAt: Date
    public var modifiedAt: Date
    public var schemaVersion: Int

    /// A missing selection shows the results of formulas and equalities, like a
    /// new sheet. Metadata of lines that are neither in `source` nor recently
    /// removed from it is discarded.
    public init(
        id: UUID = UUID(),
        customTitle: String? = nil,
        source: String,
        resultSelection: ResultSelection? = nil,
        adjustmentRanges: [UUID: VariableAdjustmentRange] = [:],
        manualStepIDs: Set<UUID> = [],
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        schemaVersion: Int = SheetRecord.currentSchemaVersion
    ) {
        self.id = id
        self.customTitle = customTitle
        self.source = source
        self.resultSelection = resultSelection ?? Self.defaultSelection(for: source)
        self.adjustmentRanges = adjustmentRanges
        self.manualStepIDs = manualStepIDs
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.schemaVersion = schemaVersion
        normalize()
    }

    /// The custom title, else the first note (`# Titre` or `// Titre`), else « Nouvelle feuille ».
    public var displayTitle: String {
        if let title = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return Self.noteTitle(in: source) ?? Self.untitledTitle
    }

    /// The text of the first non-empty note line, without its marker.
    public static func noteTitle(in source: String) -> String? {
        for line in source.split(whereSeparator: \.isNewline) {
            var text = line.trimmingCharacters(in: .whitespaces)[...]
            if text.hasPrefix("#") {
                text = text.drop { $0 == "#" }
            } else if text.hasPrefix("//") {
                text = text.drop { $0 == "/" }
            } else {
                continue
            }
            let title = text.trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return nil
    }

    /// Formulas and equalities show their result, and so do declarations that ask
    /// for it with a conversion (`v = d / t → km/h`) or as an unknown (`v = ? m/s`).
    /// Other declarations and notes start hidden.
    public static func defaultSelection(for source: String) -> ResultSelection {
        let lines = NotebookEngine.evaluate(source).lines
        let explicit = lines.filter {
            $0.kind == .expression || $0.kind == .equation
                || ($0.kind == .definition && LineSyntax($0.source).requestsValue)
        }.map(\.id)
        return ResultSelection(source: source, initiallySelectedLineIDs: Set(explicit))
    }

    /// Keeps the line metadata consistent with the current source. Metadata
    /// of a line removed by a recent edit stays, since the line may return.
    public mutating func normalize() {
        resultSelection.reconcile(source: source)
        let lineIDs = resultSelection.retainedIDs
        adjustmentRanges = adjustmentRanges.filter { lineIDs.contains($0.key) }
        manualStepIDs.formIntersection(adjustmentRanges.keys)
    }

    /// A copy with its own identity, titled « Titre – copie ».
    public func duplicate(id: UUID = UUID(), now: Date = Date()) -> SheetRecord {
        SheetRecord(id: id, customTitle: displayTitle + " – copie", source: source,
                    resultSelection: resultSelection, adjustmentRanges: adjustmentRanges,
                    manualStepIDs: manualStepIDs, createdAt: now)
    }

    // MARK: Library preview

    /// A result as shown in the library, and as read aloud.
    public struct ResultPreview: Sendable, Equatable {
        /// « E = 1 000 J ».
        public let text: String
        /// « E égale 1 000 joules ».
        public let spoken: String

        public init(text: String, spoken: String) {
            self.text = text
            self.spoken = spoken
        }
    }

    /// The first chosen result that has a value, as « E = 1 000 J ».
    /// Evaluates the sheet; call it away from the main thread for large sheets.
    public func resultPreview() -> String? {
        resultPreviewWithSpeech()?.text
    }

    /// The same preview with its spoken form. Evaluates the sheet.
    public func resultPreviewWithSpeech() -> ResultPreview? {
        Self.resultPreviewWithSpeech(selection: resultSelection, evaluation: NotebookEngine.evaluate(source))
    }

    public static func resultPreview(selection: ResultSelection, evaluation: NotebookEvaluation) -> String? {
        resultPreviewWithSpeech(selection: selection, evaluation: evaluation)?.text
    }

    public static func resultPreviewWithSpeech(selection: ResultSelection, evaluation: NotebookEvaluation) -> ResultPreview? {
        for line in evaluation.lines where selection.isSelected(at: line.id) {
            guard selection.entries[line.id].source == line.source,
                  let preview = previewWithSpeech(of: line) else { continue }
            return preview
        }
        return nil
    }

    /// « E = 1 000 J » for a computed value; nil for an equality or an error.
    public static func preview(of line: EvaluatedLine) -> String? {
        previewWithSpeech(of: line)?.text
    }

    /// The preview of a line with its spoken form; nil for an equality or an error.
    public static func previewWithSpeech(of line: EvaluatedLine) -> ResultPreview? {
        guard line.status == .success, line.kind != .equation, let value = line.formattedValue else { return nil }
        let label = previewLabel(for: line)
        let spokenLabel = MathSpeech.description(label) ?? label
        return ResultPreview(text: "\(label) = \(value)",
                             spoken: "\(spokenLabel) égale \(line.spokenResult ?? value)")
    }

    private static func previewLabel(for line: EvaluatedLine) -> String {
        // Without the comment and the conversion, which the value already reflects.
        var content = LineSyntax(line.source).body[...]
        if line.kind == .definition, let separator = content.firstIndex(of: "=") {
            content = content[..<separator]
        }
        return content.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case id, customTitle, source, resultSelection, adjustmentRanges, manualStepIDs
        case createdAt, modifiedAt, schemaVersion
    }

    /// Line metadata is decoded leniently: an invalid ruler range or selection
    /// is dropped rather than making the whole sheet unreadable.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        customTitle = try values.decodeIfPresent(String.self, forKey: .customTitle)
        source = try values.decode(String.self, forKey: .source)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        resultSelection = (try? values.decode(ResultSelection.self, forKey: .resultSelection))
            ?? Self.defaultSelection(for: source)
        let ranges = (try? values.decode([String: LossyRange].self, forKey: .adjustmentRanges)) ?? [:]
        // Keys differing only by case parse to the same UUID: keep the first, never trap.
        adjustmentRanges = Dictionary(ranges.sorted { $0.key < $1.key }.compactMap { key, range in
            guard let id = UUID(uuidString: key), let value = range.value else { return nil }
            return (id, value)
        }, uniquingKeysWith: { first, _ in first })
        let steps = (try? values.decode([String].self, forKey: .manualStepIDs)) ?? []
        manualStepIDs = Set(steps.compactMap(UUID.init(uuidString:)))
        normalize()
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encodeIfPresent(customTitle, forKey: .customTitle)
        try values.encode(source, forKey: .source)
        try values.encode(resultSelection, forKey: .resultSelection)
        try values.encode(Dictionary(uniqueKeysWithValues: adjustmentRanges.map { ($0.key.uuidString, $0.value) }),
                          forKey: .adjustmentRanges)
        try values.encode(manualStepIDs.map(\.uuidString).sorted(), forKey: .manualStepIDs)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(modifiedAt, forKey: .modifiedAt)
        try values.encode(schemaVersion, forKey: .schemaVersion)
    }

    private struct LossyRange: Decodable {
        let value: VariableAdjustmentRange?

        init(from decoder: any Decoder) throws {
            value = try? VariableAdjustmentRange(from: decoder)
        }
    }
}
