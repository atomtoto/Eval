import XCTest
@testable import EvalCore

final class MathSpeechTests: XCTestCase {
    private func said(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        MathSpeech.description(source) ?? "nil: \(source)"
    }

    private func check(_ cases: KeyValuePairs<String, String>, file: StaticString = #filePath, line: UInt = #line) {
        for (source, expected) in cases {
            XCTAssertEqual(said(source), expected, source, file: file, line: line)
        }
    }

    private static let energy = EvalCore.Dimension(length: 2, mass: 1, time: -2)
    private static let force = EvalCore.Dimension(length: 1, mass: 1, time: -2)
    private static let speed = EvalCore.Dimension(length: 1, time: -1)
    private static let acceleration = EvalCore.Dimension(length: 1, time: -2)
    private static let frequency = EvalCore.Dimension(time: -1)

    // MARK: Operators

    func testBasicOperatorsBecomeWords() {
        check([
            "E = 0,5 * m * v²": "E égale 0,5 fois m fois v au carré",
            "a + b - c": "a plus b moins c",
            "a × b": "a fois b",
            "N_A * k_B": "N indice A fois k indice B",
            "2 * pi * r": "2 fois pi fois r",
            "x³": "x au cube",
            "2^10": "2 puissance 10",
            "x^-2": "x puissance moins 2",
            "-x": "moins x",
            "+x": "plus x",
            "e^x": "e puissance x"
        ])
    }

    func testDivisionIsNeverLostWhenOperatorsAreSkipped() {
        check([
            "a / b": "a sur b",
            "E = h * c / lambda": "E égale fraction, numérateur : h fois c ; dénominateur : lambda ; fin de fraction",
            "a / (b * c)": "fraction, numérateur : a ; dénominateur : b fois c ; fin de fraction",
            "a / b * c": "a sur b fois c",
            "(a + b) / c": "fraction, numérateur : a plus b ; dénominateur : c ; fin de fraction",
            "k_e * q1 * q2 / r²":
                "fraction, numérateur : k indice e fois q1 fois q2 ; dénominateur : r au carré ; fin de fraction",
            "a / (b / c)": "fraction, numérateur : a ; dénominateur : b sur c ; fin de fraction",
            "x² / 2": "x au carré sur 2",
            "sin(x) / 2": "sinus de x sur 2"
        ])
    }

    func testGroupingFollowsTheSourceAndKeepsPrecedence() {
        check([
            "(a + b) * c": "parenthèse a plus b fin de parenthèse fois c",
            "a - (b + c)": "a moins parenthèse b plus c fin de parenthèse",
            "a - (-b)": "a moins parenthèse moins b fin de parenthèse",
            "a * -b": "a fois parenthèse moins b fin de parenthèse",
            "-(a + b)": "moins parenthèse a plus b fin de parenthèse",
            "(a + b)^2": "parenthèse a plus b fin de parenthèse au carré",
            "x^(n + 1)": "x puissance parenthèse n plus 1 fin de parenthèse",
            "a^b^c": "a puissance parenthèse b puissance c fin de parenthèse",
            "2 * (3 m + 4 m)": "2 fois parenthèse 3 mètres plus 4 mètres fin de parenthèse",
            "(5 m)²": "parenthèse 5 mètres fin de parenthèse au carré"
        ])
    }

    func testPrefixFunctionsAreDistinguishedFromTheirNeighbours() {
        check([
            "sin(x)^2": "parenthèse sinus de x fin de parenthèse au carré",
            "sin(x²)": "sinus de parenthèse x au carré fin de parenthèse",
            "sin(x) + 1": "sinus de x plus 1",
            "sin(x + 1)": "sinus de parenthèse x plus 1 fin de parenthèse",
            "sin(2 * theta)": "sinus de parenthèse 2 fois theta fin de parenthèse",
            "sin(30 deg)": "sinus de 30 degrés",
            "sqrt(sqrt(x))": "racine carrée de racine carrée de x",
            "sqrt(G * M / r)":
                "racine carrée de parenthèse fraction, numérateur : G fois M ; dénominateur : r ; fin de fraction fin de parenthèse"
        ])
    }

    // MARK: Functions

