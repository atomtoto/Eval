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
    private static let pressure = force - .length.scaled(by: 2)

    // SI definitions and decimal prefixes: NIST SP 330, sections 2 and 3.
    // https://www.nist.gov/pml/special-publication-330/sp-330-section-2
    // https://www.nist.gov/pml/special-publication-330/sp-330-section-3
    static let baseAndDerived: [UnitDefinition] = [
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
        unit("eV", "Électronvolt", energy, scale: 1.602_176_634e-19),
        // Common non-SI units. Their prefixes follow `allowedPrefixes`.
        unit("atm", "Atmosphère normale", pressure, scale: 101_325),
        unit("Torr", "Torr", pressure, scale: 101_325 / 760),
        unit("mmHg", "Millimètre de mercure", pressure, scale: 133.322_387_415),
        unit("cal", "Calorie", energy, scale: 4.184),
        unit("Wh", "Wattheure", energy, scale: 3_600),
        unit("Ah", "Ampèreheure", charge, scale: 3_600),
        unit("Å", "Ångström", .length, scale: 1e-10),
        unit("ly", "Année-lumière", .length, scale: 9_460_730_472_580_800),
        unit("pc", "Parsec", .length, scale: 3.085_677_581_491_367e16),
        unit("Da", "Dalton", .mass, scale: 1.660_539_068_92e-27),
        unit("jour", "Jour", .time, scale: 86_400),
        unit("an", "Année", .time, scale: 31_557_600),
        unit("tr", "Tour", .dimensionless, scale: 2 * .pi),
        unit("rpm", "Tour par minute", .dimensionless - .time, scale: 2 * .pi / 60),
        unit("%", "Pour cent", .dimensionless, scale: 0.01),
        unit("ppm", "Partie par million", .dimensionless, scale: 1e-6),
        unit("ft", "Pied", .length, scale: 0.3048),
        unit("mi", "Mille", .length, scale: 1_609.344),
        unit("lb", "Livre", .mass, scale: 0.453_592_37),
        unit("lbf", "Livre-force", force, scale: 4.448_221_615_260_5)
    ]

    /// Prefixes a unit accepts; a unit that is absent accepts every SI prefix.
    /// Short symbols such as t, d, a, u, in, psi or G are deliberately not units:
    /// they are everyday variable names, and a spaced suffix would shadow them.
    static let allowedPrefixes: [String: Set<String>] = [
        "kg": [], "min": [], "h": [], "deg": [],
        "bar": ["m", "k"], // Not h: hbar stays the reduced Planck constant.
        "atm": [], "Torr": ["m"], "mmHg": [], "cal": ["k"],
        "Wh": ["m", "k", "M", "G", "T"], "Ah": ["m"],
        "Å": [], "ly": [], "pc": ["k", "M", "G"], "Da": ["k", "M"],
        "jour": [], "an": [], "tr": [], "rpm": [], "%": [], "ppm": [],
        "ft": [], "mi": [], "lb": [], "lbf": []
    ]

    /// Units presented in the reference; lookup also accepts every SI decimal prefix.
    public static let all: [UnitDefinition] = baseAndDerived + [
        "km", "cm", "mm", "µm", "nm", "mg", "µg", "ms", "µs", "ns",
        "mA", "µA", "kHz", "MHz", "GHz", "kN", "kPa", "MPa", "kJ", "MJ",
        "mW", "kW", "MW", "mV", "kV", "mF", "µF", "nF", "pF", "mH",
        "mL", "keV", "MeV", "GeV", "mbar", "hPa", "kWh", "MWh", "mAh", "kcal",
        "kpc", "Mpc", "kDa", "mTorr"
    ].compactMap { prefixedUnit($0) }

    /// Spellings that name a unit without being its symbol. The litre aliases are
    /// explicit: a generic «*l» rule would turn variables such as al or pl into units.
    private static let aliases: [String: String] = [
        "ohm": "Ω", "Ohm": "Ω", "Omega": "Ω", "l": "L", "hr": "h", "hour": "h", "heure": "h",
        "minute": "min", "°": "deg", "degree": "deg", "angstrom": "Å", "day": "jour",
        "yr": "an", "year": "an",
        "kl": "kL", "hl": "hL", "dl": "dL", "cl": "cL", "ml": "mL",
        "µl": "µL", "μl": "µL", "ul": "µL"
    ]

    /// Every accepted symbol, built once: prefixed forms first, then listed
    /// units, which take precedence, as `all` always did.
    private static let index: [String: UnitDefinition] = {
        var table: [String: UnitDefinition] = [:]
        for prefix in prefixes {
            for base in baseAndDerived where accepts(prefix.symbol, base.symbol) {
                let symbol = prefix.symbol + base.symbol
                if table[symbol] == nil { table[symbol] = prefixed(symbol, prefix, base) }
            }
            // kohm, Mohm: the spelled-out ohm takes prefixes like its symbol.
            if let ohm = baseAndDerived.first(where: { $0.symbol == "Ω" }) {
                for spelling in ["ohm", "Ohm"] {
                    let symbol = prefix.symbol + spelling
                    if table[symbol] == nil { table[symbol] = prefixed(symbol, prefix, ohm) }
                }
            }
        }
        for unit in all.reversed() { table[unit.symbol] = unit }
        return table
    }()

    /// Unit symbols are case-sensitive: m, M, g and G are not interchangeable.
    public static func lookup(_ identifier: String) -> UnitDefinition? {
        if let alias = aliases[identifier] { return index[alias] }
        if identifier.contains("μ") { return index[identifier.replacingOccurrences(of: "μ", with: "µ")] }
        return index[identifier]
    }

    /// Unit expressions offered by an "Afficher en" menu, in presentation order.
    private static let displaySuggestionSymbols = [
        "km/h", "m/s", "km", "m", "cm", "mm", "µm", "nm", "Å", "au", "ly", "pc", "ft", "mi",
        "kg", "g", "mg", "lb", "Da", "s", "min", "h", "jour", "an", "ms", "µs",
        "J", "kJ", "MJ", "Wh", "kWh", "cal", "kcal", "eV", "keV", "MeV", "W", "kW", "MW",
        "N", "kN", "lbf", "Pa", "kPa", "hPa", "bar", "mbar", "atm", "mmHg",
        "L", "mL", "g/cm³", "kg/m³", "mol/L", "Hz", "kHz", "MHz", "rad/s", "tr/min", "Bq",
        "A", "mA", "mAh", "Ah", "C", "V", "mV", "kV", "Ω", "kΩ", "F", "µF", "H", "T",
        "%", "ppm", "deg", "rad", "tr"
    ]

    private static let displaySuggestionIndex: [(symbol: String, dimension: Dimension)] =
        displaySuggestionSymbols.compactMap { symbol in
            NotebookEngine.unitQuantity(of: symbol).map { (symbol, $0.dimension) }
        }

    /// Curated units for displaying a result of this dimension with `->`.
    /// Dimensionally identical units (Hz, rad/s, Bq) are all offered: only the
    /// user knows which one is meant.
    public static func displaySuggestions(compatibleWith dimension: Dimension) -> [String] {
        displaySuggestionIndex.filter { $0.dimension.isEquivalent(to: dimension) }.map(\.symbol)
    }

    /// Dimensional analysis cannot distinguish dimensionally identical named units,
    /// so the display favors ordinary mechanics and electrical SI units. Hz and Bq
    /// are never inferred: s⁻¹ may be a frequency, an angular velocity or an activity.
    static func preferredSymbol(for dimension: Dimension) -> String? {
        let preferred = ["kg", "m", "s", "A", "K", "mol", "cd", "N", "Pa", "J", "W", "C", "V", "F", "Ω", "S", "Wb", "T", "H", "kat"]
        return preferred.first { symbol in
            baseAndDerived.first { $0.symbol == symbol }?.quantity.dimension.isEquivalent(to: dimension) == true
        }
    }

    static let prefixes: [(symbol: String, name: String, scale: Double)] = [
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

    private static func accepts(_ prefix: String, _ unit: String) -> Bool {
        allowedPrefixes[unit]?.contains(prefix) ?? true
    }

    private static func prefixed(_ symbol: String, _ prefix: (symbol: String, name: String, scale: Double),
                                 _ base: UnitDefinition) -> UnitDefinition {
        UnitDefinition(
            symbol: symbol,
            name: prefix.name + base.name.lowercased(),
            quantity: Quantity(value: prefix.scale * base.quantity.value, dimension: base.quantity.dimension)
        )
    }

    /// The first prefix, in declaration order, that gives a unit with this symbol.
    private static func prefixedUnit(_ symbol: String) -> UnitDefinition? {
        for prefix in prefixes where symbol.hasPrefix(prefix.symbol) {
            let suffix = String(symbol.dropFirst(prefix.symbol.count))
            guard let base = baseAndDerived.first(where: { $0.symbol == suffix }),
                  accepts(prefix.symbol, suffix) else { continue }
            return prefixed(symbol, prefix, base)
        }
        return nil
    }

    private static func unit(_ symbol: String, _ name: String, _ dimension: Dimension, scale: Double = 1) -> UnitDefinition {
        UnitDefinition(symbol: symbol, name: name, quantity: Quantity(value: scale, dimension: dimension))
    }
}

