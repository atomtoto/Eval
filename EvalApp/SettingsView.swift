import EvalCore
import SwiftUI

/// How a line is edited when it is touched. A preference shared by every sheet
/// and window; the raw values are stored and must not change.
enum FormulaInputMode: String, CaseIterable, Identifiable {
    /// The line becomes a text field in place.
    case text
    /// Fractions and exponents are typed in their rendered form.
    case math

    static let storageKey = "eval.formulaInput.v1"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .text: "Dans la ligne (texte)"
        case .math: "Écriture mathématique"
        }
    }
}

/// The number of significant digits of the values shown, 3 to 12.
enum SignificantDigitsSetting {
    static let storageKey = "eval.significantDigits.v1"

    /// The stored setting, or the default before any choice.
    static var stored: Int {
        let value = UserDefaults.standard.object(forKey: storageKey) as? Int ?? QuantityFormatter.defaultDigits
        return min(QuantityFormatter.maximumDigits, max(QuantityFormatter.minimumDigits, value))
    }

    /// Hands the stored setting to the formatter; call it at launch.
    @MainActor
    static func apply() {
        QuantityFormatter.significantDigits = stored
    }
}

extension EnvironmentValues {
    /// Views that format values read it, so that they format them again when it changes.
    @Entry var significantDigits = QuantityFormatter.defaultDigits
}

/// The settings of the app, as a native form.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FormulaInputMode.storageKey) private var inputMode = FormulaInputMode.text
    @AppStorage(SignificantDigitsSetting.storageKey) private var digits = QuantityFormatter.defaultDigits

    /// The formatter changes before the views read the new setting, so they show it at once.
    private var digitsSelection: Binding<Int> {
        Binding {
            digits
        } set: { value in
            QuantityFormatter.significantDigits = value
            digits = QuantityFormatter.significantDigits
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Saisie des formules", selection: $inputMode) {
                        ForEach(FormulaInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } footer: {
                    Text("Touchez une ligne pour la modifier là où elle se trouve. Dans la ligne (texte), la formule s’écrit comme E = m * c^2 et s’affiche en notation mathématique dès que vous la quittez. En écriture mathématique, elle se modifie telle qu’elle s’affiche : / crée une fraction, ^ un exposant, et toucher la formule place le curseur.")
                }

                Section {
                    Stepper(value: digitsSelection,
                            in: QuantityFormatter.minimumDigits...QuantityFormatter.maximumDigits) {
                        LabeledContent("Chiffres significatifs", value: digits.formatted())
                    }
                } footer: {
                    Text("Nombre de chiffres significatifs des résultats affichés. Les calculs gardent toujours toute leur précision.")
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
