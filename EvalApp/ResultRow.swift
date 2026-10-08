import EvalCore
import SwiftUI
import UIKit

/// A line with its value, as listed in Résultats.
struct ResultRow: View {
    let result: LineResult
    /// False beside the text editor, which shows no line numbers: the formula names the line.
    var showsLineNumber = true
    @State private var copies = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsLineNumber {
                NumberedLine(number: result.index + 1) {
                    FormulaView(source: result.entry.source)
                }
            } else {
                FormulaView(source: result.entry.source)
            }
            if let line = result.line {
                ResultValueView(line: line, isCurrent: result.isCurrent)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .sensoryFeedback(.success, trigger: copies)
        .contextMenu {
            ResultCopyItems(source: result.entry.source, line: result.line, copies: $copies)
        }
        // Context menus are not reachable with Switch Control or Voice Control.
        .accessibilityActions {
            ResultCopyButtons(source: result.entry.source, line: result.line, copies: $copies)
        }
    }
}

/// The value of a line, with its message and the dimension check. While the
/// line is being edited, its previous value stays visible, dimmed.
struct ResultValueView: View {
    let line: EvaluatedLine
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let value = line.formattedValue {
                Text(value)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                    .accessibilityLabel(line.spokenResult ?? value)
            }
            if let message = line.message {
                if line.status == .error {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Erreur : \(message)")
                } else {
                    Label(message, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if let dimensionMessage = line.dimensionMessage {
                Label(dimensionMessage, systemImage: line.isHomogeneous ? "checkmark.circle" : "ruler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(line.spokenDimensionMessage ?? dimensionMessage)
            }
        }
    }
}

/// Copy and share actions for the value of a line, for a context menu.
/// Values are copied as displayed, in SI or in the unit chosen with →, and paste back as valid input.
struct ResultCopyItems: View {
    let source: String
    let line: EvaluatedLine?
    /// Incremented on every copy, to trigger haptic feedback in the caller.
    @Binding var copies: Int

    var body: some View {
        if let value = line?.formattedValue {
            ResultCopyButtons(source: source, line: line, copies: $copies)
            ShareLink(item: ResultText.line(source: source, value: value), preview: SharePreview("Résultat Eval")) {
                Label("Partager le résultat", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// « Copier la valeur » and « Copier la ligne », for menus and accessibility actions.
struct ResultCopyButtons: View {
    let source: String
    let line: EvaluatedLine?
    @Binding var copies: Int

    var body: some View {
        if let value = line?.formattedValue {
            Button("Copier la valeur", systemImage: "doc.on.doc") { copy(value) }
            Button("Copier la ligne", systemImage: "text.alignleft") {
                copy(ResultText.line(source: source, value: value))
            }
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copies += 1
    }
}
