import EvalCore
import SwiftUI

/// Adjusts the number in its entered unit, so 72 km/h stays in km/h.
struct VariableSliderView: View {
    let variable: AdjustableVariable
    let range: VariableAdjustmentRange
    let usesAutomaticStep: Bool
    let onChangeValue: (Double) -> Void
    let onChangeRange: (VariableAdjustmentRange, Bool) -> Void
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

            HStack {
                Spacer(minLength: 0)
                VariableRulerView(value: variable.value, range: range,
                                  label: "Valeur de \(variable.name)", valueLabel: valueLabel,
                                  onChangeValue: onChangeValue)
                Spacer(minLength: 0)
            }
            Text("Pas : \(QuantityFormatter.number(range.step))\(usesAutomaticStep ? " · automatique" : "")")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !(range.lowerBound...range.upperBound).contains(variable.value) {
                Text("Valeur hors des bornes. Glissez pour la ramener dans l’intervalle, ou modifiez les réglages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showsRangeEditor) {
            VariableRangeEditor(variable: variable, range: range, usesAutomaticStep: usesAutomaticStep, onSave: onChangeRange)
        }
    }
}

private struct VariableRangeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minimum: String
    @State private var maximum: String
    @State private var step: String
    @State private var usesAutomaticStep: Bool
    @FocusState private var focusedField: Field?
    let variable: AdjustableVariable
    let onSave: (VariableAdjustmentRange, Bool) -> Void

    private enum Field: Hashable { case minimum, maximum, step }

    init(variable: AdjustableVariable, range: VariableAdjustmentRange, usesAutomaticStep: Bool,
         onSave: @escaping (VariableAdjustmentRange, Bool) -> Void) {
        self.variable = variable
        self.onSave = onSave
        _minimum = State(initialValue: Self.editableNumber(range.lowerBound))
        _maximum = State(initialValue: Self.editableNumber(range.upperBound))
        _step = State(initialValue: Self.editableNumber(range.step))
        _usesAutomaticStep = State(initialValue: usesAutomaticStep)
    }

    private var configuredRange: VariableAdjustmentRange? {
        guard let lower = number(minimum), let upper = number(maximum),
              let increment = usesAutomaticStep ? Optional(min(upper - lower, variable.automaticStep)) : number(step) else { return nil }
        return VariableAdjustmentRange(lowerBound: lower, upperBound: upper, step: increment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Minimum", text: $minimum, focus: .minimum)
                    field("Maximum", text: $maximum, focus: .maximum)
                    Toggle("Pas automatique", isOn: $usesAutomaticStep)
                    if usesAutomaticStep {
                        LabeledContent("Pas", value: QuantityFormatter.number(configuredRange?.step ?? variable.automaticStep))
                    } else {
                        field("Pas", text: $step, focus: .step)
                    }
                } header: {
                    Text(variable.unit.isEmpty ? "Valeurs sans unité" : "Valeurs en \(variable.unit)")
                } footer: {
                    Text("Le pas automatique suit la précision saisie : 6 avance de 1, 8,2 de 0,1 et 8,25 de 0,01. Désactivez-le pour choisir un autre pas.")
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
                        guard let suggested = VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep) else { return }
                        minimum = Self.editableNumber(suggested.lowerBound)
                        maximum = Self.editableNumber(suggested.upperBound)
                        step = Self.editableNumber(suggested.step)
                        usesAutomaticStep = true
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
                        onSave(range, usesAutomaticStep)
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
