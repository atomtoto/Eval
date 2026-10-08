import SwiftUI

enum EvalTab: Hashable {
    case calculation, references
}

/// What the focused window can do, for the menu bar of iPadOS and the Mac,
/// and for the shortcut overlay that ⌘ held down shows.
struct WindowActions {
    let tab: EvalTab
    let newSheet: () -> Void
    let showTab: (EvalTab) -> Void
    let showHelp: () -> Void
    /// Nil where the search field cannot be focused from the keyboard (before iOS 18).
    let search: (() -> Void)?
}

/// What the sheet shown in the focused window can do.
struct NotebookActions {
    let editorMode: NotebookEditorMode
    let canChooseResults: Bool
    let canClear: Bool
    /// Nil in a narrow window, which has no results column.
    let toggleResultsColumn: (() -> Void)?
    let newLine: () -> Void
    let chooseResults: () -> Void
    let setEditorMode: (NotebookEditorMode) -> Void
    let clear: () -> Void
}

extension FocusedValues {
    @Entry var windowActions: WindowActions?
    @Entry var notebookActions: NotebookActions?
}

/// The commands of the app. Undo and Redo (⌘Z, ⇧⌘Z) come from the system.
struct EvalCommands: Commands {
    @FocusedValue(\.windowActions) private var window
    @FocusedValue(\.notebookActions) private var notebook

    /// The sheet commands apply while the Calcul tab shows a sheet.
    private var sheet: NotebookActions? {
        window?.tab == .calculation ? notebook : nil
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Nouvelle feuille") { window?.newSheet() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(window == nil)
            Button("Nouvelle ligne") { sheet?.newLine() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(sheet == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Rechercher") { window?.search?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(window?.search == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Calcul") { window?.showTab(.calculation) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(window == nil)
            Button("Références") { window?.showTab(.references) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(window == nil)
        }

        CommandMenu("Feuille") {
            Button("Choisir les résultats…") { sheet?.chooseResults() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(sheet?.canChooseResults != true)
            Button("Afficher ou masquer la colonne Résultats") { sheet?.toggleResultsColumn?() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(sheet?.toggleResultsColumn == nil)
            Divider()
            Toggle("Mode Formules", isOn: mode(.formulas))
                .keyboardShortcut("1", modifiers: [.command, .option])
                .disabled(sheet == nil)
            Toggle("Mode Texte", isOn: mode(.text))
                .keyboardShortcut("2", modifiers: [.command, .option])
                .disabled(sheet == nil)
            Divider()
            Button("Effacer la feuille…", role: .destructive) { sheet?.clear() }
                .disabled(sheet?.canClear != true)
        }

        CommandGroup(replacing: .help) {
            Button("Aide d’Eval") { window?.showHelp() }
                .keyboardShortcut("?", modifiers: .command)
                .disabled(window == nil)
        }
    }

    private func mode(_ mode: NotebookEditorMode) -> Binding<Bool> {
        Binding(get: { sheet?.editorMode == mode }, set: { if $0 { sheet?.setEditorMode(mode) } })
    }
}
