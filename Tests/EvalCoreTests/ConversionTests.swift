import XCTest
@testable import EvalCore

final class ConversionTests: XCTestCase {
    /// The displayed text of the first line, or its error message.
    private func shown(_ source: String, line index: Int = 0) -> String {
        let line = NotebookEngine.evaluate(source).lines[index]
        guard line.status == .success, let quantity = line.quantity else { return line.message ?? "?" }
        return QuantityFormatter.string(quantity, in: line.displayUnit)
    }

    func testConversionArrowDisplaysRequestedUnit() {
        XCTAssertEqual(shown("v = 20 m/s → km/h"), "72 km/h")
        XCTAssertEqual(shown("v = 20 m/s -> km/h"), "72 km/h")
        XCTAssertEqual(shown("m = 80 kg\nv = 5 m/s\nE = 0,5*m*v² -> kJ", line: 2), "1 kJ")
        XCTAssertEqual(shown("m_e*c^2 -> MeV"), "0,510999 MeV")
        XCTAssertEqual(shown("938,272 MeV/c² -> kg"), "1,67262 × 10⁻²⁷ kg")
        XCTAssertEqual(shown("asin(0,5) → °"), "30°")
        XCTAssertEqual(shown("asin(0,5) → deg"), "30 deg")
        XCTAssertEqual(shown("0,35 -> %"), "35 %")
        XCTAssertEqual(shown("3000 rpm -> rad/s"), "314,159 rad/s")
        XCTAssertEqual(shown("1 pc -> ly"), "3,26156 ly")
        XCTAssertEqual(shown("2 h -> min"), "120 min")
        XCTAssertEqual(shown("1 kg*m/s² -> N"), "1 N")
        XCTAssertEqual(shown("2 N m -> J"), "2 J")
        XCTAssertEqual(shown("4 Hz -> 1/s"), "4 1/s")
    }

    func testConversionKeepsTheVariableInSI() throws {
        let evaluation = NotebookEngine.evaluate("v = 72 km/h -> m/s\nw = v * 2\nw -> km/h")
        XCTAssertEqual(evaluation.lines[0].quantity?.value ?? 0, 20, accuracy: 1e-12)
        XCTAssertEqual(evaluation.lines[0].displayUnit?.symbol, "m/s")
        XCTAssertEqual(evaluation.lines[1].quantity?.value ?? 0, 40, accuracy: 1e-12)
        XCTAssertNil(evaluation.lines[1].displayUnit)
        XCTAssertEqual(shown("v = 72 km/h -> m/s\nw = v * 2\nw -> km/h", line: 2), "144 km/h")
        XCTAssertEqual(evaluation.variables.first { $0.name == "v" }?.quantity.value ?? 0, 20, accuracy: 1e-12)
    }

    func testConversionAppliesToComparisons() {
        let evaluation = NotebookEngine.evaluate("1 kWh == 3600 kJ -> kJ\n1 kWh == 3 MJ -> kJ")
        XCTAssertEqual(evaluation.lines[0].status, .success)
        XCTAssertEqual(evaluation.lines[0].displayUnit?.symbol, "kJ")
        XCTAssertEqual(evaluation.lines[1].status, .error)
        XCTAssertEqual(evaluation.lines[1].message, "Égalité non vérifiée : 3600 kJ ≠ 3000 kJ.")
    }

    func testConversionRejectsIncompatibleDimension() {
        XCTAssertEqual(shown("2 m -> s"), "Conversion impossible : le résultat a pour dimension m, alors que s a pour dimension s.")
        XCTAssertEqual(shown("3 -> km"), "Conversion impossible : le résultat a pour dimension 1, alors que km a pour dimension m.")
        XCTAssertEqual(shown("2 kg -> m/s"), "Conversion impossible : le résultat a pour dimension kg, alors que m/s a pour dimension m·s⁻¹.")
    }

    func testConversionErrorDoesNotBreakDependents() {
        let evaluation = NotebookEngine.evaluate("x = 2 m -> s\ny = x * 2\ny")
        XCTAssertEqual(evaluation.lines[0].status, .error)
        XCTAssertEqual(evaluation.lines[0].kind, .definition)
        XCTAssertNil(evaluation.lines[0].quantity)
        XCTAssertEqual(evaluation.lines[1].status, .success)
        XCTAssertEqual(evaluation.lines[1].quantity?.value, 4)
        XCTAssertEqual(evaluation.lines[2].quantity?.value, 4)
    }

    func testConversionTargetResolvesUnitsBeforeVariables() {
        XCTAssertEqual(shown("m = 80 kg\n5 m -> m", line: 1), "5 m")
        XCTAssertEqual(shown("h = 3 s\n2 h -> h", line: 1), "2 h")
        XCTAssertEqual(shown("g = 3\n2 kg -> g", line: 1), "2000 g")
        XCTAssertEqual(shown("2 kg -> g"), "2000 g")
    }

