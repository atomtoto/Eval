import Foundation
import Testing
@testable import EvalBridge

@Suite struct SheetLibraryTests {
    /// A library in a folder of its own, removed after the test.
    private func withLibrary(_ body: (SheetLibrary, URL) throws -> Void) rethrows {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EvalBridgeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let directory = folder.appendingPathComponent("Sheets")
        try body(SheetLibrary(directory: directory.path), directory)
    }

    private func file(_ id: String, in directory: URL) -> String {
        directory.appendingPathComponent(id).appendingPathExtension("json").path
    }

    @Test func aNewInstallationStartsWithTheKineticEnergyExampleOnce() throws {
        try withLibrary { library, directory in
            let sheets = library.sheets()
            #expect(sheets.map(\.title) == ["Énergie cinétique"])
            #expect(library.storageProblem == nil)
            #expect(FileManager.default.fileExists(atPath: file(sheets[0].id, in: directory)))
            #expect(library.mostRecentSheetId == sheets[0].id)

            // Emptied by the person, the library stays empty at the next launch.
            library.deleteSheet(id: sheets[0].id)
            #expect(library.flush())
            let relaunched = SheetLibrary(directory: directory.path)
            #expect(relaunched.isEmpty)
            #expect(relaunched.mostRecentSheetId == nil)
        }
    }

    @Test func sheetsAreListedMostRecentFirstWithTheirIOSTitles() throws {
        try withLibrary { library, _ in
            let untitled = library.createSheet()
            let noted = library.createSheet(source: "// Pendule\nT = 2 * pi * sqrt(l / g)")
            let named = library.createSheet(source: "# Note", title: "  Mon calcul ")
            let sheets = library.sheets()
            #expect(sheets.prefix(3).map(\.id) == [named, noted, untitled])
            #expect(sheets.prefix(3).map(\.title) == ["Mon calcul", "Pendule", "Nouvelle feuille"])
            #expect(library.mostRecentSheetId == named)
            #expect(sheets[0].modifiedAt >= sheets[1].modifiedAt)
        }
    }

    @Test func searchMatchesTitlesAndTextIgnoringCaseAndAccents() throws {
        try withLibrary { library, _ in
            let electricity = library.createSheet(source: "# Électricité\nU = R * I")
            #expect(library.sheets(matching: "electricite").map(\.id) == [electricity])
            #expect(library.sheets(matching: "r * i").map(\.id) == [electricity])
            #expect(library.sheets(matching: "CINÉTIQUE").map(\.title) == ["Énergie cinétique"])
            #expect(library.sheets(matching: "introuvable").isEmpty)
            #expect(library.sheets(matching: "").count == 2)
        }
    }