public enum ConstantCategory: String, CaseIterable, Identifiable, Sendable {
    case fundamental, electromagnetism, quantum, thermodynamics, chemistry, astronomy, mathematics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fundamental: "Grandeurs fondamentales"
        case .electromagnetism: "Électromagnétisme"
        case .quantum: "Quantique et particules"
        case .thermodynamics: "Thermodynamique et rayonnement"
        case .chemistry: "Chimie et gaz"
        case .astronomy: "Astronomie"
        case .mathematics: "Mathématiques"
        }
    }
}

public enum ConstantNature: String, Sendable {
    /// An exact definition or exact derivation. Double representation remains finite.
    case exact
    /// A measured constant, including quantities derived from measured constants.
    case measured
    /// A fixed reference value, not a claim about local or actual physical conditions.
    case conventional

    public var title: String {
        switch self {
        case .exact: "Exacte"
        case .measured: "Mesurée"
        case .conventional: "Conventionnelle"
        }
    }
}

public struct ConstantDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let symbol: String
    public let name: String
    public let quantity: Quantity
    public let detail: String
    public let isExact: Bool
    public let category: ConstantCategory
    public let nature: ConstantNature
    public let sourceName: String
    public let sourceURL: URL?

    public init(
        id: String? = nil, symbol: String, name: String, quantity: Quantity, detail: String, isExact: Bool,
        category: ConstantCategory = .fundamental, nature: ConstantNature? = nil,
        sourceName: String = "CODATA 2022 · NIST", sourceURL: URL? = nil
    ) {
        self.id = id ?? symbol
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.detail = detail
        self.isExact = isExact
        self.category = category
        self.nature = nature ?? (isExact ? .exact : .measured)
        self.sourceName = sourceName
        self.sourceURL = sourceURL
    }
}

