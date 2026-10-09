import EvalCore
import SwiftUI
import UIKit

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

/// The home screen icon. The system stores the choice; nil is the primary icon.
enum AppIconChoice: String, CaseIterable, Identifiable {
    /// A tinted dot seen through a large glass lens.
    case lens
    /// A single glass point on the curve.
    case point

    var id: Self { self }

    /// The alternate icon's name in the build settings, nil for the primary icon.
    var alternateName: String? {
        switch self {
        case .lens: nil
        case .point: "AppIconPoint"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .lens: "Lentille"
        case .point: "Point"
        }
    }

    var preview: ImageResource {
        switch self {
        case .lens: .appIconPreview
        case .point: .appIconPointPreview
        }
    }

    @MainActor
    static var current: Self {
        allCases.first { $0.alternateName == UIApplication.shared.alternateIconName } ?? .lens
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
    @State private var icon = AppIconChoice.current
    @State private var iconError: String?

    /// The formatter changes before the views read the new setting, so they show it at once.
    private var digitsSelection: Binding<Int> {
        Binding {
            digits
        } set: { value in
            QuantityFormatter.significantDigits = value
            digits = QuantityFormatter.significantDigits
        }
    }

    /// The system shows its own confirmation when the icon changes.
    private var iconSelection: Binding<AppIconChoice> {
        Binding {
            icon
        } set: { choice in
            let previous = icon
            icon = choice
            iconError = nil
            Task {
                do {
                    try await UIApplication.shared.setAlternateIconName(choice.alternateName)
                } catch {
                    icon = previous
                    iconError = String(localized: "L’icône n’a pas pu être changée.")
                }
            }
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

                Section {
                    Picker("Icône de l’app", selection: iconSelection) {
                        ForEach(AppIconChoice.allCases) { choice in
                            Label {
                                Text(choice.title)
                            } icon: {
                                Image(choice.preview)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .accessibilityHidden(true)
                            }
                            .tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Icône de l’app")
                } footer: {
                    if let iconError {
                        Text(iconError).foregroundStyle(.red)
                    }
                }
                .disabled(!UIApplication.shared.supportsAlternateIcons)
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
