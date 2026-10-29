import EvalCore
import Foundation

/// The sheets saved on this device and the editors of open sheets, as the iOS
/// `SheetLibrary`. Edits reach the library at once; files are written by
/// `flush()`, which the app calls `writeDelayMillis` after the last change and
/// when it leaves the foreground.
///
/// Use it from the main thread, except `flush()` and `hasPendingWrites`, which
/// any thread may call: files can be written away from the main thread.
public final class SheetLibrary: @unchecked Sendable {
    /// iOS writes the files of edited sheets after this pause.
    public static let writeDelayMillis: Int64 = 500
    /// How long iOS offers Annuler after deleting a sheet, which it does without confirmation.
    public static let deletionUndoMillis: Int64 = 6_000
    public static let unavailableStorageMessage: String = "Eval ne peut pas enregistrer vos feuilles sur cet appareil. Elles seront perdues à la fermeture de l’app. Libérez de l’espace de stockage, puis relancez Eval."

    /// Set when sheets cannot be saved on this device: they live in memory only.
    public private(set) var storageProblem: String?
    /// Increases with every change of the list: a sheet created, deleted, renamed or edited.
    public private(set) var revision: Int64 = 0

    /// Most recently modified first.
    private var records: [SheetRecord] = []
    /// The sheet shown when none is chosen: the most recent one at launch, then
    /// the latest created. Edits do not change it.
    private var mostRecentID: UUID?
    private var editors: [UUID: SheetEditor] = [:]
    /// Nil when the folder cannot be created: nothing is written.
    private let repository: SheetRepository?
    /// Guards `operations` and `pendingWrites`, which `flush()` takes from any thread.
    private let lock = NSLock()
    /// Keeps file operations in the order requested, so a deletion follows the writes before it.
    private let writeLock = NSLock()
    private var operations: [FileOperation] = []
    private var pendingWrites: [UUID: SheetRecord] = [:]

    private enum FileOperation {
        case save(SheetRecord)
        case delete(UUID)
    }