    @Test func examplesAreGroupedByDomainAsOnIOS() throws {
        let categories = SheetLibrary.exampleCategories()
        #expect(categories.map(\.title) == ["Mécanique", "Électricité", "Optique et ondes", "Thermodynamique",
                                            "Quantique", "Astronomie", "Méthode"])
        #expect(categories[0].examples.map(\.id).contains("kinetic-energy"))
        #expect(categories.allSatisfy { !$0.examples.isEmpty })

        try withLibrary { library, _ in
            let id = try #require(library.createSheetFromExample(id: "free-fall"))
            #expect(library.sheet(id: id)?.title == "Chute libre")
            #expect(library.sheets().first?.id == id)
            #expect(library.createSheetFromExample(id: "inconnu") == nil)
        }
    }

    @Test func aDuplicateIsACopyListedFirst() throws {
        try withLibrary { library, _ in
            let original = try #require(library.sheets().first)
            let copy = try #require(library.duplicateSheet(id: original.id))
            #expect(copy != original.id)
            #expect(library.sheets().first?.title == "Énergie cinétique – copie")
            #expect(library.sheet(id: copy)?.source == original.source)
            #expect(library.mostRecentSheetId == copy)
            #expect(library.duplicateSheet(id: "pas-un-identifiant") == nil)
        }
    }

    @Test func aDeletedSheetComesBackWithItsFile() throws {
        try withLibrary { library, directory in
            let id = library.createSheet(source: "x = 1")
            let editor = try #require(library.openEditor(id: id))
            let path = file(id, in: directory)
            #expect(library.flush())
            #expect(FileManager.default.fileExists(atPath: path))

            let deleted = try #require(library.deleteSheet(id: id))
            #expect(deleted.id == id)
            #expect(deleted.title == "Nouvelle feuille")
            #expect(!library.contains(id: id))
            #expect(editor.isClosed)
            #expect(library.openEditor(id: id) == nil)
            #expect(library.flush())
            #expect(!FileManager.default.fileExists(atPath: path))

            library.restoreSheet(deleted)
            library.restoreSheet(deleted)
            #expect(library.sheets().filter { $0.id == id }.count == 1)
            #expect(library.flush())
            #expect(FileManager.default.fileExists(atPath: path))
        }
    }

    @Test func renamingFollowsTheLibraryRule() throws {
        try withLibrary { library, _ in
            let id = library.createSheet(source: "# Chute\nd = 0,5 * g * t²")
            library.renameSheet(id: id, title: "  Chute libre  ")
            #expect(library.sheet(id: id)?.title == "Chute libre")
            // An empty title, or the note title, restores the automatic title.
            library.renameSheet(id: id, title: "")
            #expect(library.sheet(id: id)?.title == "Chute")
            library.renameSheet(id: id, title: "Chute")
            #expect(library.openEditor(id: id)?.customTitle == nil)

            // Through the open editor, as the title of the iOS sheet does.
            let editor = try #require(library.openedEditor(id: id))
            editor.rename("Gravité")
            #expect(library.sheet(id: id)?.title == "Gravité")
            library.renameSheet(id: id, title: "Pesanteur")
            #expect(editor.title == "Pesanteur")
        }
    }

    @Test func editsReachTheListAndTheFiles() throws {
        try withLibrary { library, directory in
            let id = library.createSheet(source: "x = 2\ny = x * 3 =")
            #expect(library.flush())
            let editor = try #require(library.openEditor(id: id))
            #expect(library.openEditor(id: id) === editor)
            let revision = library.revision

            #expect(editor.beginEditing(lineId: editor.lines()[0].id))
            editor.updateEditedLine("x = 4")
            editor.endEditing()
            editor.editAsText("# Titre\n" + editor.source)
            #expect(library.revision > revision)
            #expect(library.sheets().first?.title == "Titre")
            #expect(library.hasPendingWrites)
            #expect(library.flush())
            #expect(!library.hasPendingWrites)

            let relaunched = SheetLibrary(directory: directory.path)
            #expect(relaunched.sheets().first?.id == id)
            #expect(relaunched.sheet(id: id)?.source == "# Titre\nx = 4\ny = x * 3 =")
        }
    }

    @Test func previewsComeFromTheOpenEditorOrAnEvaluation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EvalBridgeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = SheetLibrary(directory: folder.appendingPathComponent("Sheets").path)
        let closed = try #require(library.sheets().first)
        #expect(!closed.isOpen)
        let preview = await Task.detached { closed.resultPreview() }.value
        #expect(preview?.text == "E = 1000 J")
        #expect(preview?.spoken.contains("égale") == true)

        let editor = try #require(library.openEditor(id: closed.id))
        let open = try #require(library.sheet(id: closed.id))
        #expect(open.isOpen)
        #expect(open.resultPreview() == nil)
        #expect(open != closed)
        editor.applyEvaluation(SheetEditor.evaluate(editor.evaluationRequest()))
        #expect(library.sheet(id: closed.id)?.resultPreview()?.text == "E = 1000 J")
    }

    @Test func unavailableStorageKeepsSheetsInMemory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EvalBridgeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        // A file where the folder should be.
        try Data().write(to: folder)
        let library = SheetLibrary(directory: folder.appendingPathComponent("Sheets").path)
        #expect(library.storageProblem == SheetLibrary.unavailableStorageMessage)
        #expect(library.sheets().map(\.title) == ["Énergie cinétique"])

        let id = library.createSheet(source: "a = 1")
        #expect(library.contains(id: id))
        #expect(library.flush())
        library.dismissStorageProblem()
        #expect(library.storageProblem == nil)
    }
}
