import EvalCore
import SwiftUI

/// A native slider adjusts the number as entered, so 72 km/h stays in km/h.
struct VariableSliderView: View {
    let variable: AdjustableVariable
    let range: VariableAdjustmentRange
    let onChangeValue: (Double) -> Void
    let onChangeRange: (VariableAdjustmentRange) -> Void
    @State private var showsRangeEditor = false

    private var valueLabel: String {
        QuantityFormatter.number(variable.value) + (variable.unit.isEmpty ? "" : " " + variable.unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(variable.name) = \(valueLabel)")
                    .font(.callout.monospacedDigit())
                Spacer()
                Button("Régler le curseur de \(variable.name)", systemImage: "slider.horizontal.3") {
                    showsRangeEditor = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }

            Slider(value: Binding(
                get: { range.position(for: variable.value) },
                set: { onChangeValue(range.value(at: $0)) }
            ), in: 0...1) {
                Text("Valeur de \(variable.name)")
            } minimumValueLabel: {
                Text(QuantityFormatter.number(range.lowerBound))
                    .font(.caption.monospacedDigit())
            } maximumValueLabel: {
                Text(QuantityFormatter.number(range.upperBound))
                    .font(.caption.monospacedDigit())
            }
            .accessibilityValue(valueLabel)
            .accessibilityHint("Glissez pour modifier la variable et recalculer les résultats.")
            .accessibilityAdjustableAction { direction in
                let next: Double
                switch direction {
                case .increment: next = range.adjacentValue(to: variable.value, increasing: true)
                case .decrement: next = range.adjacentValue(to: variable.value, increasing: false)
                @unknown default: return
                }
                onChangeValue(next)
            }

            if !(range.lowerBound...range.upperBound).contains(variable.value) {
                Text("Valeur hors des bornes. Glissez pour la ramener dans l’intervalle, ou modifiez les réglages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showsRangeEditor) {
            VariableRangeEditor(variable: variable, range: range, onSave: onChangeRange)
        }
    }
}

private struct VariableRangeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minimum: String
    @State private var maximum: String
    @State private var step: String
    @FocusState private var focusedField: Field?
    let variable: AdjustableVariable
    let onSave: (VariableAdjustmentRange) -> Void

    private enum Field: Hashable { case minimum, maximum, step }

    init(variable: AdjustableVariable, range: VariableAdjustmentRange,
         onSave: @escaping (VariableAdjustmentRange) -> Void) {
        self.variable = variable
        self.onSave = onSave
        _minimum = State(initialValue: Self.editableNumber(range.lowerBound))
        _maximum = State(initialValue: Self.editableNumber(range.upperBound))
        _step = State(initialValue: Self.editableNumber(range.step))
    }

    private var configuredRange: VariableAdjustmentRange? {
        guard let lower = number(minimum), let upper = number(maximum), let increment = number(step) else { return nil }
        return VariableAdjustmentRange(lowerBound: lower, upperBound: upper, step: increment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Minimum", text: $minimum, focus: .minimum)
                    field("Maximum", text: $maximum, focus: .maximum)
                    field("Pas", text: $step, focus: .step)
                } header: {
                    Text(variable.unit.isEmpty ? "Valeurs sans unité" : "Valeurs en \(variable.unit)")
                } footer: {
                    Text("Le pas détermine la précision du glissement. La virgule, le point, les valeurs négatives et la notation scientifique sont acceptés.")
                }

                if let range = configuredRange {
                    if !(range.lowerBound...range.upperBound).contains(variable.value) {
                        Section {
                            Text("La valeur actuelle sera ramenée dans l’intervalle choisi.")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Text("Le maximum doit dépasser le minimum. Le pas doit être positif et ne pas dépasser l’intervalle ; les valeurs doivent être finies.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Rétablir le réglage automatique") {
                        guard let suggested = VariableAdjustmentRange.suggested(for: variable.value) else { return }
                        minimum = Self.editableNumber(suggested.lowerBound)
                        maximum = Self.editableNumber(suggested.upperBound)
                        step = Self.editableNumber(suggested.step)
                    }
                }
            }
            .navigationTitle("Curseur de \(variable.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        guard let range = configuredRange else { return }
                        onSave(range)
                        dismiss()
                    }
                    .disabled(configuredRange == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { focusedField = nil }
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, focus: Field) -> some View {
        LabeledContent(title) {
            TextField(title, text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: focus)
                .accessibilityLabel(title)
        }
    }

    private func number(_ source: String) -> Double? {
        Double(source.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "−", with: "-"))
    }

    private static func editableNumber(_ value: Double) -> String {
        String(value).replacingOccurrences(of: ".", with: ",")
    }
}