    /// `directory` holds one JSON file per sheet, such as `filesDir/Sheets`. The
    /// first launch writes the example « Énergie cinétique », as on iOS. When the
    /// folder cannot be used, the sheets live in memory and `storageProblem` says so.
    public init(directory: String) {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            repository = nil
            replaceSheets(with: [Self.firstLaunchRecord()])
            storageProblem = Self.unavailableStorageMessage
            return
        }
        let repository = SheetRepository(directory: url)
        self.repository = repository
        do {
            try Self.seedIfNeeded(repository)
            replaceSheets(with: repository.loadAll())
        } catch {
            replaceSheets(with: repository.loadAll())
            if records.isEmpty {
                // Keeps working in memory; the next flush retries, and the next
                // launch writes the first sheet once the folder accepts files.
                let record = Self.firstLaunchRecord()
                replaceSheets(with: [record])
                lock.withLock { pendingWrites[record.id] = record }
                storageProblem = Self.unavailableStorageMessage
            }
        }
    }

    public func dismissStorageProblem() {
        storageProblem = nil
    }

    public var isEmpty: Bool {
        records.isEmpty
    }

    public var mostRecentSheetId: String? {
        mostRecentID?.uuidString
    }

    public func contains(id: String) -> Bool {
        uuid(id).map { id in records.contains { $0.id == id } } ?? false
    }

    /// The sheets in the order of the iOS list, most recently modified first. A
    /// search keeps those whose title or text contains it, ignoring case and accents.
    public func sheets(matching search: String = "") -> [SheetSummary] {
        records.filter { record in
            search.isEmpty || TextSearch.contains(record.displayTitle, search) || TextSearch.contains(record.source, search)
        }.map(summary)
    }

    public func sheet(id: String) -> SheetSummary? {
        record(for: id).map(summary)
    }

    /// The example sheets of the « Nouvelle à partir d’un exemple » menu, by domain.
    public static func exampleCategories() -> [ExampleCategory] {
        ExampleDomain.allCases.map { domain in
            ExampleCategory(id: domain.rawValue, title: domain.title,
                            examples: ExampleLibrary.examples(in: domain).map {
                                ExampleInfo(id: $0.id, title: $0.title, summary: $0.summary)
                            })
        }
    }

    // MARK: Editors

    /// Opens the sheet for editing, or returns its editor if it is already open.
    public func openEditor(id: String) -> SheetEditor? {
        guard let record = record(for: id) else { return nil }
        if let editor = editors[record.id] { return editor }
        let editor = SheetEditor(record: record, library: self)
        editors[record.id] = editor
        return editor
    }

    /// The editor of a sheet already open, without opening it.
    public func openedEditor(id: String) -> SheetEditor? {
        uuid(id).flatMap { editors[$0] }
    }

    // MARK: Library actions

    @discardableResult
    public func createSheet(source: String = "", title: String? = nil) -> String {
        add(SheetRecord(customTitle: title, source: source))
    }

    /// A new sheet from an example of `exampleCategories()`, named after it.
    public func createSheetFromExample(id: String) -> String? {
        ExampleLibrary.example(id: id).map { add(Self.record(from: $0)) }
    }

    /// A copy titled « Titre – copie », listed first.
    @discardableResult
    public func duplicateSheet(id: String) -> String? {
        record(for: id).map { add($0.duplicate()) }
    }

    /// An empty title, or the sheet's own note title, restores the automatic title.
    public func renameSheet(id: String, title: String) {
        guard var record = record(for: id) else { return }
        let customTitle = SheetSession.customTitle(renaming: record, to: title)
        if let editor = editors[record.id] {
            editor.session.customTitle = customTitle
            return
        }
        guard customTitle != record.customTitle else { return }
        record.customTitle = customTitle
        record.automaticTitleAttempted = true
        record.modifiedAt = Date()
        update(record)
    }

    /// Deletes the sheet at once and returns it as it was, for `restoreSheet(_:)`.
    /// Its editor is closed.
    @discardableResult
    public func deleteSheet(id: String) -> DeletedSheet? {
        guard let id = uuid(id), let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = editors[id]?.session.record ?? records[index]
        editors.removeValue(forKey: id)?.close()
        records.remove(at: index)
        if mostRecentID == id { mostRecentID = records.first?.id }
        lock.withLock {
            pendingWrites[id] = nil
            operations.append(.delete(id))
        }
        revision += 1
        return DeletedSheet(id: id.uuidString, title: removed.displayTitle, record: removed)
    }

    /// Brings back a deleted sheet, at the place its modification date gives it.
    public func restoreSheet(_ sheet: DeletedSheet) {
        let record = sheet.record
        guard !records.contains(where: { $0.id == record.id }) else { return }
        records.insert(record, at: insertionIndex(for: record))
        if mostRecentID == nil { mostRecentID = record.id }
        lock.withLock { operations.append(.save(record)) }
        revision += 1
    }

    // MARK: Files

    /// True while changes wait for `flush()`. Any thread.
    public var hasPendingWrites: Bool {
        lock.withLock { !operations.isEmpty || !pendingWrites.isEmpty }
    }

    /// Writes and deletes files now, in the order of the changes, and returns
    /// false if one of them failed. Any thread: call it away from the main thread.
    @discardableResult
    public func flush() -> Bool {
        writeLock.withLock {
            let (operations, writes) = lock.withLock {
                defer {
                    self.operations.removeAll()
                    pendingWrites.removeAll()
                }
                return (self.operations, Array(pendingWrites.values))
            }
            guard let repository else { return true }
            var succeeded = true
            for operation in operations + writes.map(FileOperation.save) {
                do {
                    switch operation {
                    case .save(let record): try repository.save(record)
                    case .delete(let id): try repository.delete(id: id)
                    }
                } catch {
                    succeeded = false
                }
            }
            return succeeded
        }
    }

    // MARK: Internal

    /// An edit of an open sheet: the list follows it, and its file is written at the next flush.
    func update(_ record: SheetRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records.remove(at: index)
        records.insert(record, at: insertionIndex(for: record))
        lock.withLock { pendingWrites[record.id] = record }
        revision += 1
    }

    func record(for id: String) -> SheetRecord? {
        uuid(id).flatMap { id in records.first { $0.id == id } }
    }

    private func summary(_ record: SheetRecord) -> SheetSummary {
        guard let editor = editors[record.id] else { return SheetSummary(record: record, openPreview: nil, isOpen: false) }
        let session = editor.session
        let preview = session.resultPreview.flatMap { text in
            session.spokenResultPreview.map { ResultPreview(text: text, spoken: $0) }
        }
        return SheetSummary(record: record, openPreview: preview, isOpen: true)
    }

    private func add(_ record: SheetRecord) -> String {
        records.insert(record, at: insertionIndex(for: record))
        mostRecentID = record.id
        lock.withLock { operations.append(.save(record)) }
        revision += 1
        return record.id.uuidString
    }

    private func replaceSheets(with sheets: [SheetRecord]) {
        records = sheets.sorted(by: SheetRepository.isOrderedBefore)
        mostRecentID = records.first?.id
        revision += 1
    }

    private func insertionIndex(for record: SheetRecord) -> Int {
        records.firstIndex { SheetRepository.isOrderedBefore(record, $0) } ?? records.endIndex
    }

    private func uuid(_ id: String) -> UUID? {
        UUID(uuidString: id)
    }

    private static func record(from example: ExampleSheet) -> SheetRecord {
        SheetRecord(customTitle: example.title, source: example.source)
    }

    /// The first sheet of a new installation: the kinetic energy example.
    private static func firstLaunchRecord() -> SheetRecord {
        record(from: ExampleLibrary.example(id: "kinetic-energy") ?? ExampleLibrary.all[0])
    }

    /// Runs once per installation, as the iOS migration: an empty library gets
    /// its first sheet. A failed write throws and leaves it for the next launch.
    private static func seedIfNeeded(_ repository: SheetRepository) throws {
        let marker = repository.directory.appendingPathComponent(".library-initialized")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        if repository.loadAll().isEmpty {
            try repository.save(firstLaunchRecord())
        }
        try Data().write(to: marker, options: .atomic)
    }
}

