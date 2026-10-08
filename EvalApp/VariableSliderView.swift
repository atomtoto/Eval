import EvalCore
import SwiftUI

/// Adjusts the number in its entered unit, so 72 km/h stays in km/h.
/// In Formules mode the formula above is the label and the ruler stands alone;
/// the value is repeated in text only where the ruler sits apart, in Texte mode.
struct VariableSliderView: View {
    let variable: AdjustableVariable
    let range: VariableAdjustmentRange
    let usesAutomaticStep: Bool
    var showsLabel = true
    let onChangeValue: (Double, Bool) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }
    let onChangeRange: (VariableAdjustmentRange, Bool) -> Void
    @State private var showsRangeEditor = false

    private var valueLabel: String {
        QuantityFormatter.number(variable.value, significantDigits: QuantityFormatter.preciseDigits) + (variable.unit.isEmpty ? "" : " " + variable.unit)
    }

    /// A number with the unit named, as VoiceOver reads it: « 81 kilogrammes ».
    private func spoken(_ value: Double) -> String {
        SpokenValue.text(value, unit: variable.unit,
                         fallback: QuantityFormatter.number(value, significantDigits: QuantityFormatter.preciseDigits) + (variable.unit.isEmpty ? "" : " " + variable.unit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsLabel {
                Text("\(variable.name) = \(valueLabel)")
                    .font(.callout.monospacedDigit())
            }

            HStack {
                Spacer(minLength: 0)
                VariableRulerView(value: variable.value, range: range,
                                  label: "Valeur de \(variable.name)", valueLabel: valueLabel,
                                  spokenValue: spoken(variable.value), spokenStep: spoken(range.step),
                                  usesAutomaticStep: usesAutomaticStep,
                                  onChangeValue: onChangeValue, onEditingChanged: onEditingChanged)
                Spacer(minLength: 0)
                Button("Régler le curseur de \(variable.name)", systemImage: "slider.horizontal.3") {
                    showsRangeEditor = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }

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
                        LabeledContent("Pas", value: QuantityFormatter.number(configuredRange?.step ?? variable.automaticStep, significantDigits: QuantityFormatter.preciseDigits))
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
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        guard let range = configuredRange else { return }
                        onSave(range, usesAutomaticStep)
                        dismiss()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(configuredRange == nil)
                }
            }
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, focus: Field) -> some View {
        LabeledContent(title) {
            HStack {
                TextField(title, text: text)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: focus)
                    .submitLabel(nextField(after: focus) == nil ? .done : .next)
                    .onSubmit { focusedField = nextField(after: focus) }
                    .accessibilityLabel(title)
                if !variable.unit.isEmpty {
                    Text(variable.unit).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// The field that Return moves to; the step is skipped while it is automatic.
    private func nextField(after field: Field) -> Field? {
        switch field {
        case .minimum: .maximum
        case .maximum: usesAutomaticStep ? nil : .step
        case .step: nil
        }
    }

    private func number(_ source: String) -> Double? {
        Double(source.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "−", with: "-"))
    }

    /// A plain decimal number in the current language, without grouping or an exponent.
    private static func editableNumber(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.significantDigits(1...15)))
    }
}
