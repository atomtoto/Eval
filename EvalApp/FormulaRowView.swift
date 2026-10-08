import EvalCore
import SwiftUI
import UIKit

/// A line of the sheet in Formules mode: the formula, its value when it is
/// chosen, and its ruler when it declares a number.
struct FormulaRowView: View {
    let notebook: NotebookStore
    let item: IndexedFormulaLine
    /// Whether a chosen value appears under the formula, rather than in a results column.
    let showsInlineResult: Bool
    let edit: (FormulaDraft) -> Void
    let plot: (PlotRequest) -> Void
    @Environment(\.editMode) private var editMode
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var copies = 0

    /// At accessibility sizes the line number sits above the formula, so the
    /// rows below it no longer line up with a number column.
    private var stacksNumber: Bool { dynamicTypeSize.isAccessibilitySize }

    private var draft: FormulaDraft {
        FormulaDraft(lineID: item.entry.id, source: item.entry.source, showsResult: item.entry.isSelected)
    }

    private var trimmedSource: String {
        item.entry.source.trimmingCharacters(in: .whitespaces)
    }

    private var isComment: Bool {
        trimmedSource.hasPrefix("#") || trimmedSource.hasPrefix("//")
    }

    var body: some View {
        // The last result of this line, even while its new text is evaluated.
        let line = notebook.result(for: item.entry.id)
        let variable = notebook.variablesByLineID[item.entry.id]
        let isEditing = editMode?.wrappedValue.isEditing == true
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                content(line: line, variable: variable)
            } else {
                Button {
                    edit(draft)
                } label: {
                    content(line: line, variable: variable)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Modifier la formule et choisir si son résultat doit être affiché.")
                .accessibilityActions { accessibilityActions(line: line, variable: variable) }
                if let variable {
                    NotebookVariableControl(notebook: notebook, id: item.entry.id, variable: variable,
                                            showsLabel: false, undoManager: undoManager)
                }
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.success, trigger: copies)
        .contextMenu { menu(line: line, variable: variable) }
        // A ruler row keeps horizontal drags for its ruler: it is deleted from its
        // context menu, or in edit mode.
        .deleteDisabled(variable != nil && !isEditing)
        .swipeActions {
            if variable == nil {
                Button("Supprimer", systemImage: "trash", role: .destructive) {
                    notebook.removeLine(id: item.entry.id, undoManager: undoManager)
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(line: EvaluatedLine?, variable: AdjustableVariable?) -> some View {
        if isComment {
            NumberedLine(number: item.index + 1, alignment: .firstTextBaseline) {
                note
            }
        } else if stacksNumber {
            VStack(alignment: .leading, spacing: 8) {
                LineNumberLabel(number: item.index + 1)
                FormulaView(source: item.entry.source)
                rows(line: line, variable: variable)
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    LineNumberLabel(number: item.index + 1)
                    FormulaView(source: item.entry.source)
                }
                rows(line: line, variable: variable)
            }
        }
    }

    /// A row under the formula, in the formula’s column.
    @ViewBuilder
    private func underFormula<Row: View>(@ViewBuilder _ row: () -> Row) -> some View {
        if stacksNumber {
            row()
        } else {
            GridRow {
                Color.clear.frame(width: 0, height: 0)
                row()
            }
        }
    }

    /// A declared number shows its value on its ruler, unless a conversion shows it in another unit.
    private func rulerShowsValue(_ variable: AdjustableVariable?) -> Bool {
        variable != nil && !LineSyntax(item.entry.source).requestsValue
    }

    /// Under the formula: the chosen value, or else only what the engine has to say
    /// about the line. A solved unknown follows the same rule as any other line.
    @ViewBuilder
    private func rows(line: EvaluatedLine?, variable: AdjustableVariable?) -> some View {
        if item.entry.isSelected {
            if !showsInlineResult {
                underFormula {
                    Label("Résultat affiché", systemImage: "pin.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if !rulerShowsValue(variable), let line {
                underFormula {
                    ResultValueView(line: line, isCurrent: line.source == item.entry.source)
                }
            } else if let line {
                lineMessage(line)
            }
        } else if let line {
            lineMessage(line)
        }
    }

    /// The message of a line whose value is not shown here: a problem, or a remark
    /// such as the radian note on a successful line.
    @ViewBuilder
    private func lineMessage(_ line: EvaluatedLine) -> some View {
        if let message = line.message {
            if line.status == .error {
                underFormula {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red)
                        .accessibilityLabel("Erreur : \(message)")
                }
            } else if line.status == .success, line.source == item.entry.source {
                underFormula {
                    Label(message, systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// A note reads as a heading when it is short, else as secondary text. The marker stays in the source.
    private var note: some View {
        let text = trimmedSource.drop { $0 == "#" || $0 == "/" }.trimmingCharacters(in: .whitespaces)
        let isHeading = trimmedSource.hasPrefix("#") && text.count < 60
        return Text(text.isEmpty ? trimmedSource : text)
            .font(isHeading ? .headline : .callout)
            .foregroundStyle(isHeading ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(isHeading ? .isHeader : [])
    }

    // MARK: Menu

    @ViewBuilder
    private func menu(line: EvaluatedLine?, variable: AdjustableVariable?) -> some View {
        if !isComment {
            if !rulerShowsValue(variable) || !showsInlineResult {
                Button(item.entry.isSelected ? "Masquer le résultat" : "Afficher le résultat",
                       systemImage: item.entry.isSelected ? "eye.slash" : "eye") {
                    notebook.setResultDisplayed(!item.entry.isSelected, lineID: item.entry.id, undoManager: undoManager)
                }
            }
            if line?.source == item.entry.source {
                ResultCopyItems(source: item.entry.source, line: line, copies: $copies)
            }
            DisplayUnitMenu(line: line, source: item.entry.source) { symbol in
                notebook.setDisplayUnit(symbol, lineID: item.entry.id, undoManager: undoManager)
            }
            PlotMenu(notebook: notebook, lineID: item.entry.id, source: item.entry.source, plot: plot)
        }
        Button("Copier la formule", systemImage: "doc.on.doc", action: copyFormula)
        Button("Modifier", systemImage: "pencil") { edit(draft) }
        Button("Dupliquer", systemImage: "plus.square.on.square", action: duplicate)
        Button("Supprimer", systemImage: "trash", role: .destructive, action: remove)
    }

    /// The menu’s actions for VoiceOver, Switch Control and Voice Control, which
    /// cannot press and hold. Row swipe actions already offer « Supprimer » on
    /// formulas, but a declaration keeps its horizontal drags for its ruler.
    @ViewBuilder
    private func accessibilityActions(line: EvaluatedLine?, variable: AdjustableVariable?) -> some View {
        if !isComment {
            if !rulerShowsValue(variable) || !showsInlineResult {
                Button(item.entry.isSelected ? "Masquer le résultat" : "Afficher le résultat") {
                    notebook.setResultDisplayed(!item.entry.isSelected, lineID: item.entry.id, undoManager: undoManager)
                }
            }
            if line?.source == item.entry.source {
                ResultCopyButtons(source: item.entry.source, line: line, copies: $copies)
            }
            DisplayUnitActions(line: line, source: item.entry.source) { symbol in
                notebook.setDisplayUnit(symbol, lineID: item.entry.id, undoManager: undoManager)
            }
        }
        Button("Copier la formule", action: copyFormula)
        Button("Dupliquer", action: duplicate)
        if variable != nil {
            Button("Supprimer", role: .destructive, action: remove)
        }
    }

    private func copyFormula() {
        UIPasteboard.general.string = trimmedSource
        copies += 1
    }

    private func duplicate() {
        if notebook.isDeclaration(lineID: item.entry.id) {
            // A name can be declared once: the copy opens in the editor to be renamed.
            edit(FormulaDraft(source: item.entry.source, showsResult: item.entry.isSelected))
        } else {
            notebook.duplicateLine(id: item.entry.id, undoManager: undoManager)
        }
    }

    private func remove() {
        notebook.removeLine(id: item.entry.id, undoManager: undoManager)
    }
}

/// The ruler of a declared number, with the range saved for its line.
struct NotebookVariableControl: View {
    let notebook: NotebookStore
    let id: UUID
    let variable: AdjustableVariable
    var showsLabel = true
    /// Nil where the sheet’s changes are not undoable, such as the text editor.
    var undoManager: UndoManager?

    var body: some View {
        if let range = notebook.adjustmentRange(for: id, variable: variable) {
            VariableSliderView(variable: variable, range: range,
                               usesAutomaticStep: !notebook.manualStepIDs.contains(id), showsLabel: showsLabel) { value, announcesResults in
                notebook.adjustVariable(value, lineID: id, range: range, announcesResults: announcesResults)
            } onEditingChanged: { isEditing in
                notebook.rulerEditingChanged(isEditing, name: variable.name, undoManager: undoManager)
            } onChangeRange: { configured, automatic in
                notebook.recording(String(localized: "Régler le curseur de \(variable.name)"), undoManager: undoManager) {
                    notebook.setAdjustmentRange(configured, for: id, automaticStep: automatic)
                    let bounded = min(configured.upperBound, max(configured.lowerBound, variable.value))
                    notebook.adjustVariable(bounded, lineID: id, range: configured)
                }
            }
        }
    }
}

struct FormulaDraft: Identifiable {
    let id = UUID()
    /// The line being edited; nil for a new line.
    var lineID: UUID?
    var source = ""
    var showsResult = false
}