    func testEveryFunctionHasAFrenchName() {
        check([
            "sqrt(x)": "racine carrée de x",
            "√x": "racine carrée de x",
            "abs(x)": "valeur absolue de x",
            "sin(x)": "sinus de x",
            "cos(x)": "cosinus de x",
            "tan(x)": "tangente de x",
            "asin(x)": "arc sinus de x",
            "arcsin(x)": "arc sinus de x",
            "acos(x)": "arc cosinus de x",
            "arccos(x)": "arc cosinus de x",
            "atan(x)": "arc tangente de x",
            "arctan(x)": "arc tangente de x",
            "sinh(x)": "sinus hyperbolique de x",
            "cosh(x)": "cosinus hyperbolique de x",
            "tanh(x)": "tangente hyperbolique de x",
            "exp(x)": "exponentielle de x",
            "ln(x)": "logarithme népérien de x",
            "log(x)": "logarithme décimal de x",
            "log10(x)": "logarithme décimal de x",
            "cbrt(x)": "racine cubique de x",
            "floor(x)": "partie entière de x",
            "ceil(x)": "plafond de x",
            "round(x)": "arrondi de x"
        ])
    }

    func testFunctionsOfSeveralArguments() {
        check([
            "atan2(y; x)": "arc tangente à deux arguments de y et x",
            "log(x; 2)": "logarithme de x en base 2",
            "log(x + 1; b)": "logarithme de parenthèse x plus 1 fin de parenthèse en base b",
            "min(a; b)": "minimum de a et b",
            "max(a; b; c)": "maximum de a, b et c",
            "max(a + 1; b)": "maximum de a plus 1 et b",
            "root(x; 3)": "racine troisième de x",
            "root(x; 5)": "racine cinquième de x",
            "root(x; n)": "racine d’indice n de x",
            "root(x; 12)": "racine d’indice 12 de x",
            // A call with several arguments would swallow what follows it.
            "min(a; b) + 1": "parenthèse minimum de a et b fin de parenthèse plus 1",
            "2 * max(a; b)": "2 fois parenthèse maximum de a et b fin de parenthèse"
        ])
    }

    func testFactorialAndPercent() {
        check([
            "5!": "5 factorielle",
            "n!": "n factorielle",
            "(n + 1)!": "parenthèse n plus 1 fin de parenthèse factorielle",
            "n! / k!": "n factorielle sur k factorielle",
            "20 %": "20 pour cent",
            "1 %": "1 pour cent",
            "p = 15 %": "p égale 15 pour cent"
        ])
    }

    // MARK: Numbers and names

    func testNumbersAreReadWithScientificNotationSpelledOut() {
        check([
            "x = 3,01e11": "x égale 3,01 fois 10 puissance 11",
            "x = 1e-5": "x égale 1 fois 10 puissance moins 5",
            "x = 0,001": "x égale 0,001",
            "x = 1,5": "x égale 1,5",
            "x = 12345678": "x égale 12345678"
        ])
        XCTAssertEqual(MathSpeech.number(-4.5), "moins 4,5")
        XCTAssertEqual(MathSpeech.number(-3.01e11), "moins 3,01 fois 10 puissance 11")
        XCTAssertEqual(MathSpeech.number(.infinity), "infini")
        XCTAssertEqual(MathSpeech.number(0), "0")
    }

    func testNamesKeepGreekLettersAndSpellSubscripts() {
        check([
            "lambda * nu": "lambda fois nu",
            "λ": "lambda",
            "π * r²": "pi fois r au carré",
            "ΔT": "Delta T",
            "ℏ": "h barre",
            "hbar": "h barre",
            "E_c": "E indice c",
            "GM_earth_N": "GM indice earth indice N",
            "q1": "q1",
            "v₀": "v0"
        ])
    }

    // MARK: Units

    func testUnitsUseCatalogueNamesWithAPluralFromTwo() {
        check([
            "d = 1 m": "d égale 1 mètre",
            "d = 1,5 m": "d égale 1,5 mètre",
            "d = 2 m": "d égale 2 mètres",
            "d = 0 m": "d égale 0 mètre",
            "t = 3 µs": "t égale 3 microsecondes",
            "t = 1,5 µs": "t égale 1,5 microseconde",
            "m = 80 kg": "m égale 80 kilogrammes",
            "E = 1000 J": "E égale 1000 joules",
            "R = 10 kΩ": "R égale 10 kiloohms",
            "f = 5 Hz": "f égale 5 hertz",
            "L = 3 mol": "L égale 3 moles",
            "x = 5 min": "x égale 5 minutes",
            "x = 3 h": "x égale 3 heures",
            "P = 2 kW": "P égale 2 kilowatts",
            "E = 5 MeV": "E égale 5 mégaélectronvolts",
            "l = 2 Å": "l égale 2 ångströms",
            "p = 2 atm": "p égale 2 atmosphères normales",
            "p = 760 mmHg": "p égale 760 millimètres de mercure",
            "a = 3 ly": "a égale 3 années-lumière",
            "p = 1 ppm": "p égale 1 pour cent".replacingOccurrences(of: "pour cent", with: "partie par million"),
            "x = 45°": "x égale 45 degrés",
            "x = 30 deg": "x égale 30 degrés",
            "x = 2 tr": "x égale 2 tours",
            "x = 2 jour": "x égale 2 jours"
        ])
    }