/// A row of the sheet list: title, modification date and first displayed result.
public struct SheetSummary: Hashable, Sendable {
    public let id: String
    /// The custom title, else the first note (`# Titre`), else « Nouvelle feuille ».
    public let title: String
    /// Milliseconds since 1970.
    public let modifiedAt: Int64
    public let createdAt: Int64
    /// The text of the sheet, for sharing it from the list.
    public let source: String
    /// True when an editor has the sheet open: its preview is then already known.
    public let isOpen: Bool
    let record: SheetRecord
    let openPreview: ResultPreview?

    init(record: SheetRecord, openPreview: ResultPreview?, isOpen: Bool) {
        id = record.id.uuidString
        title = record.displayTitle
        modifiedAt = record.modifiedAt.millisecondsSince1970
        createdAt = record.createdAt.millisecondsSince1970
        source = record.source
        self.isOpen = isOpen
        self.record = record
        self.openPreview = openPreview
    }

    /// The first requested value that has a result, « E = 1000 J », as the iOS row
    /// shows it. An open sheet gives its current one; any other is evaluated, so
    /// call this away from the main thread. Any thread.
    public func resultPreview() -> ResultPreview? {
        if isOpen { return openPreview }
        return record.resultPreviewWithSpeech().map { ResultPreview(text: $0.text, spoken: $0.spoken) }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(modifiedAt)
        hasher.combine(openPreview)
    }
}

/// A result as the sheet list shows it, and as TalkBack reads it.
public struct ResultPreview: Hashable, Sendable {
    /// « E = 1000 J ».
    public let text: String
    /// « E égale 1000 joules ».
    public let spoken: String
}

/// A deleted sheet, kept so that Annuler can restore it.
public struct DeletedSheet: Sendable {
    public let id: String
    /// For « « Titre » supprimée ».
    public let title: String
    let record: SheetRecord
}

/// A domain of example sheets, such as « Mécanique ».
public struct ExampleCategory: Hashable, Sendable {
    public let id: String
    public let title: String
    public let examples: [ExampleInfo]
}

public struct ExampleInfo: Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
}

extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }
}
