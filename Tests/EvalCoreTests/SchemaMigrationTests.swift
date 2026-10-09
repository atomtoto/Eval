import Foundation
import XCTest
@testable import EvalCore

/// Schema 2 shows a result because its line asks for it; schema 1 sheets chose
/// their results, and decoding one writes the choices into the text.
final class SchemaMigrationTests: XCTestCase {
    /// A sheet as version 1 of the app saved it.
    private func schema1JSON(source: String, selected: Set<Int>) throws -> Data {
        let selection = ResultSelection(source: source, initiallySelectedLineIDs: selected)
        let record = SheetRecord(source: source, resultSelection: selection, schemaVersion: 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object["schemaVersion"] = 1
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testChosenExpressionsAndDerivedDeclarationsGainARequest() throws {
        let source = """
            # Énergie
            m = 80 kg
            v = 5 m/s
            E = 0,5 * m * v²
            F = m * 9,81 m/s²
            m * v
            E → kWh
            """
        let data = try schema1JSON(source: source, selected: [3, 5, 6])
        let record = try JSONDecoder().decode(SheetRecord.self, from: data)
        XCTAssertEqual(record.schemaVersion, 2)
        XCTAssertEqual(record.source, """
            # Énergie
            m = 80 kg
            v = 5 m/s
            E = 0,5 * m * v² =
            F = m * 9,81 m/s²
            m * v =
            E → kWh
            """)
        // The shown results are the requested ones.
        let shown = NotebookEngine.evaluate(record.source).lines.filter(\.requestsValue).map(\.id)
        XCTAssertEqual(shown, [3, 5, 6])
        XCTAssertEqual(record.resultSelection.entries.map(\.source), record.source.components(separatedBy: "\n"))
    }

    func testEqualitiesUnknownsArrowsLiteralsAndNotesAreUntouched() throws {
        let source = "# Titre\nF = 14,4 N\nm = 2 kg\nm * 7,2 m/s² == F\nw = ? m/s\nF → kN\nm = 3 kg\nx +"
        let data = try schema1JSON(source: source, selected: Set(0..<8))
        let record = try JSONDecoder().decode(SheetRecord.self, from: data)
        // Only the broken expression changes: it was an expression the user had chosen.
        XCTAssertEqual(record.source, "# Titre\nF = 14,4 N\nm = 2 kg\nm * 7,2 m/s² == F\nw = ? m/s\nF → kN\nm = 3 kg\nx + =")
    }

    func testCommentsStayAfterTheRequestAndCanonicalFormIsKept() throws {
        let source = "E = P * 2 h  # énergie\nE → kWh  // en kWh\nP = 2 kW"
        let data = try schema1JSON(source: source, selected: [0, 1])
        let record = try JSONDecoder().decode(SheetRecord.self, from: data)
        XCTAssertEqual(record.source, "E = P * 2 h =  # énergie\nE → kWh  // en kWh\nP = 2 kW")
        let canonical = LineSyntax("E = P * 2 h").replacingConversion("kWh")
        XCTAssertEqual(LineSyntax(canonical).addingResultRequest(), "E = P * 2 h → kWh =")
    }

    func testMigrationKeepsIdentitiesRulersAndIsSelected() throws {
        let source = "m = 80 kg\nE = 0,5 * m * 4 m²/s²"
        let selection = ResultSelection(source: source, initiallySelectedLineIDs: [1])
        let massID = selection.entries[0].id, energyID = selection.entries[1].id
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 160, step: 1))
        let old = SheetRecord(source: source, resultSelection: selection, adjustmentRanges: [massID: range],
                              manualStepIDs: [massID], schemaVersion: 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object["schemaVersion"] = 1
        let record = try JSONDecoder().decode(SheetRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(record.resultSelection.entries.map(\.id), [massID, energyID])
        XCTAssertEqual(record.adjustmentRanges[massID], range)
        XCTAssertEqual(record.manualStepIDs, [massID])
        // `isSelected` stays decodable.
        XCTAssertEqual(record.resultSelection.entries.map(\.isSelected), [false, true])
    }

    func testSchema1WithoutASavedSelectionUsesTheOldDefaults() throws {
        let record = SheetRecord(source: "x = 2 m\nx * 3\nx → km\nx == 2 m", schemaVersion: 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object["schemaVersion"] = 1
        object["resultSelection"] = nil
        let decoded = try JSONDecoder().decode(SheetRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.source, "x = 2 m\nx * 3 =\nx → km\nx == 2 m")
    }

    func testMissingSchemaVersionCountsAsSchema1() throws {
        let data = try schema1JSON(source: "a = 2\na * 3", selected: [1])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = nil
        let decoded = try JSONDecoder().decode(SheetRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.source, "a = 2\na * 3 =")
        XCTAssertEqual(decoded.schemaVersion, 2)
    }

    func testSchema2IsNotMigratedAgain() throws {
        let source = "a = 2\na * 3"
        let selection = ResultSelection(source: source, initiallySelectedLineIDs: [1])
        let record = SheetRecord(source: source, resultSelection: selection)
        let decoded = try JSONDecoder().decode(SheetRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.source, source)
        XCTAssertEqual(decoded, record)
    }

    func testMigratedRecordRoundTripsAndKeepsItsValues() throws {
        let data = try schema1JSON(source: "m = 3 kg\nv = 2 m/s\nE = 0,5 * m * v²", selected: [2])
        let record = try JSONDecoder().decode(SheetRecord.self, from: data)
        let again = try JSONDecoder().decode(SheetRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(again, record)
        XCTAssertEqual(record.resultPreview(), "E = 6 J")
    }

    func testRepositoryLoadsSchema1Sheets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaMigrationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try schema1JSON(source: "a = 2\na * 3", selected: [1])
        let id = try JSONDecoder().decode(SheetRecord.self, from: data).id
        try data.write(to: directory.appendingPathComponent("\(id.uuidString).json"))
        let loaded = SheetRepository(directory: directory).loadAll()
        XCTAssertEqual(loaded.map(\.source), ["a = 2\na * 3 ="])
    }
}

/// The adjustable declaration exposes its number and its value is touchable in the notation.
final class AdjustableValueTests: XCTestCase {
    func testLiteralRangeCoversTheNumberWithItsSign() throws {
        for (source, literal) in [("m = 80 kg", "80"), ("v = −5,5 m/s # note", "−5,5"), ("T = 1,2e3 K", "1,2e3"),
                                  ("x = - 3", "- 3"), ("m = 80 kg =", "80"), ("v = 5 m/s → km/h =", "5")] {
            let variable = try XCTUnwrap(AdjustableVariable(source: source), source)
            XCTAssertEqual(String(source[variable.literalRange]), literal, source)
        }
    }

    func testALiteralDeclarationWithARequestStaysAdjustable() throws {
        let variable = try XCTUnwrap(AdjustableVariable(source: "m = 80 kg =  # masse"))
        XCTAssertEqual(variable.value, 80)
        XCTAssertEqual(variable.unit, "kg")
        XCTAssertEqual(variable.source(replacingValue: 81), "m = 81 kg =  # masse")
        let converted = try XCTUnwrap(AdjustableVariable(source: "v = 5 m/s → km/h ="))
        XCTAssertEqual(converted.source(replacingValue: 6), "v = 6 m/s → km/h =")
    }

    func testOnlyAdjustableDeclarationsWrapTheirValue() throws {
        XCTAssertEqual(MathNotation.formula("m = 80 kg"),
                       .row([.atom("m"), .atom(" = "), .value(try XCTUnwrap(MathNotation.formula("80 kg")))]))
        XCTAssertEqual(MathNotation.formula("m = 80 kg =")?.valueContent(), MathNotation.formula("80 kg"))
        XCTAssertEqual(MathNotation.formula("v = 5 m/s → km/h")?.valueContent(), MathNotation.formula("5 m/s"))
        for source in ["E = 0,5 * m * v²", "E = 3 * 4", "m * v", "x == 2", "v = ? m/s", "a =", "n = m"] {
            XCTAssertNil(MathNotation.formula(source)?.valueContent(), source)
        }
    }

    func testValueCaseDrawsLikeItsContent() throws {
        let formula = try XCTUnwrap(MathNotation.formula("g = 9,81 m/s²"))
        XCTAssertEqual(formula.valueContent()?.plainText, MathNotation.formula("9,81 m/s²")?.plainText)
        XCTAssertEqual(MathNotation.formula("m = 80 kg")?.plainText, "m = 80 kg")
    }
}

/// Test-only helpers to inspect a formula.
private extension MathFormula {
    /// The content of the first `.value` node of a row.
    func valueContent() -> MathFormula? {
        guard case .row(let children) = self else { return nil }
        for child in children { if case .value(let inner) = child { return inner } }
        return nil
    }

    var plainText: String {
        switch self {
        case .atom(let text): return text
        case .row(let children): return children.map(\.plainText).joined()
        case .fraction(let n, let d): return n.plainText + "/" + d.plainText
        case .power(let b, let e): return b.plainText + "^" + e.plainText
        case .radical(let r): return "√(" + r.plainText + ")"
        case .root(let i, let r): return i.plainText + "√(" + r.plainText + ")"
        case .parentheses(let p): return "(" + p.plainText + ")"
        case .value(let v): return v.plainText
        }
    }
}

/// The number of significant digits is a runtime setting.
final class SignificantDigitsTests: XCTestCase {
    override func tearDown() {
        QuantityFormatter.significantDigits = QuantityFormatter.defaultDigits
        super.tearDown()
    }

    func testDefaultsToSixAndKeepsPreciseDigits() {
        XCTAssertEqual(QuantityFormatter.significantDigits, 6)
        XCTAssertEqual(QuantityFormatter.preciseDigits, 10)
        XCTAssertEqual(QuantityFormatter.number(1.0 / 3.0), "0,333333")
    }

    func testChangingTheDigitsChangesEveryDefaultFormatting() {
        QuantityFormatter.significantDigits = 3
        XCTAssertEqual(QuantityFormatter.significantDigits, 3)
        XCTAssertEqual(QuantityFormatter.number(1.0 / 3.0), "0,333")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: 2.0 / 3.0, dimension: .dimensionless)), "0,667")
        XCTAssertEqual(NotebookEngine.evaluate("1 / 3 =").lines[0].formattedValue, "0,333")
        QuantityFormatter.significantDigits = 10
        XCTAssertEqual(NotebookEngine.evaluate("1 / 3 =").lines[0].formattedValue, "0,3333333333")
        XCTAssertEqual(QuantityFormatter.number(1.0 / 3.0, significantDigits: 4), "0,3333", "an explicit count wins")
        XCTAssertEqual(MathSpeech.description("a ="), "a égale")
    }

    func testTheSettingIsClamped() {
        QuantityFormatter.significantDigits = 1
        XCTAssertEqual(QuantityFormatter.significantDigits, 3)
        QuantityFormatter.significantDigits = 99
        XCTAssertEqual(QuantityFormatter.significantDigits, 12)
        QuantityFormatter.significantDigits = -4
        XCTAssertEqual(QuantityFormatter.significantDigits, 3)
    }

    func testTheSettingIsSafeFromSeveralThreads() {
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            QuantityFormatter.significantDigits = 3 + index % 10
            XCTAssertTrue((3...12).contains(QuantityFormatter.significantDigits))
            _ = QuantityFormatter.number(Double(index) / 7)
        }
    }
}
