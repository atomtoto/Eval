import EvalCore
import SwiftUI

@main
struct EvalApp: App {
    @State private var library = SheetLibrary()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SignificantDigitsSetting.apply()
    }

    var body: some Scene {
        WindowGroup {
            EvalRootView()
                .environment(library)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                library.flush(waitUntilWritten: phase == .background)
            }
        }
        .commands { EvalCommands() }
    }
}

/// One window: its tab and the sheet it shows are restored per window.
/// It observes only the library's membership, never the open sheet, so
/// edits do not refresh the tab view or the Références tab.
private struct EvalRootView: View {
    @Environment(SheetLibrary.self) private var library
    @Environment(\.undoManager) private var undoManager
    @SceneStorage("eval.selectedSheetID") private var storedSheetID = ""
    /// Read here so that every value is formatted again when the setting changes.
    @AppStorage(SignificantDigitsSetting.storageKey) private var significantDigits = QuantityFormatter.defaultDigits
    @State private var tab = EvalTab.calculation
    @State private var showsHelp = false
    @State private var showsSettings = false
    /// Each increment asks a search field to take focus: ⌘F.
    @State private var referenceSearchRequest = 0
    @State private var sheetSearchRequest = 0
    @State private var column = NavigationSplitViewColumn.detail
    /// Nil until the window first changes its selection; until then the
    /// window shows its last sheet, else the most recent one.
    @State private var chosenSheet: UUID??
    @State private var chosenColumnVisibility: NavigationSplitViewVisibility?

    var body: some View {
        TabView(selection: $tab) {
            SheetSplitView(selection: selection, columnVisibility: columnVisibility, column: $column,
                           searchRequest: sheetSearchRequest)
                .tabItem { Label("Calcul", systemImage: "function") }
                .tag(EvalTab.calculation)

            ReferenceView(searchRequest: referenceSearchRequest) { symbol, name in
                insert(symbol, named: name)
            }
            .tabItem { Label("Références", systemImage: "books.vertical") }
            .tag(EvalTab.references)
        }
        .environment(\.significantDigits, significantDigits)
        .sheet(isPresented: $showsHelp) { HelpView() }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .alert("Enregistrement impossible", isPresented: storageAlertPresented) {
            Button("OK") {}
        } message: {
            Text(library.storageProblem ?? "")
        }
        .focusedSceneValue(\.windowActions, windowActions)
    }

    private var storageAlertPresented: Binding<Bool> {
        Binding(get: { library.storageProblem != nil }, set: { if !$0 { library.dismissStorageProblem() } })
    }

    private var windowActions: WindowActions {
        WindowActions(tab: tab, newSheet: newSheet, showTab: { tab = $0 }, showHelp: { showsHelp = true },
                      showSettings: { showsSettings = true }, search: searchAction)
    }

    private func newSheet() {
        selection.wrappedValue = library.createSheet()
        column = .detail
        tab = .calculation
    }

    /// ⌘F searches the catalogs, or else the list of sheets, which it shows first.
    private var searchAction: (() -> Void)? {
        guard #available(iOS 18, *) else { return nil }
        return {
            if tab == .references {
                referenceSearchRequest += 1
            } else {
                column = .sidebar
                chosenColumnVisibility = .all
                // The list takes a moment to appear.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    sheetSearchRequest += 1
                }
            }
        }
    }

    /// Returning to the list on iPhone clears the selection but keeps the
    /// stored sheet, which reopens at the next launch.
    private var selection: Binding<UUID?> {
        Binding {
            if let chosenSheet { return chosenSheet }
            return lastSheetID ?? library.mostRecentSheetID
        } set: { id in
            chosenSheet = .some(id)
            if let id { storedSheetID = id.uuidString }
        }
    }

    /// A window that opens on a sheet gives it the width, with its results
    /// beside it; the sheet list stays one tap away in the toolbar.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding {
            chosenColumnVisibility ?? (selection.wrappedValue == nil ? .automatic : .detailOnly)
        } set: { visibility in
            chosenColumnVisibility = visibility
        }
    }

    private var lastSheetID: UUID? {
        UUID(uuidString: storedSheetID).flatMap { library.contains($0) ? $0 : nil }
    }

    /// Inserts into the sheet of this window, creating one when there is none.
    /// Focus moves to the Calcul tab, so the line added is announced there.
    private func insert(_ symbol: String, named name: String) {
        let target = selection.wrappedValue.flatMap { library.contains($0) ? $0 : nil }
            ?? lastSheetID
            ?? library.createSheet()
        let session = library.session(for: target)
        // An undoable step, so that earlier steps of the window stay valid after it.
        var lineID: UUID?
        session?.recording("Ajouter une formule", undoManager: undoManager) {
            lineID = session?.append(symbol)
        }
        selection.wrappedValue = target
        column = .detail
        tab = .calculation
        if let lineID, let number = session?.lineIndex(of: lineID).map({ $0 + 1 }) {
            VoiceOverAnnouncement.post(String(localized: "Ajouté à la feuille, ligne \(number) : \(name)"),
                                       after: .milliseconds(600))
        }
    }
}
