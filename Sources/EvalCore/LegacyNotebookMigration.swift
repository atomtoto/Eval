import Foundation

/// Moves the single sheet of earlier versions, kept in UserDefaults, into a
/// sheet library. The new file is written before the migration is marked done,
/// and the earlier keys are kept so that a previous version can still read them.
public enum LegacyNotebookMigration {
    public static let sourceKey = "eval.notebook.source.v1"
    public static let resultSelectionKey = "eval.notebook.resultSelection.v1"
    public static let adjustmentRangesKey = "eval.notebook.adjustmentRanges.v1"
    public static let manualStepKey = "eval.notebook.manualStep.v1"
    public static let migratedKey = "eval.library.migrated.v1"

    public enum Outcome: Equatable, Sendable {
        /// An earlier launch already completed the migration.
        case alreadyMigrated
        /// The library already contained sheets; nothing was imported.
        case libraryInUse
        /// The earlier sheet was written to the library.
        case migrated(SheetRecord)
        /// No earlier sheet existed; the first sheet was written instead.
        case seeded(SheetRecord)
        /// No earlier sheet and no first sheet to write.
        case nothingToMigrate
    }

    /// Builds a record from the earlier keys, or nil when no sheet was saved.
    /// Unreadable choices fall back to the defaults, as earlier versions did.
    public static func legacyRecord(in defaults: UserDefaults, now: Date = Date()) -> SheetRecord? {
        guard let source = defaults.string(forKey: sourceKey) else { return nil }
        let decoder = JSONDecoder()
        let selection = defaults.data(forKey: resultSelectionKey)
            .flatMap { try? decoder.decode(ResultSelection.self, from: $0) }
        let ranges = defaults.data(forKey: adjustmentRangesKey)
            .flatMap { try? decoder.decode([UUID: VariableAdjustmentRange].self, from: $0) } ?? [:]
        let manualSteps = defaults.data(forKey: manualStepKey)
            .flatMap { try? decoder.decode(Set<UUID>.self, from: $0) } ?? []
        return SheetRecord(source: source, resultSelection: selection, adjustmentRanges: ranges,
                           manualStepIDs: manualSteps, createdAt: now)
    }

    /// Runs once per installation. `firstSheet` supplies the sheet of a new
    /// installation; it is written only when there is nothing to migrate.
    /// A failed write throws and leaves the migration pending for the next launch.
    public static func run(
        defaults: UserDefaults,
        repository: SheetRepository,
        now: Date = Date(),
        firstSheet: () -> SheetRecord? = { nil }
    ) throws -> Outcome {
        guard !defaults.bool(forKey: migratedKey) else { return .alreadyMigrated }
        guard repository.loadAll().isEmpty else {
            defaults.set(true, forKey: migratedKey)
            return .libraryInUse
        }
        let outcome: Outcome
        if let record = legacyRecord(in: defaults, now: now) {
            try repository.save(record)
            outcome = .migrated(record)
        } else if let record = firstSheet() {
            try repository.save(record)
            outcome = .seeded(record)
        } else {
            outcome = .nothingToMigrate
        }
        defaults.set(true, forKey: migratedKey)
        return outcome
    }
}