public enum ConstantCatalog: Sendable {
    private static let codata = "https://physics.nist.gov/cuu/Constants/Table/allascii.txt"
    private static let bipm = "https://www.bipm.org/en/measurement-units/si-defining-constants"
    private static let iau2015 = "https://www.iau.org/common/Uploaded%20files/IAUGA2015-Resolution-B3-recommended-nominal-conversion.pdf"
    private static let iau2012 = "https://iauarchive.eso.org/static/resolutions/IAU2012_English.pdf"
    private static let dlmfExponential = "https://dlmf.nist.gov/4.2"
    private static let dlmfTrigonometry = "https://dlmf.nist.gov/4.14"

    private static let lightSpeed = 299_792_458.0
    private static let planck = 6.626_070_15e-34
    private static let elementaryCharge = 1.602_176_634e-19
    private static let boltzmann = 1.380_649e-23
    private static let avogadro = 6.022_140_76e23
    private static let gasConstant = boltzmann * avogadro

    private static let force = Dimension.mass + .length - .time.scaled(by: 2)
    private static let energy = force + .length
    private static let power = energy - .time
    private static let action = energy + .time
    private static let charge = Dimension.electricCurrent + .time
    private static let voltage = power - .electricCurrent
    private static let resistance = voltage - .electricCurrent
    private static let magneticField = voltage + .time - .length.scaled(by: 2)
    private static let magneticMoment = energy - magneticField
    private static let massParameter = Dimension.length.scaled(by: 3) - .time.scaled(by: 2)

