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

/// The accent color of the whole app. The raw values are stored and must not change.
enum AccentSetting: String, CaseIterable, Identifiable {
    /// A safety orange, the AccentColor of the asset catalog and the default.
    case orange
    /// The system blue.
    case blue

    static let storageKey = "eval.accent.v1"

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .orange: "Orange industriel"
        case .blue: "Bleu"
        }
    }

    /// The color applied as the tint of the app.
    var color: Color {
        switch self {
        case .orange: Color(.accent)
        case .blue: .blue
        }
    }
}

extension AccentSetting {
    /// SwiftUI's tint does not reach the views the system draws itself, such as the value
    /// of a menu picker or the buttons of an alert: they follow the tint of the window.
    @MainActor
    func applyToWindows() {
        let tint = UIColor(color)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.tintColor = tint }
        }
    }
}

/// Whether sheets take a warm page in light mode. A preference shared by every window.
enum WarmBackgroundSetting {
    static let storageKey = "eval.warmBackground.v1"
}

/// The home screen icon style. The system stores the choice, as the name of an
/// alternate icon that also tells the accent color; nil is the primary icon.
enum AppIconChoice: String, CaseIterable, Identifiable {
    /// A tinted dot seen through a large glass lens.
    case lens
    /// A single glass point on the curve.
    case point

    var id: Self { self }

    /// The alternate icon's name in the build settings, nil for the primary icon.
    /// The icon follows the accent color: orange is the primary style.
    func alternateName(for accent: AccentSetting) -> String? {
        switch (self, accent) {
        case (.lens, .orange): nil
        case (.point, .orange): "AppIconPoint"
        case (.lens, .blue): "AppIconBlue"
        case (.point, .blue): "AppIconPointBlue"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .lens: "Lentille"
        case .point: "Point"
        }
    }

    func preview(for accent: AccentSetting) -> ImageResource {
        switch (self, accent) {
        case (.lens, .orange): .appIconPreview
        case (.point, .orange): .appIconPointPreview
        case (.lens, .blue): .appIconBluePreview
        case (.point, .blue): .appIconPointBluePreview
        }
    }

    /// The style of the icon in use, from its name.
    @MainActor
    static var current: Self {
        switch UIApplication.shared.alternateIconName {
        case "AppIconPoint", "AppIconPointBlue": .point
        default: .lens
        }
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
    @AppStorage(AccentSetting.storageKey) private var accent = AccentSetting.orange
    @AppStorage(WarmBackgroundSetting.storageKey) private var warmBackground = true
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
            updateIcon(restoring: previous)
        }
    }

    /// Gives the app the icon of the chosen style in the accent color, unless it already has it.
    /// A refused change puts the style back when `previous` is given.
    private func updateIcon(restoring previous: AppIconChoice? = nil) {
        let name = icon.alternateName(for: accent)
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != name else { return }
        iconError = nil
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(name)
            } catch {
                if let previous { icon = previous }
                iconError = String(localized: "L’icône n’a pas pu être changée.")
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
                    Picker("Couleur d’accent", selection: $accent) {
                        ForEach(AccentSetting.allCases) { setting in
                            Label {
                                Text(setting.title)
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(setting.color)
                            }
                            .tag(setting)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Couleur d’accent")
                } footer: {
                    Text("L’icône de l’app suit la couleur d’accent.")
                }

                Section {
                    Toggle("Fond chaud", isOn: $warmBackground)
                } footer: {
                    Text("En mode clair, les feuilles prennent un fond crème chaud. Le mode sombre ne change pas.")
                }

                Section {
                    Picker("Icône de l’app", selection: iconSelection) {
                        ForEach(AppIconChoice.allCases) { choice in
                            Label {
                                Text(choice.title)
                            } icon: {
                                Image(choice.preview(for: accent))
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
            .warmPage()
            .onChange(of: accent) { updateIcon() }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .tint(.primary)
                }
            }
        }
    }
}
