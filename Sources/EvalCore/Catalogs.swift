import Foundation

public struct UnitDefinition: Identifiable, Hashable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let quantity: Quantity

    public init(symbol: String, name: String, quantity: Quantity) {
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
    }
}

public enum UnitCatalog: Sendable {
    private static let force = Dimension.mass + .length - .time.scaled(by: 2)
    private static let energy = force + .length
    private static let power = energy - .time
    private static let charge = Dimension.electricCurrent + .time
    private static let voltage = power - .electricCurrent

    // SI definitions and decimal prefixes: NIST SP 330, sections 2 and 3.
    // https://www.nist.gov/pml/special-publication-330/sp-330-section-2
    // https://www.nist.gov/pml/special-publication-330/sp-330-section-3
    private static let baseAndDerived: [UnitDefinition] = [
        unit("m", "Mètre", .length),
        unit("kg", "Kilogramme", .mass),
        unit("g", "Gramme", .mass, scale: 1e-3),
        unit("s", "Seconde", .time),
        unit("A", "Ampère", .electricCurrent),
        unit("K", "Kelvin", .temperature),
        unit("mol", "Mole", .amount),
        unit("cd", "Candela", .luminousIntensity),
        unit("Hz", "Hertz", .dimensionless - .time),
        unit("N", "Newton", force),
        unit("Pa", "Pascal", force - .length.scaled(by: 2)),
        unit("J", "Joule", energy),
        unit("W", "Watt", power),
        unit("C", "Coulomb", charge),
        unit("V", "Volt", voltage),
        unit("F", "Farad", charge - voltage),
        unit("Ω", "Ohm", voltage - .electricCurrent),
        unit("S", "Siemens", .electricCurrent - voltage),
        unit("Wb", "Weber", voltage + .time),
        unit("T", "Tesla", voltage + .time - .length.scaled(by: 2)),
        unit("H", "Henry", voltage + .time - .electricCurrent),
        unit("lm", "Lumen", .luminousIntensity),
        unit("lx", "Lux", .luminousIntensity - .length.scaled(by: 2)),
        unit("Bq", "Becquerel", .dimensionless - .time),
        unit("Gy", "Gray", energy - .mass),
        unit("Sv", "Sievert", energy - .mass),
        unit("kat", "Katal", .amount - .time),
        unit("rad", "Radian", .dimensionless),
        unit("sr", "Stéradian", .dimensionless),
        unit("deg", "Degré", .dimensionless, scale: .pi / 180),
        unit("min", "Minute", .time, scale: 60),
        unit("h", "Heure", .time, scale: 3_600),
        unit("L", "Litre", .length.scaled(by: 3), scale: 1e-3),
        unit("bar", "Bar", force - .length.scaled(by: 2), scale: 1e5),
        unit("eV", "Électronvolt", energy, scale: 1.602_176_634e-19)
    ]

    /// Units presented in the reference; lookup also accepts every SI decimal prefix.
    public static let all: [UnitDefinition] = baseAndDerived + [
        "km", "cm", "mm", "µm", "nm", "mg", "µg", "ms", "µs", "ns",
        "mA", "µA", "kHz", "MHz", "GHz", "kN", "kPa", "MPa", "kJ", "MJ",
        "mW", "kW", "MW", "mV", "kV", "mF", "µF", "nF", "pF", "mH",
        "mL", "keV", "MeV", "GeV"
    ].compactMap { prefixedUnit($0) }

    /// Unit symbols are case-sensitive: m, M, g and G are not interchangeable.
    public static func lookup(_ identifier: String) -> UnitDefinition? {
        let aliases: [String: String] = [
            "ohm": "Ω", "Ohm": "Ω", "Omega": "Ω", "Ω": "Ω",
            "l": "L", "hr": "h", "hour": "h", "heure": "h", "minute": "min",
            "°": "deg", "degree": "deg"
        ]
        let symbol = aliases[identifier] ?? identifier.replacingOccurrences(of: "μ", with: "µ")
        return all.first { $0.symbol == symbol } ?? prefixedUnit(symbol)
    }