    /// Sources checked in October 2026; the full catalogue is available offline.
    /// Exact and conventional definitions still use finite-precision Double values.
    /// Gas reference values include their temperature and pressure in the identifier and detail.
    /// Astronomical nominal values are conversion references, not current measurements.
    public static let all: [ConstantDefinition] = fundamental + electromagnetism + quantum
        + thermodynamics + chemistry + astronomy + mathematics

    private static let fundamental: [ConstantDefinition] = [
        constant("c", "Vitesse de la lumière", lightSpeed, Dimension.length - .time,
                 "Vitesse dans le vide. Définition exacte du SI.", category: .fundamental, nature: .exact),
        constant("g", "Pesanteur standard", 9.806_65, Dimension.length - .time.scaled(by: 2),
                 "Valeur conventionnelle standard ; la pesanteur locale peut varier.", category: .fundamental, nature: .conventional),
        constant("G", "Constante gravitationnelle", 6.674_30e-11, massParameter - .mass,
                 "Gravitation universelle. Valeur mesurée CODATA 2022.", category: .fundamental),
        constant("nu_Cs", "Fréquence du césium 133", 9_192_631_770, .dimensionless - .time,
                 "Transition hyperfine non perturbée de l’état fondamental du césium 133 ; définition de la seconde.",
                 category: .fundamental, nature: .exact, symbol: "ν_Cs", sourceName: "Définition du SI · BIPM", source: bipm),
        constant("K_cd", "Efficacité lumineuse de référence", 683, .luminousIntensity - power,
                 "Rayonnement monochromatique de fréquence 540 × 10¹² Hz ; définition de la candela.",
                 category: .fundamental, nature: .exact, sourceName: "Définition du SI · BIPM", source: bipm)
    ]

    private static let electromagnetism: [ConstantDefinition] = [
        constant("e", "Charge élémentaire", elementaryCharge, charge,
                 "Charge élémentaire positive. Définition exacte du SI.", category: .electromagnetism, nature: .exact),
        constant("epsilon_0", "Permittivité du vide", 8.854_187_8188e-12,
                 Dimension.electricCurrent.scaled(by: 2) + .time.scaled(by: 4) - .mass - .length.scaled(by: 3),
                 "Permittivité électrique du vide. Valeur mesurée CODATA 2022.", category: .electromagnetism, symbol: "ε₀"),
        constant("mu_0", "Perméabilité du vide", 1.256_637_061_27e-6,
                 force - .electricCurrent.scaled(by: 2),
                 "Perméabilité magnétique du vide ; elle n’est plus exacte depuis la redéfinition du SI de 2019.",
                 category: .electromagnetism, symbol: "μ₀"),
        constant("alpha", "Constante de structure fine", 7.297_352_5643e-3, .dimensionless,
                 "Couplage électromagnétique. Valeur mesurée CODATA 2022.", category: .electromagnetism, symbol: "α"),
        constant("k_e", "Constante de Coulomb", 1 / (4 * .pi * 8.854_187_8188e-12),
                 force + .length.scaled(by: 2) - charge.scaled(by: 2),
                 "k_e = 1 / (4π ε₀). Dépend de la permittivité mesurée du vide.", category: .electromagnetism),
        constant("Z_0", "Impédance du vide", 376.730_313_412, resistance,
                 "Impédance caractéristique du vide. Valeur mesurée CODATA 2022.", category: .electromagnetism),
        constant("mu_B", "Magnéton de Bohr", 9.274_010_0657e-24, magneticMoment,
                 "Moment magnétique de référence de l’électron ; μ_B = eℏ / (2m_e).", category: .electromagnetism, symbol: "μ_B"),
        constant("mu_N", "Magnéton nucléaire", 5.050_783_7393e-27, magneticMoment,
                 "Moment magnétique de référence nucléaire ; μ_N = eℏ / (2m_p).", category: .electromagnetism, symbol: "μ_N"),
        constant("Phi_0", "Quantum de flux magnétique", planck / (2 * elementaryCharge), voltage + .time,
                 "Φ₀ = h / (2e). Dérivé des définitions exactes du SI.", category: .electromagnetism, nature: .exact, symbol: "Φ₀"),
        constant("R_K", "Constante de von Klitzing", planck / (elementaryCharge * elementaryCharge), resistance,
                 "R_K = h / e². Référence de résistance quantique, exacte dans le SI.", category: .electromagnetism, nature: .exact),
        constant("G_0", "Quantum de conductance", 2 * elementaryCharge * elementaryCharge / planck, .dimensionless - resistance,
                 "G₀ = 2e² / h. Dérivé des définitions exactes du SI.", category: .electromagnetism, nature: .exact, symbol: "G₀"),
        constant("K_J", "Constante de Josephson", 2 * elementaryCharge / planck, .dimensionless - .time - voltage,
                 "K_J = 2e / h. Conversion fréquence–tension exacte dans le SI.", category: .electromagnetism, nature: .exact)
    ]