    func testCompoundUnitsPluralizeOnlyTheNumerator() {
        check([
            "a = 7,2 m/s²": "a égale 7,2 mètres par seconde carrée",
            "v = 72 km/h": "v égale 72 kilomètres par heure",
            "v = 5 m/s": "v égale 5 mètres par seconde",
            "v = 1 m/s": "v égale 1 mètre par seconde",
            "F = 5 kg*m/s²": "F égale 5 kilogrammes mètres par seconde carrée",
            "A = 3 m²": "A égale 3 mètres carrés",
            "V = 2 m³": "V égale 2 mètres cubes",
            "A = 1 m²": "A égale 1 mètre carré",
            "rho = 1000 kg/m³": "rho égale 1000 kilogrammes par mètre cube",
            "rho = 7,8 g/cm³": "rho égale 7,8 grammes par centimètre cube",
            "w = 3 rad/s": "w égale 3 radians par seconde",
            "n = 3000 rpm": "n égale 3000 tours par minute",
            "c_p = 4180 J/kg/K": "c_p égale 4180 joules par kilogramme par kelvin".replacingOccurrences(of: "c_p", with: "c indice p"),
            "x = 5 s^-1": "x égale 5 secondes puissance moins 1",
            "x = 2 m^4": "x égale 2 mètres puissance 4"
        ])
    }

    func testQuantitiesInsideLargerExpressions() {
        check([
            "2 m + 3 s": "2 mètres plus 3 secondes",
            "5 m * a": "5 mètres fois a",
            "m * 9,81 m/s²": "m fois 9,81 mètres par seconde carrée",
            "10 m / 2 s": "10 mètres sur 2 secondes",
            "sqrt(2 m²)": "racine carrée de 2 mètres carrés",
            "2 * 3 m": "2 fois 3 mètres"
        ])
    }

    // MARK: Whole lines

    func testEqualityDeclarationAndComparison() {
        check([
            "E = h * c / lambda": "E égale fraction, numérateur : h fois c ; dénominateur : lambda ; fin de fraction",
            "m * a == F": "m fois a comparé à F",
            "2 + 3 = 5": "2 plus 3 égale 5",
            "a = 7,2 m/s²": "a égale 7,2 mètres par seconde carrée"
        ])
    }

    func testConversionArrowIsSpokenAsDisplayedIn() {
        check([
            "v → km/h": "v, affiché en kilomètres par heure",
            "v -> km/h": "v, affiché en kilomètres par heure",
            "E = 5 J → kJ": "E égale 5 joules, affiché en kilojoules",
            "E → kWh": "E, affiché en kilowattheures",
            "t → min": "t, affiché en minutes",
            "x → MeV/c²": "x, affiché en mégaélectronvolts par c carré",
            "x → 1/s": "x, affiché en par seconde",
            "p → atm": "p, affiché en atmosphères normales",
            "m * a → N": "m fois a, affiché en newtons"
        ])
    }

    func testCommentsAreSpokenAsNotes() {
        check([
            "# Chute libre": "note : Chute libre",
            "// Chute libre": "note : Chute libre",
            "## Titre": "note : Titre",
            "g = 9,81 m/s² # pesanteur": "g égale 9,81 mètres par seconde carrée, note : pesanteur",
            "v → km/h # converti": "v, affiché en kilomètres par heure, note : converti",
            "x = 2 // deux": "x égale 2, note : deux"
        ])
    }

    func testTheUnknownIsAnnounced() {
        check([
            "v = ?": "v égale inconnue",
            "v = ? m/s": "v égale inconnue en mètres par seconde",
            "l = ? m # longueur": "l égale inconnue en mètres, note : longueur",
            "t = ? s → min": "t égale inconnue en secondes, affiché en minutes"
        ])
    }

