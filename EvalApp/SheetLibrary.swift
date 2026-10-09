import EvalCore
import Foundation
import Observation
import os

/// The sheets saved on this device and the editing sessions of open sheets.
/// Edits reach the library at once; files are written after a short pause
/// and when the app leaves the foreground.
@MainActor
@Observable
final class SheetLibrary {
    /// Most recently modified first.
    private(set) var sheets: [SheetRecord] = []
    /// Changes only when a sheet is created or deleted, so views that need
    /// membership are not refreshed by every edit.
    private(set) var sheetIDs: Set<UUID> = []
    /// The sheet a new window opens: the most recent one at launch, then the
    /// latest created. Edits do not change it, unlike the order of `sheets`.
    private(set) var mostRecentSheetID: UUID?

    /// Set when sheets cannot be saved on this device: they live in memory only.
    private(set) var storageProblem: String?

    @ObservationIgnored private var sessions: [UUID: NotebookStore] = [:]
    @ObservationIgnored private var pendingWrites: [UUID: SheetRecord] = [:]
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private let storage: SheetStorage
    /// Sheets whose automatic title is being generated.
    @ObservationIgnored private var titleRequests: Set<UUID> = []

    /// With no repository, the library keeps its sheets in memory, does not
    /// touch the migration state, and reports the problem in `storageProblem`.
    init(repository: SheetRepository? = .standard, defaults: UserDefaults = .standard) {
        storage = SheetStorage(repository: repository)
        guard let repository else {
            SheetStorage.logger.error("Sheet storage is unavailable")
            // The earlier sheet is read, not moved: the next launch can still migrate it.
            replaceSheets(with: [LegacyNotebookMigration.legacyRecord(in: defaults) ?? Self.firstLaunchRecord()])
            storageProblem = Self.unavailableStorageMessage
            return
        }
        do {
            _ = try LegacyNotebookMigration.run(defaults: defaults, repository: repository) {
                Self.firstLaunchRecord()
            }
            replaceSheets(with: repository.loadAll())
        } catch {
            SheetStorage.logger.error("Sheet migration failed: \(error.localizedDescription, privacy: .public)")
            replaceSheets(with: repository.loadAll())
            if sheets.isEmpty {
                // Keep working in memory; the next write retries, and the next
                // launch completes the migration once a sheet file exists.
                let record = LegacyNotebookMigration.legacyRecord(in: defaults) ?? Self.firstLaunchRecord()
                replaceSheets(with: [record])
                scheduleWrite(record)
                storageProblem = Self.unavailableStorageMessage
            }
        }
    }

    private static let unavailableStorageMessage = String(localized: "Eval ne peut pas enregistrer vos feuilles sur cet appareil. Elles seront perdues à la fermeture de l’app. Libérez de l’espace de stockage, puis relancez Eval.")

    func dismissStorageProblem() {
        storageProblem = nil
    }

    func contains(_ id: UUID) -> Bool {
        sheetIDs.contains(id)
    }

    func record(for id: UUID) -> SheetRecord? {
        sheets.first { $0.id == id }
    }

    /// The session of a sheet already open in a window, without opening it.
    func openSession(for id: UUID) -> NotebookStore? {
        sessions[id]
    }

    /// Opens the sheet, or returns the session other windows already share.
    func session(for id: UUID) -> NotebookStore? {
        guard contains(id) else { return nil }
        if let session = sessions[id] { return session }
        guard let record = record(for: id) else { return nil }
        let session = NotebookStore(record: record) { [weak self] updated in
            self?.update(updated)
        }
        sessions[id] = session
        return session
    }

    // MARK: Library actions

    @discardableResult
    func createSheet(source: String = "", customTitle: String? = nil) -> UUID {
        add(SheetRecord(customTitle: customTitle, source: source))
    }

    @discardableResult
    func createSheet(from example: ExampleSheet) -> UUID {
        add(Self.record(from: example))
    }

    @discardableResult
    func duplicateSheet(id: UUID) -> UUID? {
        guard let record = record(for: id) else { return nil }
        return add(record.duplicate())
    }