    private static let quantum: [ConstantDefinition] = [
        constant("h", "Constante de Planck", planck, action,
                 "Relie l’énergie d’un photon à sa fréquence. Définition exacte du SI.", category: .quantum, nature: .exact),
        constant("hbar", "Constante de Planck réduite", planck / (2 * .pi), action,
                 "ℏ = h / (2π). Dérivée de la définition exacte du SI.", category: .quantum, nature: .exact, symbol: "ℏ"),
        constant("m_e", "Masse de l’électron", 9.109_383_7139e-31, .mass,
                 "Masse au repos de l’électron. Valeur mesurée CODATA 2022.", category: .quantum),
        constant("m_p", "Masse du proton", 1.672_621_925_95e-27, .mass,
                 "Masse au repos du proton. Valeur mesurée CODATA 2022.", category: .quantum),
        constant("m_n", "Masse du neutron", 1.674_927_500_56e-27, .mass,
                 "Masse au repos du neutron. Valeur mesurée CODATA 2022.", category: .quantum),
        constant("m_mu", "Masse du muon", 1.883_531_627e-28, .mass,
                 "Masse au repos du muon. Valeur mesurée CODATA 2022.", category: .quantum, symbol: "m_μ"),
        constant("m_tau", "Masse du tau", 3.167_54e-27, .mass,
                 "Masse au repos du lepton tau. Valeur mesurée CODATA 2022.", category: .quantum, symbol: "m_τ"),
        constant("m_d", "Masse du deutéron", 3.343_583_7768e-27, .mass,
                 "Noyau du deutérium, sans électron. Valeur mesurée CODATA 2022.", category: .quantum),
        constant("m_alpha", "Masse de la particule alpha", 6.644_657_3450e-27, .mass,
                 "Noyau d’hélium 4, sans électron. Valeur mesurée CODATA 2022.", category: .quantum, symbol: "m_α"),
        constant("m_t", "Masse du triton", 5.007_356_7512e-27, .mass,
                 "Noyau du tritium, sans électron. Valeur mesurée CODATA 2022.", category: .quantum),
        constant("m_helion", "Masse de l’hélion", 5.006_412_7862e-27, .mass,
                 "Noyau d’hélium 3, sans électron. Valeur mesurée CODATA 2022.", category: .quantum),
        constant("a_0", "Rayon de Bohr", 5.291_772_105_44e-11, .length,
                 "Longueur atomique de référence. Valeur mesurée CODATA 2022.", category: .quantum, symbol: "a₀"),
        constant("R_inf", "Constante de Rydberg", 10_973_731.568_157, .dimensionless - .length,
                 "Nombre d’onde de référence pour un noyau de masse infinie. Valeur mesurée CODATA 2022.", category: .quantum, symbol: "R_∞"),
        constant("E_h", "Énergie de Hartree", 4.359_744_722_2060e-18, energy,
                 "Unité atomique d’énergie. Valeur mesurée CODATA 2022.", category: .quantum),
        constant("r_e", "Rayon classique de l’électron", 2.817_940_3205e-15, .length,
                 "Rayon classique de référence, distinct d’une taille physique mesurée de l’électron.", category: .quantum),
        constant("lambda_C", "Longueur d’onde de Compton", 2.426_310_235_38e-12, .length,
                 "Pour l’électron : λ_C = h / (m_e c). Valeur mesurée CODATA 2022.", category: .quantum, symbol: "λ_C"),
        constant("sigma_T", "Section efficace de Thomson", 6.652_458_7051e-29, .length.scaled(by: 2),
                 "Diffusion Thomson de l’électron. Valeur mesurée CODATA 2022.", category: .quantum, symbol: "σ_T"),
        constant("t_atomic", "Unité atomique de temps", 2.418_884_326_5864e-17, .time,
                 "Temps atomique de référence : ℏ / E_h. Valeur mesurée CODATA 2022.", category: .quantum),
        constant("l_P", "Longueur de Planck", 1.616_255e-35, .length,
                 "Dépend de la constante gravitationnelle mesurée G. Valeur CODATA 2022.", category: .quantum),
        constant("m_P", "Masse de Planck", 2.176_434e-8, .mass,
                 "Dépend de la constante gravitationnelle mesurée G. Valeur CODATA 2022.", category: .quantum),
        constant("t_P", "Temps de Planck", 5.391_247e-44, .time,
                 "Dépend de la constante gravitationnelle mesurée G. Valeur CODATA 2022.", category: .quantum),
        constant("T_P", "Température de Planck", 1.416_784e32, .temperature,
                 "Dépend de la constante gravitationnelle mesurée G. Valeur CODATA 2022.", category: .quantum)
    ]

