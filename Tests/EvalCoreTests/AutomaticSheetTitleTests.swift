import Foundation
import XCTest
@testable import EvalCore

final class AutomaticSheetTitleTests: XCTestCase {
    private let physics = "m = 80 kg\nh = 12 m\nv = sqrt(2 * g * h) =\nE = m * g * h ="

    // MARK: Eligibility

    func testAnUntitledSheetWithContentIsEligible() {
        XCTAssertTrue(AutomaticSheetTitle.isEligible(SheetRecord(source: physics)))
        XCTAssertTrue(AutomaticSheetTitle.isEligible(SheetRecord(customTitle: "  ", source: physics)))
    }

    func testANamedSheetIsNotEligible() {
        XCTAssertFalse(AutomaticSheetTitle.isEligible(SheetRecord(customTitle: "Chute", source: physics)))
        XCTAssertFalse(AutomaticSheetTitle.isEligible(SheetRecord(source: "# Chute libre\n" + physics)))
        XCTAssertFalse(AutomaticSheetTitle.isEligible(SheetRecord(source: physics + "\n// Hauteur d’un immeuble")))
    }

    func testASheetIsOfferedATitleOnlyOnce() {
        XCTAssertFalse(AutomaticSheetTitle.isEligible(SheetRecord(automaticTitleAttempted: true, source: physics)))
    }

    func testASheetWithTooLittleContentIsNotEligible() {
        for source in ["", "   \n\n", "x = 2", "1 + 1 =", "1234567890 + 42 ="] {
            XCTAssertFalse(AutomaticSheetTitle.isEligible(SheetRecord(source: source)), source)
        }
        XCTAssertTrue(AutomaticSheetTitle.hasMeaningfulContent("m = 80 kg\nv = 5 m/s"))
    }

    func testTheAttemptIsSavedAndOlderFilesDecodeWithoutIt() throws {
        let attempted = SheetRecord(automaticTitleAttempted: true, source: physics)
        let decoded = try JSONDecoder().decode(SheetRecord.self, from: JSONEncoder().encode(attempted))
        XCTAssertTrue(decoded.automaticTitleAttempted)

        let untouched = try JSONEncoder().encode(SheetRecord(source: physics))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: untouched) as? [String: Any])
        XCTAssertNil(json["automaticTitleAttempted"], "files stay as they were until an attempt")
        XCTAssertFalse(try JSONDecoder().decode(SheetRecord.self, from: untouched).automaticTitleAttempted)
    }

    // MARK: Content

    func testContentKeepsWholeNonBlankLinesUpToTheLimit() {
        XCTAssertEqual(AutomaticSheetTitle.content(for: "  m = 80 kg \n\n\nv = 5 m/s\n"), "m = 80 kg\nv = 5 m/s")
        let long = Array(repeating: "E = 0,5 * m * v^2 =", count: 200).joined(separator: "\n")
        let content = AutomaticSheetTitle.content(for: long)
        XCTAssertLessThanOrEqual(content.count, AutomaticSheetTitle.maximumContentLength)
        XCTAssertTrue(content.split(separator: "\n").allSatisfy { $0 == "E = 0,5 * m * v^2 =" })
        let oneLine = String(repeating: "a", count: 3000)
        XCTAssertEqual(AutomaticSheetTitle.content(for: oneLine).count, AutomaticSheetTitle.maximumContentLength)
    }

    // MARK: Sanitizing

    func testSanitizingRemovesQuotesAndTheFinalPeriod() {
        XCTAssertEqual(AutomaticSheetTitle.sanitized("  Chute libre  "), "Chute libre")
        XCTAssertEqual(AutomaticSheetTitle.sanitized("« Chute libre »."), "Chute libre")
        XCTAssertEqual(AutomaticSheetTitle.sanitized("\"Énergie d’un photon\""), "Énergie d’un photon")
        XCTAssertEqual(AutomaticSheetTitle.sanitized("“Loi d’Ohm”…"), "Loi d’Ohm")
        XCTAssertEqual(AutomaticSheetTitle.sanitized("'Pendule simple'"), "Pendule simple")
        XCTAssertEqual(AutomaticSheetTitle.sanitized("Énergie d’un photon !"), "Énergie d’un photon")
    }

    func testSanitizingKeepsTheFirstLineWithoutMarker() {
        XCTAssertEqual(AutomaticSheetTitle.sanitized("\n# Titre : chute   libre\nUne feuille sur la chute."), "Chute libre")
        XCTAssertEqual(AutomaticSheetTitle.sanitized("Tir\u{00A0}parabolique"), "Tir parabolique")
    }

    func testSanitizingShortensBetweenWords() throws {
        let title = try XCTUnwrap(AutomaticSheetTitle.sanitized(
            "Énergie cinétique et potentielle d’un skieur sur une piste verglacée"))
        XCTAssertLessThanOrEqual(title.count, AutomaticSheetTitle.maximumLength)
        XCTAssertEqual(title, "Énergie cinétique et potentielle d’un")
        let word = try XCTUnwrap(AutomaticSheetTitle.sanitized(String(repeating: "x", count: 60)))
        XCTAssertEqual(word.count, AutomaticSheetTitle.maximumLength)
    }

    func testSanitizingRejectsEmptyOrUntitledProposals() {
        for proposal in ["", "  \n ", "« »", "...", "42", "Nouvelle feuille", "« nouvelle feuille »."] {
            XCTAssertNil(AutomaticSheetTitle.sanitized(proposal), proposal)
        }
    }
}