    /// Dimensional analysis cannot distinguish dimensionally identical named units,
    /// so the display favors ordinary mechanics and electrical SI units.
    static func preferredSymbol(for dimension: Dimension) -> String? {
        let preferred = ["kg", "m", "s", "A", "K", "mol", "cd", "Hz", "N", "Pa", "J", "W", "C", "V", "F", "Ω", "S", "Wb", "T", "H", "kat"]
        return preferred.first { symbol in
            baseAndDerived.first { $0.symbol == symbol }?.quantity.dimension.isEquivalent(to: dimension) == true
        }
    }

    private static let prefixes: [(symbol: String, name: String, scale: Double)] = [
        ("da", "déca", 1e1), ("Q", "quetta", 1e30), ("R", "ronna", 1e27),
        ("Y", "yotta", 1e24), ("Z", "zetta", 1e21), ("E", "exa", 1e18),
        ("P", "péta", 1e15), ("T", "téra", 1e12), ("G", "giga", 1e9),
        ("M", "méga", 1e6), ("k", "kilo", 1e3), ("h", "hecto", 1e2),
        ("d", "déci", 1e-1), ("c", "centi", 1e-2), ("m", "milli", 1e-3),
        ("µ", "micro", 1e-6), ("u", "micro", 1e-6), ("n", "nano", 1e-9),
        ("p", "pico", 1e-12), ("f", "femto", 1e-15), ("a", "atto", 1e-18),
        ("z", "zepto", 1e-21), ("y", "yocto", 1e-24), ("r", "ronto", 1e-27),
        ("q", "quecto", 1e-30)
    ]

    private static func prefixedUnit(_ symbol: String) -> UnitDefinition? {
        for prefix in prefixes where symbol.hasPrefix(prefix.symbol) {
            let suffix = String(symbol.dropFirst(prefix.symbol.count))
            // Kilogram already contains a prefix. Prefix mass units from gram instead.
            guard suffix != "kg", suffix != "min", suffix != "h", suffix != "deg", suffix != "bar",
                  let base = baseAndDerived.first(where: { $0.symbol == suffix }) else { continue }
            return UnitDefinition(
                symbol: symbol,
                name: prefix.name + base.name.lowercased(),
                quantity: Quantity(value: prefix.scale * base.quantity.value, dimension: base.quantity.dimension)
            )
        }
        return nil
    }

    private static func unit(_ symbol: String, _ name: String, _ dimension: Dimension, scale: Double = 1) -> UnitDefinition {
        UnitDefinition(symbol: symbol, name: name, quantity: Quantity(value: scale, dimension: dimension))
    }
}

public struct ConstantDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let symbol: String
    public let name: String
    public let quantity: Quantity
    public let detail: String
    public let isExact: Bool

    public init(id: String? = nil, symbol: String, name: String, quantity: Quantity, detail: String, isExact: Bool) {
        self.id = id ?? symbol
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.detail = detail
        self.isExact = isExact
    }
}

