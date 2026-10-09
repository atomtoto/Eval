import EvalCore
import SwiftUI
import UIKit

/// A line of the sheet. At rest it shows the formula, followed by its value when
/// the line asks for it (`E =`); a tap edits it in place. A long press on the
/// value of a declared number opens its ruler in a popover anchored to the value.
struct FormulaRowView: View {
    let notebook: NotebookStore
    let item: IndexedFormulaLine
    /// True while this line is edited in place.
    let isEditing: Bool
    let inputMode: FormulaInputMode
    let focus: FocusState<UUID?>.Binding
    let selection: FormulaSelectionState
    let keyboard: LineKeyboard
    /// Starts editing a line: this one, or its copy.
    let edit: (UUID) -> Void
    /// Receives the text of the line when it contains line breaks: a Return or a paste.
    let breakLine: (String) -> Void
    let plot: (PlotRequest) -> Void
    @Environment(\.editMode) private var editMode
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(LineNumbersSetting.storageKey) private var showsLineNumbers = false
    /// Read so that values are formatted again when the setting changes.
    @Environment(\.significantDigits) private var significantDigits
    @State private var copies = 0

    private var id: UUID { item.entry.id }
    private var source: String { item.entry.source }

    /// At accessibility sizes the line number sits above the formula, so the
    /// rows below it no longer line up with a number column.
    private var stacksNumber: Bool { dynamicTypeSize.isAccessibilitySize }

    private var trimmedSource: String {
        source.trimmingCharacters(in: .whitespaces)
    }

    private var isComment: Bool {
        trimmedSource.hasPrefix("#") || trimmedSource.hasPrefix("//")
    }