    /// An empty title, or the sheet's own note title, restores the automatic title.
    func renameSheet(id: UUID, to title: String) {
        guard var record = record(for: id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let automaticTitle = SheetRecord.noteTitle(in: record.source) ?? SheetRecord.untitledTitle
        let customTitle: String? = trimmed.isEmpty || (record.customTitle == nil && trimmed == automaticTitle)
            ? nil : trimmed
        if let session = sessions[id] {
            session.customTitle = customTitle
            return
        }
        guard customTitle != record.customTitle else { return }
        record.customTitle = customTitle
        record.automaticTitleAttempted = true
        record.modifiedAt = Date()
        update(record)
    }

    /// Asks Apple Intelligence, on the device, to name a sheet the user leaves
    /// for the first time while it is still « Nouvelle feuille ». The title
    /// arrives later, unless the sheet was named meanwhile; nothing happens
    /// when the setting is off or the model is unavailable.
    func suggestTitleIfNeeded(for id: UUID) {
        guard AutomaticTitleSetting.isEnabled, !titleRequests.contains(id),
              let record = sessions[id]?.record ?? record(for: id),
              AutomaticSheetTitle.isEligible(record),
              SheetTitleGenerator.isAvailable else { return }
        titleRequests.insert(id)
        let content = AutomaticSheetTitle.content(for: record.source)
        Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                await SheetTitleGenerator.title(for: content)
            }.value
            self?.finishTitleRequest(for: id, with: outcome)
        }
    }

    private func finishTitleRequest(for id: UUID, with outcome: SheetTitleGenerator.Outcome) {
        titleRequests.remove(id)
        let title: String?
        switch outcome {
        case .title(let proposal): title = proposal
        case .noTitle: title = nil
        case .retryLater: return
        }
        if let session = sessions[id] {
            session.applyAutomaticTitle(title)
        } else if var record = record(for: id), !record.automaticTitleAttempted {
            record.automaticTitleAttempted = true
            if let title, record.displayTitle == SheetRecord.untitledTitle {
                record.customTitle = title
            }
            update(record)
        }
    }

    func deleteSheet(id: UUID) {
        sessions.removeValue(forKey: id)?.close()
        pendingWrites[id] = nil
        sheets.removeAll { $0.id == id }
        sheetIDs.remove(id)
        if mostRecentSheetID == id { mostRecentSheetID = sheets.first?.id }
        storage.delete(id: id)
    }

    /// Writes pending edits now. Waiting guarantees that they reach the disk
    /// before the app is suspended.
    func flush(waitUntilWritten: Bool = false) {
        writeTask?.cancel()
        writeTask = nil
        for record in pendingWrites.values {
            storage.save(record)
        }
        pendingWrites.removeAll()
        if waitUntilWritten {
            storage.waitUntilFinished()
        }
    }

    // MARK: Private

    private static func record(from example: ExampleSheet) -> SheetRecord {
        SheetRecord(customTitle: example.title, source: example.source)
    }

    /// The first sheet of a new installation: the kinetic energy example.
    private static func firstLaunchRecord() -> SheetRecord {
        record(from: ExampleLibrary.example(id: "kinetic-energy") ?? ExampleLibrary.all[0])
    }

    private func replaceSheets(with records: [SheetRecord]) {
        sheets = records.sorted(by: SheetRepository.isOrderedBefore)
        sheetIDs = Set(records.map(\.id))
        mostRecentSheetID = sheets.first?.id
    }

    private func add(_ record: SheetRecord) -> UUID {
        var updated = sheets
        updated.insert(record, at: insertionIndex(for: record, in: updated))
        sheets = updated
        sheetIDs.insert(record.id)
        mostRecentSheetID = record.id
        storage.save(record)
        return record.id
    }

    private func update(_ record: SheetRecord) {
        guard let index = sheets.firstIndex(where: { $0.id == record.id }) else { return }
        var updated = sheets
        updated.remove(at: index)
        updated.insert(record, at: insertionIndex(for: record, in: updated))
        sheets = updated
        scheduleWrite(record)
    }

    private func insertionIndex(for record: SheetRecord, in records: [SheetRecord]) -> Int {
        records.firstIndex { SheetRepository.isOrderedBefore(record, $0) } ?? records.endIndex
    }

    private func scheduleWrite(_ record: SheetRecord) {
        pendingWrites[record.id] = record
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            self?.flush()
        }
    }
}

/// Writes sheet files on a serial background queue, in the order requested,
/// so a deletion always follows the writes that preceded it.
final class SheetStorage: Sendable {
    static let logger = Logger(subsystem: "com.atom.Eval", category: "Sheets")
    private let repository: SheetRepository?
    private let queue = DispatchQueue(label: "com.atom.Eval.sheets", qos: .utility)

    init(repository: SheetRepository?) {
        self.repository = repository
    }

    func save(_ record: SheetRecord) {
        guard let repository else { return }
        queue.async {
            do {
                try repository.save(record)
            } catch {
                Self.logger.error("Sheet write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func delete(id: UUID) {
        guard let repository else { return }
        queue.async {
            do {
                try repository.delete(id: id)
            } catch {
                Self.logger.error("Sheet deletion failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func waitUntilFinished() {
        queue.sync {}
    }
}

extension SheetRepository {
    /// Application Support/Sheets; nil when that folder is unavailable. There is
    /// no fallback to a temporary folder, which the system may empty at any time.
    static var standard: SheetRepository? {
        (try? SheetRepository.defaultDirectory()).map { SheetRepository(directory: $0) }
    }
}