    func testConversionTargetAllowsCatalogConstants() {
        XCTAssertEqual(shown("1 au -> km"), "149597871 km")
        XCTAssertEqual(shown("c -> km/s"), "299792 km/s")
        XCTAssertEqual(shown("1,5 au -> au"), "1,5 au")
    }

    func testConversionRejectsArithmeticAndTemperatureOffsets() {
        let rule = "Après →, indiquez seulement une unité, par exemple km/h, kWh ou MeV/c²."
        for source in ["2 m -> 1000 m", "2 m -> m + m", "2 m -> -m", "2 m -> sqrt(m)", "2 m -> 2 m"] {
            XCTAssertEqual(shown(source), rule, source)
        }
        XCTAssertTrue(shown("20 K -> °C").hasPrefix("Les températures en °C ou °F"))
        XCTAssertTrue(shown("20 K -> degF").hasPrefix("Les températures en °C ou °F"))
        XCTAssertEqual(shown("2 m -> foo"), "« foo » n’est pas une unité reconnue pour l’affichage après →.")
    }

    func testConversionStructuralMessages() {
        XCTAssertEqual(shown("2 m ->"), "Indiquez l’unité d’affichage après →, par exemple → km/h.")
        XCTAssertEqual(shown("2 m → # km"), "Indiquez l’unité d’affichage après →, par exemple → km/h.")
        XCTAssertEqual(shown("-> km"), "Il manque l’expression à convertir avant →.")
        XCTAssertEqual(shown("2 m -> km -> m"), "Une seule conversion → par ligne.")
        XCTAssertEqual(shown("2 m # -> km"), "2 m")
    }

    func testKeywordEnInSuggestsArrow() {
        XCTAssertEqual(shown("E = 2 J\nE in kJ", line: 1),
                       "« in » n’est pas un mot-clé. Pour afficher un résultat dans une autre unité, écrivez par exemple E -> kJ ou E → kJ.")
        XCTAssertTrue(shown("E = 2 J\nE en kJ", line: 1).hasPrefix("« en » n’est pas un mot-clé."))
    }

    func testConversionDoesNotChangeUnitFreeLines() {
        let evaluation = NotebookEngine.evaluate("2 + 3\n# note -> km")
        XCTAssertNil(evaluation.lines[0].displayUnit)
        XCTAssertEqual(evaluation.lines[1].kind, .comment)
    }

    func testDisplaySuggestionsFollowTheDimension() {
        let speed = UnitCatalog.displaySuggestions(compatibleWith: EvalCore.Dimension(length: 1, time: -1))
        XCTAssertEqual(speed.prefix(2), ["km/h", "m/s"])
        let energy = UnitCatalog.displaySuggestions(compatibleWith: EvalCore.Dimension(length: 2, mass: 1, time: -2))
        for symbol in ["kWh", "kJ", "MeV", "kcal"] { XCTAssertTrue(energy.contains(symbol), symbol) }
        XCTAssertFalse(energy.contains("km/h"))
        let rate = UnitCatalog.displaySuggestions(compatibleWith: .dimensionless - .time)
        for symbol in ["Hz", "rad/s", "tr/min"] { XCTAssertTrue(rate.contains(symbol), symbol) }
        let plain = UnitCatalog.displaySuggestions(compatibleWith: .dimensionless)
        XCTAssertTrue(plain.contains("%") && plain.contains("deg"))
        XCTAssertTrue(UnitCatalog.displaySuggestions(compatibleWith: EvalCore.Dimension(length: 7)).isEmpty)
        // Every suggestion is a valid target for a quantity of its own dimension.
        typealias Dim = EvalCore.Dimension
        let dimensions: [Dim] = [.length, .mass, .time, EvalCore.Dimension(length: 1, time: -1), .dimensionless,
                                       EvalCore.Dimension(length: 2, mass: 1, time: -2), .dimensionless - .time]
        for dimension in dimensions {
            for symbol in UnitCatalog.displaySuggestions(compatibleWith: dimension) {
                let line = NotebookEngine.evaluate("1 \(symbol) -> \(symbol)").lines[0]
                XCTAssertEqual(line.status, LineStatus.success, "\(symbol): \(line.message ?? "")")
            }
        }
    }

    func testArrowSymbolIsShownAsTypedWithMiddleDot() {
        let line = NotebookEngine.evaluate("3 kg*m/s² -> kg*m/s²").lines[0]
        XCTAssertEqual(line.displayUnit?.symbol, "kg·m/s²")
        XCTAssertEqual(shown("3 kg*m/s² -> kg*m/s²"), "3 kg·m/s²")
    }

    func testHugeConversionOverflowIsReported() {
        XCTAssertEqual(shown("1e300 m -> pm"), "Le résultat converti dépasse la plage numérique.")
    }

    func testRadiansAndTurnsAreDimensionlessSoHertzIsNotRevolutionsPerSecond() {
        XCTAssertEqual(shown("50 Hz -> tr/min"), "477,465 tr/min")
        XCTAssertEqual(shown("3000 rpm -> rad/s"), "314,159 rad/s")
    }
}