    func testUnparsableLinesFallBackToTheSource() {
        for source in ["", "   ", "2 +", "(", "= 3", "a = b = c", "a → ", "a → b → c", "→ km", "1 + ?", "$",
                       "sin(", "max(1)", "a ==", "x = 2 @", "a\nb"] {
            XCTAssertNil(MathSpeech.description(source), source)
        }
        XCTAssertNil(MathSpeech.description(String(repeating: "a + ", count: 600) + "a"))
        XCTAssertNil(MathSpeech.description(Array(repeating: "(", count: 100).joined() + "a" + Array(repeating: ")", count: 100).joined()))
    }

    func testSpeechAndNotationAgreeOnWhichLinesParse() {
        let sources = ExampleLibrary.all.flatMap { $0.source.components(separatedBy: "\n") }
            + ["2 +", "v = ? m", "a ==", "a → b", "x = 3 → ", "(a", "5!", "20 %", "a = b = c", "√2 m"]
        for source in sources {
            let isComment = LineSyntax(source).content.trimmingCharacters(in: .whitespaces).isEmpty
            if isComment { continue }
            XCTAssertEqual(MathSpeech.description(source) != nil, MathNotation.formula(source) != nil, source)
        }
    }

    func testEveryExampleLineIsSpoken() {
        for example in ExampleLibrary.all {
            for source in example.source.components(separatedBy: "\n")
            where !source.trimmingCharacters(in: .whitespaces).isEmpty && LineSyntax(source).comment == nil {
                let spoken = said(source)
                XCTAssertFalse(spoken.hasPrefix("nil"), "\(example.id): \(source)")
                // No raw operator is left for the screen reader to guess.
                XCTAssertFalse(spoken.contains(where: { "*/^²³→=" .contains($0) }), "\(example.id): \(source) → \(spoken)")
            }
        }
    }

    // MARK: Results

