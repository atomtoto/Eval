import EvalCore
import Foundation

/// The catalogs of the Références tab: constants by domain, and units. Searches
/// match as on iOS, ignoring case and accents. Any thread.
public final class ReferenceCatalog {
    private init() {}

    /// The domains of the « Domaine » filter, in order.
    public static func categories() -> [ConstantCategoryItem] {
        ConstantCategory.allCases.map { ConstantCategoryItem(id: $0.rawValue, title: $0.title) }
    }

    /// The constants matching a search, in sections by domain; only domains with a
    /// match appear. `categoryId` limits them to one domain, nil for all of them.
    /// The footer counts them: « 1 constante », « 61 constantes ».
    public static func constantSections(matching search: String = "", categoryId: String? = nil) -> [ConstantSection] {
        let matches = constants.filter { entry in
            (categoryId == nil || entry.item.categoryId == categoryId) && (search.isEmpty || TextSearch.contains(entry.haystack, search))
        }
        return ConstantCategory.allCases.compactMap { category in
            let items = matches.filter { $0.item.categoryId == category.rawValue }.map(\.item)
            return items.isEmpty ? nil : ConstantSection(categoryId: category.rawValue, title: category.title, constants: items)
        }
    }

    /// « Unités reconnues »: the units matching a search by symbol or name.
    public static func units(matching search: String = "") -> [UnitItem] {
        unitItems.filter { search.isEmpty || TextSearch.contains("\($0.symbol) \($0.name)", search) }
    }

    /// A constant by what is typed for it, such as `k_B`, or by one of its aliases.
    public static func constant(id: String) -> ConstantItem? {
        ConstantCatalog.lookup(id).map(ConstantItem.init)
    }

    /// The reference data, prepared once: what each constant matches in a search
    /// and how its value is written.
    private static let constants: [(item: ConstantItem, haystack: String)] = ConstantCatalog.all.map { constant in
        let item = ConstantItem(constant)
        let aliases = item.aliases.joined(separator: " ")
        return (item, "\(constant.symbol) \(constant.id) \(constant.name) \(constant.detail) \(constant.category.title) \(constant.sourceName) \(aliases)")
    }

    private static let unitItems = UnitCatalog.all.map(UnitItem.init)
}

public struct ConstantCategoryItem: Hashable, Sendable {
    public let id: String
    public let title: String
}

public struct ConstantSection: Hashable, Sendable {
    public let categoryId: String
    public let title: String
    public let constants: [ConstantItem]
}

/// A physical constant, with everything its detail page shows.
public struct ConstantItem: Hashable, Sendable {
    /// What to type in a formula (« Saisie »), such as `k_B`.
    public let id: String
    /// The symbol as written, such as `ε₀`.
    public let symbol: String
    public let name: String
    /// The value with ten significant digits and its SI unit.
    public let valueText: String
    /// The value in words: « 299 792 458 mètres par seconde ».
    public let spokenValue: String
    /// « c égale … », as TalkBack reads the row.
    public let spokenLine: String
    public let detail: String
    public let categoryId: String
    public let categoryTitle: String
    /// `exact`, `measured` or `conventional`.
    public let nature: String
    /// « Exacte », « Mesurée » or « Conventionnelle ».
    public let natureTitle: String
    /// « CODATA 2022 · NIST ».
    public let sourceName: String
    public let sourceUrl: String?
    /// Other spellings accepted in formulas.
    public let aliases: [String]

    init(_ constant: ConstantDefinition) {
        id = constant.id
        symbol = constant.symbol
        name = constant.name
        valueText = QuantityFormatter.string(constant.quantity, significantDigits: QuantityFormatter.preciseDigits)
        spokenValue = QuantityFormatter.spokenString(constant.quantity)
        spokenLine = "\(MathSpeech.description(constant.symbol) ?? constant.symbol) égale \(spokenValue)"
        detail = constant.detail
        categoryId = constant.category.rawValue
        categoryTitle = constant.category.title
        nature = constant.nature.rawValue
        natureTitle = constant.nature.title
        sourceName = constant.sourceName
        sourceUrl = constant.sourceURL?.absoluteString
        aliases = ConstantCatalog.aliases(for: constant)
    }
}

/// A unit, as the catalog and the sheet list it.
public struct UnitItem: Hashable, Sendable {
    public let symbol: String
    public let name: String
    /// Its size in SI, with ten significant digits: « 1000 m » for km.
    public let valueText: String
    public let spokenValue: String

    init(_ unit: UnitDefinition) {
        symbol = unit.symbol
        name = unit.name
        valueText = QuantityFormatter.string(unit.quantity, significantDigits: QuantityFormatter.preciseDigits)
        spokenValue = QuantityFormatter.spokenString(unit.quantity)
    }
}

/// Text search as iOS's `localizedStandardContains`: case and accents are ignored.
enum TextSearch {
    static func contains(_ text: String, _ search: String) -> Bool {
        text.localizedStandardContains(search)
    }
}