    private var isReordering: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
        // The last result of this line, even while its new text is evaluated.
        let line = notebook.result(for: id)
        let variable = notebook.variablesByLineID[id]
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                editingContent(line: line)
            } else if isReordering {
                content(line: line, variable: variable)
            } else {
                content(line: line, variable: variable)
                    .environment(\.formulaValueInteraction, variable.map { _ in
                        FormulaValueInteraction(isPresented: rulerBinding,
                                                longPress: showRuler,
                                                popover: AnyView(NotebookVariableControl(notebook: notebook, id: id,
                                                                                         undoManager: undoManager)))
                    })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { edit(id) }
                    .contextMenu { menu(line: line, variable: variable) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(line: line, variable: variable))
                    .accessibilityValue(variable.map(spokenValue) ?? "")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Modifie la ligne.")
                    .accessibilityAction { edit(id) }
                    .accessibilityActions { accessibilityActions(line: line, variable: variable) }
                    .modifier(AdjustableValue(variable: variable) { increasing in
                        if let variable { adjust(variable, increasing: increasing) }
                    })
            }
        }
        .padding(.vertical, 4)
        // The separator starts with the line, not with the text of a note under it.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .sensoryFeedback(.success, trigger: copies)
        // A row keeps horizontal drags for the text it edits.
        .deleteDisabled(isEditing)
    }

    // MARK: Content

    @ViewBuilder
    private func content(line: EvaluatedLine?, variable: AdjustableVariable?) -> some View {
        if isComment {
            numbered(notes: []) {
                note
            }
        } else {
            numbered(notes: notes(for: line)) {
                FormulaView(source: source) {
                    inlineResult(line: line)
                }
            }
        }
    }

    /// The line edited in place, with its value kept up to date under the field.
    /// Errors wait for the end of the editing: the line is often incomplete while typed.
    private func editingContent(line: EvaluatedLine?) -> some View {
        var notes: [LineNote] = []
        if let line, LineSyntax(source).requestsValue, line.kind != .equation, let value = line.formattedValue {
            notes.append(LineNote(text: "= \(value)", style: line.source == source ? .value : .staleValue,
                                  spoken: String(localized: "Résultat : \(line.spokenResult ?? value)")))
        } else if let line, line.kind == .equation, line.source == source, line.status == .success {
            notes += self.notes(for: line).prefix(1)
        }
        return numbered(notes: notes) {
            LineEditorSlot(mode: inputMode, lineID: id, text: text, selection: selection, focus: focus,
                           keyboard: keyboard)
        }
    }

    /// The text of the line; line breaks go to the sheet, which turns them into lines.
    private var text: Binding<String> {
        Binding {
            notebook.lineSource(of: id) ?? ""
        } set: { newValue in
            if newValue.contains(where: \.isNewline) {
                breakLine(newValue)
            } else {
                notebook.updateLine(newValue, lineID: id)
            }
        }
    }

    /// The line and its notes under it in the line’s column, with the line’s number beside it when shown.
    @ViewBuilder
    private func numbered<Line: View>(notes: [LineNote], @ViewBuilder _ line: () -> Line) -> some View {
        let column = VStack(alignment: .leading, spacing: 8) {
            line()
                .frame(maxWidth: .infinity, alignment: .leading)
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(notes) { $0 }
                }
            }
        }
        if !showsLineNumbers {
            column
        } else if stacksNumber {
            VStack(alignment: .leading, spacing: 4) {
                LineNumberLabel(number: item.index + 1)
                column
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LineNumberLabel(number: item.index + 1)
                column
            }
        }
    }

    /// The value a line asks for with `=`, `→` or `?`, on the line of the formula.
    /// A tap opens the line’s menu. A value computed for an earlier text is dimmed.
    @ViewBuilder
    private func inlineResult(line: EvaluatedLine?) -> some View {
        let syntax = LineSyntax(source)
        if syntax.requestsValue, let line, line.kind != .equation, let value = line.formattedValue {
            Menu {
                menu(line: line, variable: notebook.variablesByLineID[id])
            } label: {
                Text(verbatim: syntax.requestsResult ? value : "= \(value)")
                    .foregroundStyle(line.source == source ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
        }
    }

    /// What the engine has to say about the line: an error, the verdict of an
    /// equality, a remark such as the radian note, or a dimension it checked.
    private func notes(for line: EvaluatedLine?) -> [LineNote] {
        guard let line else { return [] }
        let isCurrent = line.source == source
        var notes: [LineNote] = []
        if let message = line.message {
            if line.status == .error {
                let icon = line.kind == .equation && line.quantity != nil ? "xmark.circle" : "exclamationmark.triangle"
                notes.append(LineNote(text: message, systemImage: icon, style: .error,
                                      spoken: String(localized: "Erreur : \(message)")))
            } else if line.status == .success, isCurrent {
                notes.append(line.kind == .equation
                    ? LineNote(text: message, systemImage: "checkmark.circle", style: .verified)
                    : LineNote(text: message, systemImage: "info.circle", style: .info))
            }
        }
        if isCurrent, line.isHomogeneous, line.kind == .equation || LineSyntax(source).requestsValue,
           let dimension = line.dimensionMessage {
            notes.append(LineNote(text: dimension, systemImage: "checkmark.circle", style: .caption,
                                  spoken: line.spokenDimensionMessage))
        }
        return notes
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

    // MARK: Ruler

    /// Whether the popover of the ruler is shown; it closes with a tap outside.
    private var rulerBinding: Binding<Bool> {
        Binding {
            notebook.activeRulerLineID == id && !isReordering && !isEditing
        } set: { isPresented in
            if isPresented {
                notebook.showRuler(lineID: id)
            } else if notebook.activeRulerLineID == id {
                notebook.activeRulerLineID = nil
            }
        }
    }

    private func showRuler() {
        notebook.showRuler(lineID: id)
    }

    /// One step of the ruler, for VoiceOver’s adjustable action: one undo step.
    private func adjust(_ variable: AdjustableVariable, increasing: Bool) {
        let step = notebook.rulerStep(for: id, variable: variable)
        notebook.rulerEditingChanged(true, name: variable.name, undoManager: undoManager)
        notebook.adjustVariable(VariableAdjustmentRange.stepped(from: variable.value, steps: increasing ? 1 : -1, step: step),
                                lineID: id, announcesResults: true)
        notebook.rulerEditingChanged(false, name: variable.name, undoManager: undoManager)
    }

    private func spokenValue(_ variable: AdjustableVariable) -> String {
        SpokenValue.text(variable.value, unit: variable.unit,
                         fallback: QuantityFormatter.number(variable.value, significantDigits: QuantityFormatter.preciseDigits)
                            + (variable.unit.isEmpty ? "" : " " + variable.unit))
    }

    // MARK: Accessibility

    /// The formula and its value as one phrase; a declared number is read as its value.
    private func accessibilityLabel(line: EvaluatedLine?, variable: AdjustableVariable?) -> String {
        if isComment { return String(localized: "Ligne \(item.index + 1), note : \(trimmedSource)") }
        var parts: [String] = []
        if let variable {
            parts.append(String(localized: "Valeur de \(variable.name)"))
        } else {
            parts.append(MathSpeech.description(source) ?? source)
            let syntax = LineSyntax(source)
            if syntax.requestsValue, let line, line.kind != .equation, line.source == source,
               let spoken = line.spokenResult {
                parts[0] += syntax.requestsResult ? " \(spoken)" : String(localized: " égale \(spoken)")
            }
        }
        if let line, let message = line.message, line.status == .error || line.source == source {
            parts.append(line.status == .error ? String(localized: "Erreur : \(message)") : message)
        }
        return parts.joined(separator: ". ")
    }

    // MARK: Menu

    @ViewBuilder
    private func menu(line: EvaluatedLine?, variable: AdjustableVariable?) -> some View {
        if !isComment {
            if line?.source == source, LineSyntax(source).requestsValue || line?.kind == .equation {
                ResultCopyItems(source: source, line: line, copies: $copies)
            }
            DisplayUnitMenu(line: line, source: source) { symbol in
                notebook.setDisplayUnit(symbol, lineID: id, undoManager: undoManager)
            }
            PlotMenu(notebook: notebook, lineID: id, source: source, plot: plot)
            if variable != nil {
                Button("Afficher la réglette", systemImage: "ruler", action: showRuler)
            }
        }
        Button("Copier la formule", systemImage: "doc.on.doc", action: copyFormula)
        Button("Modifier", systemImage: "pencil") { edit(id) }
        Button("Dupliquer", systemImage: "plus.square.on.square", action: duplicate)
        Button("Supprimer", systemImage: "trash", role: .destructive, action: remove)
    }

    /// The menu’s actions for VoiceOver, Switch Control and Voice Control, which
    /// cannot press and hold.
    @ViewBuilder
    private func accessibilityActions(line: EvaluatedLine?, variable: AdjustableVariable?) -> some View {
        if !isComment {
            if variable != nil {
                Button("Afficher la réglette", action: showRuler)
            }
            if line?.source == source, LineSyntax(source).requestsValue {
                ResultCopyButtons(source: source, line: line, copies: $copies)
            }
            DisplayUnitActions(line: line, source: source) { symbol in
                notebook.setDisplayUnit(symbol, lineID: id, undoManager: undoManager)
            }
        }
        Button("Copier la formule", action: copyFormula)
        Button("Dupliquer", action: duplicate)
        Button("Supprimer", role: .destructive, action: remove)
    }

    private func copyFormula() {
        UIPasteboard.general.string = trimmedSource
        copies += 1
    }

    /// The copy opens for editing: a declaration’s copy needs another name.
    private func duplicate() {
        if let copy = notebook.duplicateLine(id: id, undoManager: undoManager) { edit(copy) }
    }

    private func remove() {
        notebook.removeLine(id: id, undoManager: undoManager)
    }
}

/// A line of text under a formula: its value while it is edited, an error, a
/// verdict or a remark.
private struct LineNote: View, Identifiable {
    enum Style {
        case value, staleValue, error, verified, info, caption
    }

    let text: String
    var systemImage: String?
    let style: Style
    var spoken: String?

    nonisolated var id: String { text }

    var body: some View {
        Group {
            if let systemImage {
                Label {
                    Text(text)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(style == .verified ? AnyShapeStyle(.green) : AnyShapeStyle(foreground))
                }
            } else {
                Text(text)
            }
        }
        .font(font)
        .foregroundStyle(foreground)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? text)
    }

    private var font: Font {
        switch style {
        case .value, .staleValue: .body.monospacedDigit().weight(.semibold)
        case .error, .verified, .info: .callout
        case .caption: .caption
        }
    }

    private var foreground: AnyShapeStyle {
        switch style {
        case .value: AnyShapeStyle(.tint)
        case .error: AnyShapeStyle(.red)
        case .staleValue, .verified, .info, .caption: AnyShapeStyle(.secondary)
        }
    }
}

/// Makes a declared number adjustable with VoiceOver’s swipe up and down.
private struct AdjustableValue: ViewModifier {
    let variable: AdjustableVariable?
    let adjust: (Bool) -> Void

    func body(content: Content) -> some View {
        if variable != nil {
            content.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(true)
                case .decrement: adjust(false)
                @unknown default: break
                }
            }
        } else {
            content
        }
    }
}