    private static let thermodynamics: [ConstantDefinition] = [
        constant("k_B", "Constante de Boltzmann", boltzmann, energy - .temperature,
                 "Relie température et énergie. Définition exacte du SI.", category: .thermodynamics, nature: .exact),
        constant("sigma_SB", "Constante de Stefan–Boltzmann",
                 2 * pow(.pi, 5) * pow(boltzmann, 4) / (15 * pow(planck, 3) * lightSpeed * lightSpeed),
                 power - .length.scaled(by: 2) - .temperature.scaled(by: 4),
                 "Puissance rayonnée par un corps noir : P = σ A T⁴. Dérivée des définitions exactes du SI.",
                 category: .thermodynamics, nature: .exact, symbol: "σ_SB"),
        constant("b_Wien", "Déplacement de Wien (longueur d’onde)", 2.897_771_955e-3, .length + .temperature,
                 "Maximum spectral par longueur d’onde d’un corps noir : λ_max T = b. Valeur théorique exacte, représentation arrondie.",
                 category: .thermodynamics, nature: .exact),
        constant("b_Wien_frequency", "Déplacement de Wien (fréquence)", 5.878_925_757e10, .dimensionless - .time - .temperature,
                 "Maximum spectral par fréquence d’un corps noir : ν_max / T. Valeur théorique exacte, représentation arrondie.",
                 category: .thermodynamics, nature: .exact),
        constant("c_1", "Première constante de rayonnement", 2 * .pi * planck * lightSpeed * lightSpeed,
                 power + .length.scaled(by: 2),
                 "c₁ = 2πhc², pour l’exitance spectrale du corps noir. Dérivée exacte du SI.",
                 category: .thermodynamics, nature: .exact, symbol: "c₁"),
        constant("c_2", "Seconde constante de rayonnement", planck * lightSpeed / boltzmann, .length + .temperature,
                 "c₂ = hc / k_B, utilisée dans la loi de Planck. Dérivée exacte du SI.",
                 category: .thermodynamics, nature: .exact, symbol: "c₂")
    ]