public enum ConstantCatalog: Sendable {
    /// CODATA 2022, NIST SRD 121, verified October 2026. Values are bundled offline.
    /// https://physics.nist.gov/cuu/pdf/all.pdf
    /// g uses the conventional standard gravity, not a local gravity measurement:
    /// https://physics.nist.gov/cuu/pdf/adopted_2002.pdf
    /// Exact refers to the SI definition; Double still has finite numerical precision.
    public static let all: [ConstantDefinition] = [
        constant("c", "Vitesse de la lumière", 299_792_458, Dimension.length - .time,
                 "Vitesse de la lumière dans le vide. Définition exacte du SI.", exact: true),
        constant("g", "Pesanteur standard", 9.806_65, Dimension.length - .time.scaled(by: 2),
                 "Valeur conventionnelle standard ; la pesanteur locale peut varier.", exact: true),
        constant("G", "Constante gravitationnelle", 6.674_30e-11,
                 Dimension.length.scaled(by: 3) - .mass - .time.scaled(by: 2),
                 "Constante de gravitation universelle, valeur mesurée CODATA 2022.", exact: false),
        constant("h", "Constante de Planck", 6.626_070_15e-34,
                 Dimension.mass + .length.scaled(by: 2) - .time,
                 "Relie l’énergie d’un photon à sa fréquence. Définition exacte du SI.", exact: true),
        constant("hbar", "Constante de Planck réduite", 6.626_070_15e-34 / (2 * .pi),
                 Dimension.mass + .length.scaled(by: 2) - .time,
                 "ℏ = h / (2π).", exact: true, symbol: "ℏ"),
        constant("e", "Charge élémentaire", 1.602_176_634e-19, Dimension.electricCurrent + .time,
                 "Valeur positive de la charge élémentaire. Définition exacte du SI.", exact: true),
        constant("k_B", "Constante de Boltzmann", 1.380_649e-23,
                 Dimension.mass + .length.scaled(by: 2) - .time.scaled(by: 2) - .temperature,
                 "Relie température et énergie. Définition exacte du SI.", exact: true),
        constant("N_A", "Constante d’Avogadro", 6.022_140_76e23, .dimensionless - .amount,
                 "Nombre d’entités par mole. Définition exacte du SI.", exact: true),
        constant("R", "Constante des gaz parfaits", 1.380_649e-23 * 6.022_140_76e23,
                 Dimension.mass + .length.scaled(by: 2) - .time.scaled(by: 2) - .temperature - .amount,
                 "R = N_A × k_B.", exact: true),
        constant("epsilon_0", "Permittivité du vide", 8.854_187_8188e-12,
                 Dimension.electricCurrent.scaled(by: 2) + .time.scaled(by: 4) - .mass - .length.scaled(by: 3),
                 "Permittivité électrique du vide, valeur mesurée CODATA 2022.", exact: false, symbol: "ε₀"),
        constant("mu_0", "Perméabilité du vide", 1.256_637_061_27e-6,
                 Dimension.mass + .length - .time.scaled(by: 2) - .electricCurrent.scaled(by: 2),
                 "Perméabilité magnétique du vide, valeur mesurée CODATA 2022.", exact: false, symbol: "μ₀"),
        constant("pi", "Pi", .pi, .dimensionless,
                 "Rapport de la circonférence d’un cercle à son diamètre.", exact: true, symbol: "π"),
        constant("m_e", "Masse de l’électron", 9.109_383_7139e-31, .mass,
                 "Masse au repos de l’électron, valeur mesurée CODATA 2022.", exact: false),
        constant("m_p", "Masse du proton", 1.672_621_925_95e-27, .mass,
                 "Masse au repos du proton, valeur mesurée CODATA 2022.", exact: false),
        constant("alpha", "Constante de structure fine", 7.297_352_5643e-3, .dimensionless,
                 "Intensité du couplage électromagnétique, valeur mesurée CODATA 2022.", exact: false, symbol: "α")
    ]

    public static func lookup(_ identifier: String) -> ConstantDefinition? {
        let aliases: [String: String] = [
            "c_0": "c", "c0": "c", "g_n": "g", "g0": "g", "ħ": "hbar", "ℏ": "hbar",
            "kB": "k_B", "k_b": "k_B", "k": "k_B", "NA": "N_A", "Na": "N_A",
            "ε0": "epsilon_0", "ε_0": "epsilon_0", "ε₀": "epsilon_0", "eps0": "epsilon_0",
            "mu0": "mu_0", "μ0": "mu_0", "μ_0": "mu_0", "μ₀": "mu_0", "µ0": "mu_0", "µ_0": "mu_0", "µ₀": "mu_0",
            "π": "pi", "α": "alpha", "me": "m_e", "mp": "m_p"
        ]
        let id = aliases[identifier] ?? identifier
        return all.first { $0.id == id || $0.symbol == identifier }
    }

    private static func constant(
        _ id: String, _ name: String, _ value: Double, _ dimension: Dimension,
        _ detail: String, exact: Bool, symbol: String? = nil
    ) -> ConstantDefinition {
        ConstantDefinition(id: id, symbol: symbol ?? id, name: name,
                           quantity: Quantity(value: value, dimension: dimension), detail: detail, isExact: exact)
    }
}