/// Where a line is edited in place, according to the setting « Saisie des formules ».
struct LineEditorSlot: View {
    let mode: FormulaInputMode
    let lineID: UUID
    @Binding var text: String
    let selection: FormulaSelectionState
    let focus: FocusState<UUID?>.Binding
    let keyboard: LineKeyboard

    var body: some View {
        switch mode {
        case .text:
            LineTextField(lineID: lineID, text: $text, selection: selection, focus: focus, keyboard: keyboard)
        case .math:
            // Writes the line on every change; a Return writes a line break, which the
            // sheet turns into a new line, exactly as from the text field.
            MathEditorView(source: $text, lineID: lineID, focus: focus, keyboard: keyboard)
        }
    }
}

/// The ruler of a declared number, as the popover of its value. It reads the line
/// from the store, so that its value and label follow the drag.
struct NotebookVariableControl: View {
    let notebook: NotebookStore
    let id: UUID
    /// Nil where the sheet’s changes are not undoable.
    var undoManager: UndoManager?

    var body: some View {
        if let variable = notebook.variablesByLineID[id],
           let range = notebook.adjustmentRange(for: id, variable: variable)
            ?? VariableAdjustmentRange.suggested(for: variable.value) {
            VariableSliderView(variable: variable, range: range,
                               step: notebook.rulerStep(for: id, variable: variable),
                               usesAutomaticStep: !notebook.manualStepIDs.contains(id),
                               onChangeValue: { value, announcesResults in
                                   notebook.adjustVariable(value, lineID: id, announcesResults: announcesResults)
                               }, onEditingChanged: { isEditing in
                                   notebook.rulerEditingChanged(isEditing, name: variable.name, undoManager: undoManager)
                               }, onChangeRange: { configured, automatic in
                                   notebook.recording(String(localized: "Régler le curseur de \(variable.name)"),
                                                      undoManager: undoManager) {
                                       notebook.setAdjustmentRange(configured, for: id, automaticStep: automatic)
                                   }
                               })
        }
    }
}
