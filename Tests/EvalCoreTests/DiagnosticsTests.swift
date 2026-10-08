import XCTest
@testable import EvalCore

final class DiagnosticsTests: XCTestCase {
    private let engine = NotebookEngine()

    func testUndeclaredSymbolResolvedAsUnitIsReported() {
        let evaluation = engine.evaluate("p = 101325 Pa\nV = 24 L\nn = 1 mol\np*V/(n*R*T)")
        XCTAssertEqual(evaluation.lines[3].status, .success)
        XCTAssertEqual(evaluation.symbolUnits.map(\.symbol), ["T"])
        XCTAssertEqual(evaluation.symbolUnits.first?.name, "Tesla")
        XCTAssertEqual(evaluation.constants.map(\.id), ["R"])
    }

    func testSymbolUnitsAreListedOnceInOrderOfFirstUseThroughDeclarations() {
        let evaluation = engine.evaluate("E = m*g*h\nF2 = T + V\nE\nE\nT")
        XCTAssertEqual(evaluation.symbolUnits.map(\.symbol), ["m", "T", "V"])
        XCTAssertEqual(evaluation.constants.map(\.id), ["g", "h"])
    }

    func testSuffixUnitsAreNotReported() {
        for source in ["5 m", "72 km/h", "v = 20 m/s\nv * 2 kg", "3 g/cm³"] {
            XCTAssertTrue(engine.evaluate(source).symbolUnits.isEmpty, source)
        }
    }

    func testPercentAndDegreeNotationAreNotReported() {
        for source in ["35%", "P = 200 W\nP * 15%", "sin(30°)", "θ = 30°\nθ", "x = 30deg\nx", "50 %"] {
            let evaluation = engine.evaluate(source)
            XCTAssertTrue(evaluation.lines.allSatisfy { $0.status != .error }, source)
            XCTAssertTrue(evaluation.symbolUnits.isEmpty, "\(source): \(evaluation.symbolUnits.map(\.symbol))")
        }
    }

    func testDeclaredSymbolIsNotReported() {
        XCTAssertTrue(engine.evaluate("T = 300 K\nT * 2").symbolUnits.isEmpty)
        XCTAssertTrue(engine.evaluate("m = 80 kg\n5 m").symbolUnits.isEmpty)
    }

    func testCompactNumberUnitIsReported() {
        XCTAssertEqual(engine.evaluate("2m").symbolUnits.map(\.symbol), ["m"])
        XCTAssertEqual(engine.evaluate("10N").symbolUnits.map(\.symbol), ["N"])
    }

    func testBareUnitFallbackRemainsUsable() throws {
        let evaluation = engine.evaluate("an\n1 mi")
        XCTAssertEqual(evaluation.lines[0].quantity?.value, 31_557_600)
        XCTAssertEqual(evaluation.symbolUnits.map(\.symbol), ["an"])
    }

    func testOffsetTemperatureExplainsKelvin() {
        let message = "Les températures en °C ou °F ne sont pas prises en charge (unités à décalage). Utilisez le kelvin : 20 °C correspondent à 293,15 K."
        for source in ["20 °C", "20 degC", "68 °F", "x = 5 celsius"] {
            let line = engine.evaluate(source).lines[0]
            XCTAssertEqual(line.status, .error, source)
            XCTAssertEqual(line.message, message, source)
        }
        XCTAssertEqual(engine.evaluate("273,15 K + 20 K").lines[0].status, .success)
    }

    func testUnitPowerTypoSuggestsSuperscript() {
        XCTAssertEqual(engine.evaluate("2 m2").lines[0].message,
                       "« m2 » est inconnu. Pour une puissance d’unité, écrivez m² ou m^2 ; pour une variable, ajoutez une déclaration m2 = ….")
        XCTAssertTrue(engine.evaluate("3 cm3").lines[0].message?.contains("cm²") == true)
        // A declaration stays valid, and a stem that is no unit gets the general message.
        XCTAssertEqual(engine.evaluate("m2 = 3 kg\nm2 * 2").lines[1].quantity?.value, 6)
        XCTAssertTrue(engine.evaluate("x2 + 1").lines[0].message?.hasPrefix("« x2 » n’est ni une variable déclarée") == true)
    }

    func testGeneralUnknownSymbolMessage() {
        XCTAssertEqual(engine.evaluate("banane * 2").lines[0].message,
                       "« banane » n’est ni une variable déclarée, ni une constante, ni une unité connue. Ajoutez une déclaration, par exemple banane = 7,2 m, ou consultez Références › Unités.")
    }

    func testDegreeLikeLiteralInSineAddsRadianNote() {
        let note = "Angle interprété en radians. Pour des degrés, écrivez sin(30 deg)."
        let line = engine.evaluate("sin(30)").lines[0]
        XCTAssertEqual(line.status, .success)
        XCTAssertEqual(line.message, note)
        XCTAssertEqual(line.quantity?.value ?? 0, -0.9880316240928618, accuracy: 1e-15)
        XCTAssertEqual(engine.evaluate("cos(90)").lines[0].message, "Angle interprété en radians. Pour des degrés, écrivez cos(90 deg).")
        XCTAssertEqual(engine.evaluate("x = tan(45)\nx").lines[0].message?.hasPrefix("Angle interprété"), true)
        XCTAssertNil(engine.evaluate("x = tan(45)\nx").lines[1].message)
        for source in ["sin(0,5)", "sin(30 deg)", "sin(pi/6)", "sin(31)", "sin(10)", "sin(375)", "cos(2 rad)", "sqrt(30)", "a = 30\nsin(a)"] {
            XCTAssertNil(engine.evaluate(source).lines.last?.message, source)
        }
    }

    func testRadianNoteDoesNotReplaceTheEqualityMessage() {
        XCTAssertEqual(engine.evaluate("sin(30) == sin(30)").lines[0].message, "Égalité vérifiée.")
    }
}