    func testQuantitiesAreSpokenWithTheirUnit() {
        let energy = Self.energy
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 3.010013851e11, dimension: energy)),
                       "3,01001 fois 10 puissance 11 joules")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 1, dimension: energy)), "1 joule")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 1.5, dimension: energy)), "1,5 joule")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: -21.57, dimension: Self.force)), "moins 21,57 newtons")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 3)), "3")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 299_792_458, dimension: Self.speed)),
                       "299792458 mètres par seconde")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 7.2, dimension: Self.acceleration)),
                       "7,2 mètres par seconde carrée")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 50, dimension: Self.frequency)), "50 par seconde")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 2, dimension: .mass)), "2 kilogrammes")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 1e-7)), "1 fois 10 puissance moins 7")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 4, dimension: .temperature)), "4 kelvins")
    }

    func testQuantitiesHonourTheDisplayUnit() {
        let speed = Quantity(value: 5, dimension: Self.speed)
        XCTAssertEqual(QuantityFormatter.spokenString(speed, in: DisplayUnit(symbol: "km/h", scale: 1 / 3.6)), "18 kilomètres par heure")
        XCTAssertEqual(QuantityFormatter.spokenString(speed, in: nil), "5 mètres par seconde")
        let energy = Quantity(value: 7.2e6, dimension: Self.energy)
        XCTAssertEqual(QuantityFormatter.spokenString(energy, in: DisplayUnit(symbol: "kWh", scale: 3.6e6)), "2 kilowattheures")
        XCTAssertEqual(QuantityFormatter.spokenString(energy, in: DisplayUnit(symbol: "MJ", scale: 1e6)), "7,2 mégajoules")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 1.5), in: DisplayUnit(symbol: "°", scale: .pi / 180)), "85,9437 degrés")
        XCTAssertEqual(QuantityFormatter.spokenString(Quantity(value: 0.01), in: DisplayUnit(symbol: "%", scale: 0.01)), "1 pour cent")
        XCTAssertEqual(QuantityFormatter.spokenString(energy, in: DisplayUnit(symbol: "MeV/c²", scale: 1.0)),
                       "7200000 mégaélectronvolts par c carré")
    }

    func testDimensionsAreDescribedInBaseUnits() {
        let (length, mass, time): (EvalCore.Dimension, EvalCore.Dimension, EvalCore.Dimension) = (.length, .mass, .time)
        let none = EvalCore.Dimension.dimensionless
        let cases: [(EvalCore.Dimension, String)] = [
            (none, "sans dimension"),
            (length, "mètre"),
            (length - time, "mètre par seconde"),
            (length - time.scaled(by: 2), "mètre par seconde carrée"),
            (mass + length.scaled(by: 2) - time.scaled(by: 2), "kilogramme mètre carré par seconde carrée"),
            (none - time, "par seconde"),
            (none - time.scaled(by: 2), "par seconde carrée"),
            (mass - length.scaled(by: 3), "kilogramme par mètre cube"),
            (length.scaled(by: 0.5), "mètre puissance 0,5"),
            (EvalCore.Dimension.electricCurrent + time, "seconde ampère"),
            (EvalCore.Dimension.amount - length.scaled(by: 3), "mole par mètre cube"),
            (EvalCore.Dimension.luminousIntensity, "candela"),
            (EvalCore.Dimension.temperature - time.scaled(by: 4), "kelvin par seconde puissance 4")
        ]
        for (dimension, expected) in cases {
            XCTAssertEqual(dimension.spokenDescription, expected, dimension.formatted)
        }
    }

    func testEvaluatedLinesSpeakTheirResultAndDimension() {
        let lines = NotebookEngine.evaluate("""
            m = 80 kg
            v = 5 m/s
            E = 0,5 * m * v²
            E → kJ
            2 m + 3 m
            2 m * 3 m
            4
            # note
            """).lines
        XCTAssertEqual(lines[3].spokenResult, "1 kilojoule")
        XCTAssertEqual(lines[2].spokenResult, "1000 joules")
        XCTAssertEqual(lines[2].spokenDimensionMessage, "Dimension : kilogramme mètre carré par seconde carrée")
        XCTAssertEqual(lines[4].spokenDimensionMessage, "Homogène : mètre")
        XCTAssertEqual(lines[4].spokenResult, "5 mètres")
        XCTAssertEqual(lines[5].spokenResult, "6 mètres carrés")
        XCTAssertEqual(lines[6].spokenResult, "4")
        XCTAssertNil(lines[6].spokenDimensionMessage)
        XCTAssertNil(lines[7].spokenResult)
        XCTAssertNil(lines[7].spokenDimensionMessage)
    }

    func testUnitNamesMatchTheCatalogue() {
        for symbol in ["m", "kg", "s", "A", "K", "mol", "cd", "N", "Pa", "J", "W", "C", "V", "F", "Ω", "S", "Wb", "T", "H",
                       "Hz", "Bq", "min", "h", "L", "bar", "eV", "µm", "ns", "kHz", "GeV"] {
            let name = MathSpeech.unitName(symbol, plural: false).name
            XCTAssertEqual(name, UnitCatalog.lookup(symbol)?.name.lowercased(), symbol)
            XCTAssertFalse(name.contains(where: \.isUppercase), name)
        }
        XCTAssertEqual(MathSpeech.unitName("µs", plural: false).name, "microseconde")
        XCTAssertEqual(MathSpeech.unitName("µs", plural: false).feminine, true)
        XCTAssertEqual(MathSpeech.unitName("wattheure", plural: false).feminine, false)
        XCTAssertEqual(MathSpeech.unitName("Wh", plural: false).feminine, false)
        XCTAssertEqual(MathSpeech.unitName("kcal", plural: false).feminine, true)
        XCTAssertEqual(MathSpeech.unitName("lux", plural: true).name, "lux")
        XCTAssertEqual(MathSpeech.unitName("lx", plural: true).name, "lux")
        XCTAssertEqual(MathSpeech.unitName("S", plural: true).name, "siemens")
        XCTAssertEqual(MathSpeech.unitName("Hz", plural: true).name, "hertz")
        XCTAssertEqual(MathSpeech.unitName("xyz", plural: true).name, "xyz")
    }

    func testLongLinesAndDeepNestingAreBoundedLikeTheNotation() {
        let moderate = Array(repeating: "a", count: 150).joined(separator: " + ")
        XCTAssertNotNil(MathSpeech.description(moderate))
        let deep = Array(repeating: "a", count: 400).joined(separator: " + ")
        XCTAssertNil(MathNotation.formula(deep))
        XCTAssertNil(MathSpeech.description(deep))
        XCTAssertNil(MathSpeech.description(String(repeating: "a", count: 2_001)))
    }

    func testSpokenResultLineNamesTheFormula() {
        XCTAssertEqual(ResultText.spokenLine(source: "E = m * c^2 # énergie", spokenValue: "9 joules"), "E égale 9 joules")
        XCTAssertEqual(ResultText.spokenLine(source: "m * v", spokenValue: "400 kilogrammes"), "m fois v égale 400 kilogrammes")
        XCTAssertEqual(ResultText.spokenLine(source: "", spokenValue: "2"), "2")
    }
}