    private static let chemistry: [ConstantDefinition] = [
        constant("N_A", "Constante d’Avogadro", avogadro, .dimensionless - .amount,
                 "Nombre d’entités par mole. Définition exacte du SI.", category: .chemistry, nature: .exact),
        constant("R", "Constante des gaz parfaits", gasConstant, energy - .temperature - .amount,
                 "R = N_A × k_B. Dérivée des définitions exactes du SI.", category: .chemistry, nature: .exact),
        constant("F_const", "Constante de Faraday", elementaryCharge * avogadro, charge - .amount,
                 "Valeur absolue de la charge par mole d’électrons : F = N_A e. Saisir F_const ; F reste l’unité farad.", category: .chemistry, nature: .exact),
        constant("m_u", "Constante de masse atomique", 1.660_539_068_92e-27, .mass,
                 "Un douzième de la masse d’un atome de carbone 12 libre, au repos et dans son état fondamental.", category: .chemistry),
        constant("M_u", "Constante de masse molaire", 1.000_000_001_05e-3, Dimension.mass - .amount,
                 "M_u = N_A m_u. Valeur mesurée ; elle n’est plus exactement 1 g/mol depuis 2019.", category: .chemistry),
        constant("M_C12", "Masse molaire du carbone 12", 12.000_000_0126e-3, Dimension.mass - .amount,
                 "Isotope carbone 12 : M = 12 M_u. Valeur mesurée CODATA 2022.", category: .chemistry),
        constant("p_standard", "Pression d’état standard", 100_000, force - .length.scaled(by: 2),
                 "Pression de référence conventionnelle : 100 kPa (1 bar).", category: .chemistry, nature: .conventional),
        constant("p_atm", "Atmosphère normale", 101_325, force - .length.scaled(by: 2),
                 "Pression de référence conventionnelle : 101,325 kPa ; différente de l’état standard à 100 kPa.", category: .chemistry, nature: .conventional),
        constant("V_m_100kPa", "Volume molaire idéal à 100 kPa", gasConstant * 273.15 / 100_000,
                 Dimension.length.scaled(by: 3) - .amount,
                 "Gaz parfait à 273,15 K et 100 kPa ; V_m = RT / p. Dérivé exact pour ces conditions de référence.", category: .chemistry, nature: .exact),
        constant("V_m_atm", "Volume molaire idéal à 1 atm", gasConstant * 273.15 / 101_325,
                 Dimension.length.scaled(by: 3) - .amount,
                 "Gaz parfait à 273,15 K et 101,325 kPa ; V_m = RT / p. Dérivé exact pour ces conditions de référence.", category: .chemistry, nature: .exact),
        constant("n_L_100kPa", "Constante de Loschmidt à 100 kPa", 100_000 / (boltzmann * 273.15), .dimensionless - .length.scaled(by: 3),
                 "Nombre d’entités par m³ de gaz parfait à 273,15 K et 100 kPa : p / (k_B T).", category: .chemistry, nature: .exact),
        constant("n_L_atm", "Constante de Loschmidt à 1 atm", 101_325 / (boltzmann * 273.15), .dimensionless - .length.scaled(by: 3),
                 "Nombre d’entités par m³ de gaz parfait à 273,15 K et 101,325 kPa : p / (k_B T).", category: .chemistry, nature: .exact)
    ]

    private static let astronomy: [ConstantDefinition] = [
        constant("au", "Unité astronomique", 149_597_870_700, .length,
                 "Longueur de référence définie exactement par l’UAI en 2012.", category: .astronomy, nature: .conventional,
                 sourceName: "Résolution 2012 B2 · UAI", source: iau2012),
        nominal("R_sun_N", "Rayon solaire nominal", 6.957e8, .length,
                "Rayon nominal solaire de référence pour les conversions ; le rayon solaire réel peut varier."),
        nominal("L_sun_N", "Luminosité solaire nominale", 3.828e26, power,
                "Luminosité nominale solaire de référence pour les conversions ; ce n’est pas une mesure instantanée."),
        nominal("T_sun_N", "Température solaire nominale", 5_772, .temperature,
                "Température effective nominale solaire de référence pour les conversions."),
        nominal("GM_sun_N", "Paramètre de masse solaire nominal", 1.327_124_4e20, massParameter,
                "Produit GM nominal du Soleil, en m³/s². Pour une masse en kg, diviser par la valeur mesurée de G."),
        nominal("GM_earth_N", "Paramètre de masse terrestre nominal", 3.986_004e14, massParameter,
                "Produit GM nominal de la Terre, en m³/s². Référence de conversion conventionnelle."),
        nominal("R_earth_equatorial_N", "Rayon terrestre équatorial nominal", 6.3781e6, .length,
                "Rayon équatorial nominal de la Terre ; différent du rayon polaire."),
        nominal("R_earth_polar_N", "Rayon terrestre polaire nominal", 6.3568e6, .length,
                "Rayon polaire nominal de la Terre ; différent du rayon équatorial.")
    ]

