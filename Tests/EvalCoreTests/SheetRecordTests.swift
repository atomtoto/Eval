import Foundation
import XCTest
@testable import EvalCore

final class SheetRecordTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SheetRecordTests-\(UUID().uuidString)", isDirectory: true)
        suiteName = "SheetRecordTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: Titles

    func testDisplayTitlePrefersTheCustomTitle() {
        let record = SheetRecord(customTitle: "  Mécanique – TD 3 ", source: "# Énergie\nx = 2")
        XCTAssertEqual(record.displayTitle, "Mécanique – TD 3")
    }

    func testDisplayTitleUsesTheFirstNoteWithoutItsMarker() {
        XCTAssertEqual(SheetRecord(source: "x = 2\n## Énergie cinétique\n# Autre").displayTitle, "Énergie cinétique")
        XCTAssertEqual(SheetRecord(source: "   // Optique  \nx = 2").displayTitle, "Optique")
        XCTAssertEqual(SheetRecord(customTitle: "   ", source: "#\n# Chute libre").displayTitle, "Chute libre")
    }

    func testDisplayTitleFallsBackWithoutNote() {
        XCTAssertEqual(SheetRecord(source: "x = 2\nx * 3").displayTitle, "Nouvelle feuille")
        XCTAssertEqual(SheetRecord(source: "").displayTitle, "Nouvelle feuille")
    }

    // MARK: Ruler settings of lines that return

    func testRulerSettingsSurviveARemovedLineThatReturns() throws {
        let source = "m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v²"
        var record = SheetRecord(source: source)
        let vID = record.resultSelection.entries[1].id
        record.adjustmentRanges[vID] = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 50, step: 0.5))
        record.manualStepIDs.insert(vID)

        record.source = "m = 80 kg\nE = 0,5 * m * v²"
        record.normalize()
        XCTAssertNotNil(record.adjustmentRanges[vID], "the line may come back (undo, paste)")

        // It survives a save and a reload.
        record = try JSONDecoder().decode(SheetRecord.self, from: JSONEncoder().encode(record))
        record.source = source
        record.normalize()
        XCTAssertEqual(record.resultSelection.entries[1].id, vID)
        XCTAssertEqual(record.adjustmentRanges[vID]?.upperBound, 50)
        XCTAssertTrue(record.manualStepIDs.contains(vID))
    }

    func testRulerSettingsOfForgottenLinesAreDiscarded() throws {
        var record = SheetRecord(source: "a = 1\nb = 2")
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 10, step: 1))
        record.adjustmentRanges = [UUID(): range, record.resultSelection.entries[0].id: range]
        record.normalize()
        XCTAssertEqual(record.adjustmentRanges.count, 1)
    }

    // MARK: New sheets

    func testNewRecordSelectsNothingAndShowsWhatItsLinesRequest() {
        let record = SheetRecord(source: "# Note\nx = 2 m\nx * 3 =\nx == 2 m")
        XCTAssertEqual(record.schemaVersion, 2)
        XCTAssertEqual(SheetRecord.currentSchemaVersion, 2)
        XCTAssertEqual(record.resultSelection.entries.map(\.isSelected), [false, false, false, false])
        XCTAssertEqual(record.source, "# Note\nx = 2 m\nx * 3 =\nx == 2 m")
    }

    // MARK: Line metadata

    func testMetadataOfMissingLinesIsDiscarded() throws {
        let selection = ResultSelection(source: "x = 2\ny = 3", initiallySelectedLineIDs: [])
        let kept = selection.entries[0].id
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 4, step: 1))
        let record = SheetRecord(source: "x = 2", resultSelection: selection,
                                 adjustmentRanges: [kept: range, UUID(): range],
                                 manualStepIDs: [kept, UUID()])
        XCTAssertEqual(record.resultSelection.entries.map(\.id), [kept])
        XCTAssertEqual(Array(record.adjustmentRanges.keys), [kept])
        XCTAssertEqual(record.manualStepIDs, [kept])
    }

    func testCodingRoundTripKeepsEveryField() throws {
        let selection = ResultSelection(source: "v = 72 km/h\nv * 2 s", initiallySelectedLineIDs: [1])
        let lineID = selection.entries[0].id
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 144, step: 0.5))
        let record = SheetRecord(customTitle: "Vitesse", source: "v = 72 km/h\nv * 2 s",
                                 resultSelection: selection, adjustmentRanges: [lineID: range],
                                 manualStepIDs: [lineID],
                                 createdAt: Date(timeIntervalSinceReferenceDate: 1_000.25),
                                 modifiedAt: Date(timeIntervalSinceReferenceDate: 2_000.5))
        let decoded = try JSONDecoder().decode(SheetRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    func testInvalidRulerRangeDoesNotMakeTheSheetUnreadable() throws {
        let record = SheetRecord(source: "x = 2")
        let lineID = record.resultSelection.entries[0].id.uuidString
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object["adjustmentRanges"] = [lineID: ["lowerBound": 5, "upperBound": 1, "step": 1]]
        let decoded = try JSONDecoder().decode(SheetRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.source, "x = 2")
        XCTAssertTrue(decoded.adjustmentRanges.isEmpty)
    }

    func testCaseDifferingDuplicateRangeKeysDoNotCrashDecoding() throws {
        let record = SheetRecord(source: "x = 2")
        let lineID = record.resultSelection.entries[0].id.uuidString
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        let range: [String: Any] = ["lowerBound": 1, "upperBound": 5, "step": 1]
        object["adjustmentRanges"] = [lineID.uppercased(): range, lineID.lowercased(): range]
        let decoded = try JSONDecoder().decode(SheetRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.source, "x = 2")
        XCTAssertLessThanOrEqual(decoded.adjustmentRanges.count, 1)
    }

    func testDuplicateHasItsOwnIdentityAndACopyTitle() {
        let original = SheetRecord(source: "# Énergie cinétique\nE = 2 J\nE",
                                   createdAt: Date(timeIntervalSinceReferenceDate: 0))
        let now = Date(timeIntervalSinceReferenceDate: 50)
        let copy = original.duplicate(now: now)
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.displayTitle, "Énergie cinétique – copie")
        XCTAssertEqual(copy.source, original.source)
        XCTAssertEqual(copy.resultSelection, original.resultSelection)
        XCTAssertEqual(copy.createdAt, now)
        XCTAssertEqual(copy.modifiedAt, now)
    }

    func testResultPreviewShowsTheFirstRequestedValue() throws {
        let record = SheetRecord(source: "# Note\nm = 80 kg\nv = 5 m/s # vitesse\nE = 0,5 * m * v²\nE =\nm =")
        let lines = NotebookEngine.evaluate(record.source).lines
        let energy = try XCTUnwrap(lines[4].quantity)
        XCTAssertEqual(record.resultPreview(), "E = \(QuantityFormatter.string(energy))")

        // A declaration that requests its value comes first when it is first.
        let declared = SheetRecord(source: "m = 80 kg =\nm")
        XCTAssertEqual(declared.resultPreview(), "m = 80 kg")
        // Lines that request nothing show nothing, and neither do failures or equalities.
        XCTAssertNil(SheetRecord(source: "x = 2\nx * 3").resultPreview())
        XCTAssertEqual(SheetRecord(source: "zz =\nx = 2\nx =").resultPreview(), "x = 2")
        XCTAssertNil(SheetRecord(source: "x = 2\nx == 2 =").resultPreview())
    }

    func testResultPreviewIsAlsoSpoken() {
        let record = SheetRecord(source: "m = 3 kg\nv = 2 m/s\nE = 0,5 * m * v^2\nE =")
        XCTAssertEqual(record.resultPreviewWithSpeech()?.text, "E = 6 J")
        XCTAssertEqual(record.resultPreviewWithSpeech()?.spoken, "E égale 6 joules")
        XCTAssertEqual(record.resultPreview(), record.resultPreviewWithSpeech()?.text)
        XCTAssertNil(SheetRecord(source: "x = 2").resultPreviewWithSpeech())
    }

    func testStalePreviewIsIgnored() {
        let record = SheetRecord(source: "x = 2\nx =")
        let evaluation = NotebookEngine.evaluate("x = 2\nx = 3 =")
        XCTAssertNil(SheetRecord.resultPreview(selection: record.resultSelection, evaluation: evaluation))
    }

    func testLinePreviewSkipsEqualitiesAndErrors() throws {
        let lines = NotebookEngine.evaluate("v = 5 m/s # vitesse\nv == 5 m/s\n2 m + 3 s\n# Note").lines
        let speed = try XCTUnwrap(lines[0].quantity)
        XCTAssertEqual(SheetRecord.preview(of: lines[0]), "v = \(QuantityFormatter.string(speed))")
        XCTAssertNil(SheetRecord.preview(of: lines[1]))
        XCTAssertNil(SheetRecord.preview(of: lines[2]))
        XCTAssertNil(SheetRecord.preview(of: lines[3]))
    }

    func testLinePreviewUsesTheRequestedUnit() throws {
        let lines = NotebookEngine.evaluate("v = 20 m/s → km/h\nv → km/h").lines
        XCTAssertEqual(SheetRecord.preview(of: lines[0]), "v = 72 km/h")
        XCTAssertEqual(SheetRecord.preview(of: lines[1]), "v = 72 km/h")
        XCTAssertEqual(lines[1].formattedValue, "72 km/h")
    }

    // MARK: Repository

    func testRepositoryRoundTripSortsByModificationDate() throws {
        let repository = SheetRepository(directory: directory)
        let older = SheetRecord(source: "# A", createdAt: Date(timeIntervalSinceReferenceDate: 10))
        let newer = SheetRecord(source: "# B", createdAt: Date(timeIntervalSinceReferenceDate: 5),
                                modifiedAt: Date(timeIntervalSinceReferenceDate: 20))
        try repository.save(older)
        try repository.save(newer)
        XCTAssertEqual(repository.loadAll(), [newer, older])

        var renamed = older
        renamed.customTitle = "Renommée"
        renamed.modifiedAt = Date(timeIntervalSinceReferenceDate: 30)
        try repository.save(renamed)
        XCTAssertEqual(repository.loadAll().map(\.displayTitle), ["Renommée", "B"])
    }

    func testRepositorySkipsCorruptAndFutureFiles() throws {
        let repository = SheetRepository(directory: directory)
        let record = SheetRecord(source: "# Lisible")
        try repository.save(record)
        try Data("{ pas du JSON".utf8).write(to: directory.appendingPathComponent("\(UUID().uuidString).json"))
        try Data("ignoré".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        var future = SheetRecord(source: "# Futur")
        future.schemaVersion = SheetRecord.currentSchemaVersion + 1
        try repository.save(future)
        XCTAssertEqual(repository.loadAll(), [record])
    }

    func testRepositoryOfMissingDirectoryIsEmpty() throws {
        let repository = SheetRepository(directory: directory.appendingPathComponent("absent"))
        XCTAssertTrue(repository.loadAll().isEmpty)
        XCTAssertNoThrow(try repository.delete(id: UUID()))
    }

    func testRepositoryDeletesOneSheet() throws {
        let repository = SheetRepository(directory: directory)
        let kept = SheetRecord(source: "# Gardée")
        let removed = SheetRecord(source: "# Supprimée")
        try repository.save(kept)
        try repository.save(removed)
        try repository.delete(id: removed.id)
        XCTAssertEqual(repository.loadAll(), [kept])
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.fileURL(for: removed.id).path))
    }

    // MARK: Migration

    func testMigrationBuildsOneRecordFromTheEarlierKeys() throws {
        let source = "# Ma feuille\nx = 2 m\nx * 3"
        var selection = ResultSelection(source: source, initiallySelectedLineIDs: [1])
        selection.setSelected(false, at: 2)
        let lineID = selection.entries[1].id
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 10, step: 0.5))
        defaults.set(source, forKey: LegacyNotebookMigration.sourceKey)
        defaults.set(try JSONEncoder().encode(selection), forKey: LegacyNotebookMigration.resultSelectionKey)
        defaults.set(try JSONEncoder().encode([lineID: range]), forKey: LegacyNotebookMigration.adjustmentRangesKey)
        defaults.set(try JSONEncoder().encode(Set([lineID])), forKey: LegacyNotebookMigration.manualStepKey)
        let repository = SheetRepository(directory: directory)

        let outcome = try LegacyNotebookMigration.run(defaults: defaults, repository: repository) {
            XCTFail("An earlier sheet must not be replaced by the first sheet.")
            return nil
        }

        guard case .migrated(let record) = outcome else { return XCTFail("Unexpected outcome \(outcome)") }
        XCTAssertEqual(record.source, source)
        XCTAssertEqual(record.displayTitle, "Ma feuille")
        XCTAssertEqual(record.resultSelection, selection)
        XCTAssertEqual(record.adjustmentRanges, [lineID: range])
        XCTAssertEqual(record.manualStepIDs, [lineID])
        XCTAssertEqual(repository.loadAll(), [record])
        XCTAssertTrue(defaults.bool(forKey: LegacyNotebookMigration.migratedKey))
        // The earlier keys stay available for a rollback.
        XCTAssertEqual(defaults.string(forKey: LegacyNotebookMigration.sourceKey), source)
        XCTAssertNotNil(defaults.data(forKey: LegacyNotebookMigration.resultSelectionKey))
    }

    func testMigrationWithOnlyASourceUsesDefaultChoices() throws {
        defaults.set("x = 2 m\nx * 3", forKey: LegacyNotebookMigration.sourceKey)
        defaults.set(Data("corrompu".utf8), forKey: LegacyNotebookMigration.resultSelectionKey)
        let record = try XCTUnwrap(LegacyNotebookMigration.legacyRecord(in: defaults))
        // The formula was shown by default: it now asks for its value.
        XCTAssertEqual(record.source, "x = 2 m\nx * 3 =")
        XCTAssertEqual(record.resultSelection.entries.map(\.source), ["x = 2 m", "x * 3 ="])
        XCTAssertEqual(record.schemaVersion, 2)
        XCTAssertTrue(record.adjustmentRanges.isEmpty)
    }

    func testLegacyChosenResultsBecomeRequests() throws {
        let source = "m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v²\nE → kWh # énergie"
        defaults.set(source, forKey: LegacyNotebookMigration.sourceKey)
        let selection = ResultSelection(source: source, initiallySelectedLineIDs: [2, 3])
        defaults.set(try JSONEncoder().encode(selection), forKey: LegacyNotebookMigration.resultSelectionKey)
        let record = try XCTUnwrap(LegacyNotebookMigration.legacyRecord(in: defaults))
        XCTAssertEqual(record.source, "m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v² =\nE → kWh # énergie")
        XCTAssertEqual(record.resultSelection.entries.map(\.id), selection.entries.map(\.id))
    }

    func testMigrationRunsOnlyOnce() throws {
        defaults.set("# Ma feuille", forKey: LegacyNotebookMigration.sourceKey)
        let repository = SheetRepository(directory: directory)
        _ = try LegacyNotebookMigration.run(defaults: defaults, repository: repository)
        let second = try LegacyNotebookMigration.run(defaults: defaults, repository: repository)
        XCTAssertEqual(second, .alreadyMigrated)
        XCTAssertEqual(repository.loadAll().count, 1)
    }

    func testFreshInstallationWritesTheFirstSheet() throws {
        let repository = SheetRepository(directory: directory)
        let first = SheetRecord(customTitle: "Énergie cinétique", source: "# Énergie cinétique")
        let outcome = try LegacyNotebookMigration.run(defaults: defaults, repository: repository) { first }
        XCTAssertEqual(outcome, .seeded(first))
        XCTAssertEqual(repository.loadAll(), [first])
        XCTAssertTrue(defaults.bool(forKey: LegacyNotebookMigration.migratedKey))
    }

    func testExistingLibraryIsNotOverwrittenByTheEarlierSheet() throws {
        let repository = SheetRepository(directory: directory)
        let existing = SheetRecord(source: "# Déjà là")
        try repository.save(existing)
        defaults.set("# Ancienne", forKey: LegacyNotebookMigration.sourceKey)
        XCTAssertEqual(try LegacyNotebookMigration.run(defaults: defaults, repository: repository), .libraryInUse)
        XCTAssertEqual(repository.loadAll(), [existing])
    }

    func testFailedWriteLeavesTheMigrationPending() throws {
        // A regular file where the directory should be makes every write fail.
        try Data().write(to: directory)
        defaults.set("# Ma feuille", forKey: LegacyNotebookMigration.sourceKey)
        let repository = SheetRepository(directory: directory)
        XCTAssertThrowsError(try LegacyNotebookMigration.run(defaults: defaults, repository: repository))
        XCTAssertFalse(defaults.bool(forKey: LegacyNotebookMigration.migratedKey))
        XCTAssertEqual(defaults.string(forKey: LegacyNotebookMigration.sourceKey), "# Ma feuille")
    }
}
