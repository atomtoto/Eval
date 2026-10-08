import Foundation

/// Stores each sheet as one JSON file named after its identifier.
/// Writes are atomic. Unreadable files are skipped rather than failing the library.
public struct SheetRepository: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Application Support/Sheets in the user domain.
    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Sheets", isDirectory: true)
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    /// Every readable sheet, most recently modified first. Corrupt files and
    /// files written by a newer schema are left untouched and ignored.
    public func loadAll() -> [SheetRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        var records: [UUID: SheetRecord] = [:]
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? decoder.decode(SheetRecord.self, from: data),
                  record.schemaVersion <= SheetRecord.currentSchemaVersion else { continue }
            // A copied file may repeat an identifier; keep its latest version.
            if let existing = records[record.id], existing.modifiedAt >= record.modifiedAt { continue }
            records[record.id] = record
        }
        return records.values.sorted(by: Self.isOrderedBefore)
    }

    public func save(_ record: SheetRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: fileURL(for: record.id), options: .atomic)
    }

    /// Removing a sheet that has no file is not an error.
    public func delete(id: UUID) throws {
        do {
            try FileManager.default.removeItem(at: fileURL(for: id))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    /// Most recently modified first; creation order then identity break ties.
    public static func isOrderedBefore(_ lhs: SheetRecord, _ rhs: SheetRecord) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