    private static let mathematics: [ConstantDefinition] = [
        constant("pi", "Pi", .pi, .dimensionless,
                 "Rapport de la circonférence d’un cercle à son diamètre. Représentation numérique arrondie.",
                 category: .mathematics, nature: .exact, symbol: "π", sourceName: "DLMF · NIST", source: dlmfTrigonometry),
        constant("euler", "Nombre d’Euler", exp(1), .dimensionless,
                 "Base du logarithme naturel : exp(1). Saisir euler ; e représente la charge élémentaire.",
                 category: .mathematics, nature: .exact, sourceName: "DLMF · NIST", source: dlmfExponential),
        constant("tau", "Tau", 2 * .pi, .dimensionless,
                 "τ = 2π, angle d’un tour complet en radians. Représentation numérique arrondie.",
                 category: .mathematics, nature: .exact, symbol: "τ", sourceName: "DLMF · NIST", source: dlmfTrigonometry)
    ]

    public static func lookup(_ identifier: String) -> ConstantDefinition? {
        let id = aliases[identifier] ?? identifier
        return all.first { $0.id == id || $0.symbol == identifier }
    }

    /// Also exposed to reference search so a familiar alias finds the canonical entry.
    public static func aliases(for constant: ConstantDefinition) -> [String] {
        aliases.filter { $0.value == constant.id }.map(\.key).sorted()
    }

    private static let aliases: [String: String] = [
        "c_0": "c", "c0": "c", "g_n": "g", "g0": "g", "ħ": "hbar", "ℏ": "hbar",
        "kB": "k_B", "k_b": "k_B", "k": "k_B", "NA": "N_A", "Na": "N_A",
        "ε0": "epsilon_0", "ε_0": "epsilon_0", "ε₀": "epsilon_0", "eps0": "epsilon_0",
        "mu0": "mu_0", "μ0": "mu_0", "μ_0": "mu_0", "μ₀": "mu_0", "µ0": "mu_0", "µ_0": "mu_0", "µ₀": "mu_0",
        "π": "pi", "α": "alpha", "me": "m_e", "mp": "m_p", "mn": "m_n",
        "Faraday": "F_const", "faraday": "F_const", "F_Faraday": "F_const",
        "atomic_mass": "m_u", "amu": "m_u", "Bohr_radius": "a_0", "a0": "a_0",
        "Rydberg": "R_inf", "R_infinity": "R_inf", "hartree": "E_h",
        "muB": "mu_B", "μ_B": "mu_B", "µ_B": "mu_B", "muN": "mu_N", "μ_N": "mu_N", "µ_N": "mu_N",
        "Phi0": "Phi_0", "phi_0": "Phi_0", "Φ0": "Phi_0", "Φ₀": "Phi_0",
        "sigma": "sigma_SB", "σ": "sigma_SB", "σ_SB": "sigma_SB", "Stefan_Boltzmann": "sigma_SB",
        "lambda_Compton": "lambda_C", "λ_C": "lambda_C", "σ_T": "sigma_T",
        "ν_Cs": "nu_Cs", "AU": "au", "ua": "au", "τ": "tau"
    ]

    private static func constant(
        _ id: String, _ name: String, _ value: Double, _ dimension: Dimension, _ detail: String,
        category: ConstantCategory, nature: ConstantNature = .measured, symbol: String? = nil,
        sourceName: String = "CODATA 2022 · NIST", source: String = codata
    ) -> ConstantDefinition {
        ConstantDefinition(id: id, symbol: symbol ?? id, name: name,
                           quantity: Quantity(value: value, dimension: dimension), detail: detail,
                           isExact: nature != .measured, category: category, nature: nature,
                           sourceName: sourceName, sourceURL: URL(string: source))
    }

    private static func nominal(
        _ id: String, _ name: String, _ value: Double, _ dimension: Dimension, _ detail: String
    ) -> ConstantDefinition {
        constant(id, name, value, dimension, detail + " Valeur nominale définie exactement par l’UAI en 2015.",
                 category: .astronomy, nature: .conventional, sourceName: "Résolution 2015 B3 · UAI", source: iau2015)
    }
}
