import XCTest
@testable import EvalCore

final class RecognizedMathTests: XCTestCase {
    private typealias Box = RecognizedMath.Box
    private typealias Fragment = RecognizedMath.Fragment

    /// Characters of equal width on one baseline, with some of them raised and smaller.
    private func fragment(_ text: String, x: Double = 0.1, y: Double = 0.5, raised: Set<Int> = []) -> Fragment {
        let width = 0.03, height = 0.06
        let boxes = text.indices.enumerated().map { offset, _ -> Box in
            raised.contains(offset)
                ? Box(x: x + Double(offset) * width, y: y - height * 0.3, width: width * 0.7, height: height * 0.5)
                : Box(x: x + Double(offset) * width, y: y, width: width, height: height)
        }
        let box = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        return Fragment(text: text, box: box, characterBoxes: boxes)
    }

    func testRaisedDigitsBecomeExponents() {
        XCTAssertEqual(RecognizedMath.lines(from: [fragment("3x2+2x-3=0", raised: [2])]), ["3x²+2x-3=0"])
        XCTAssertEqual(RecognizedMath.lines(from: [fragment("E=mc2", raised: [4])]), ["E=mc²"])
        XCTAssertEqual(RecognizedMath.lines(from: [fragment("x-12", raised: [1, 2, 3])]), ["x⁻¹²"])
        // Digits on the line stay digits.
        XCTAssertEqual(RecognizedMath.lines(from: [fragment("x2+10")]), ["x2+10"])
    }

    func testFragmentsJoinIntoLinesTopToBottom() {
        let lines = RecognizedMath.lines(from: [
            Fragment(text: "x =", box: Box(x: 0.1, y: 0.4, width: 0.1, height: 0.05)),
            Fragment(text: "m = 80 kg", box: Box(x: 0.1, y: 0.1, width: 0.3, height: 0.05)),
            Fragment(text: "v = 5 m/s", box: Box(x: 0.1, y: 0.2, width: 0.3, height: 0.05)),
            Fragment(text: "+ 1", box: Box(x: 0.6, y: 0.21, width: 0.1, height: 0.05)),
        ])
        XCTAssertEqual(lines, ["m = 80 kg", "v = 5 m/s + 1", "x ="])
    }

    func testABarBetweenTwoFragmentsIsAFraction() {
        let lines = RecognizedMath.lines(from: [
            Fragment(text: "E =", box: Box(x: 0.05, y: 0.47, width: 0.1, height: 0.06)),
            Fragment(text: "m v2", box: Box(x: 0.22, y: 0.38, width: 0.12, height: 0.06)),
            Fragment(text: "——", box: Box(x: 0.2, y: 0.49, width: 0.16, height: 0.01)),
            Fragment(text: "2", box: Box(x: 0.26, y: 0.52, width: 0.03, height: 0.06)),
        ])
        XCTAssertEqual(lines, ["E = (m v2)/2"])
    }

    func testLookAlikesAreSpelledForTheSheet() {
        XCTAssertEqual(RecognizedMath.normalized("F = m − a"), "F = m - a")
        XCTAssertEqual(RecognizedMath.normalized("x**2 = 1O5"), "x^2 = 105")
        XCTAssertEqual(RecognizedMath.normalized("$E = \\frac{1}{2} m v^{2}$"), "E = 1/2 * m v^2")
        XCTAssertEqual(RecognizedMath.normalized("\\frac{a+b}{\\sqrt{2}}"), "(a+b)/√2")
        XCTAssertEqual(RecognizedMath.normalized("\\sqrt{x+1} \\cdot \\pi"), "√(x+1) * π")
        XCTAssertEqual(RecognizedMath.normalized("\\frac{1}{2} g t^2"), "1/2 * g t^2")
        // Outside LaTeX, the sheet's own reading applies: 2 m is two metres.
        XCTAssertEqual(RecognizedMath.normalized("d = 2 m"), "d = 2 m")
        XCTAssertEqual(RecognizedMath.normalized("```x = 2```"), "x = 2")
    }

    func testBrokenLinesAreJoined() {
        XCTAssertEqual(RecognizedMath.joiningBrokenLines(["2 x =", "4"]), ["2 x = 4"])
        XCTAssertEqual(RecognizedMath.joiningBrokenLines(["3x^2", "+ 2x", "- 3", "= 0"]), ["3x^2 + 2x - 3 = 0"])
        // A request followed by another equation stays apart, and so do notes.
        XCTAssertEqual(RecognizedMath.joiningBrokenLines(["x =", "2x + 1 = 5"]), ["x =", "2x + 1 = 5"])
        XCTAssertEqual(RecognizedMath.joiningBrokenLines(["# Titre", "- note"]), ["# Titre", "- note"])
        XCTAssertEqual(RecognizedMath.joiningBrokenLines(["m = 80 kg", "v = 5 m/s"]), ["m = 80 kg", "v = 5 m/s"])
    }

    func testReadingsAgreeWhenTheyShareTheirCharacters() {
        XCTAssertEqual(RecognizedMath.agreement(["3x^2 + 2x - 3 = 0"], ["3x²+2x-3=0"]), 1)
        XCTAssertGreaterThan(RecognizedMath.agreement(["2x = 4"], ["2×=4"]), 0.6)
        // An invented sheet shares almost nothing with what was written.
        XCTAssertLessThan(RecognizedMath.agreement(["v_0 = (1/2) * g * h", "h = (v_0^2) / (2 * g)", "# Chute libre"],
                                                   ["2x=4"]), 0.2)
    }

    func testDeclaredNamesAfterANumberAreMultiplied() {
        let lines = RecognizedMath.clarifyingProducts(["m = 80 kg", "1000 J = 0,5 m v^2", "v ="], declared: [])
        XCTAssertEqual(lines, ["m = 80 kg", "1000 J = 0,5 * m v^2", "v ="])
        // A unit stays a unit, and the sheet's own names count.
        XCTAssertEqual(RecognizedMath.clarifyingProducts(["d = 2 m", "F = 2 a"], declared: ["a"]), ["d = 2 m", "F = 2 * a"])
        let evaluation = NotebookEngine.evaluate(lines.joined(separator: "\n"))
        XCTAssertEqual(evaluation.lines[2].formattedValue, "−5 m·s⁻¹ ; 5 m·s⁻¹")
    }

    func testRecognizedLinesEvaluate() {
        let lines = RecognizedMath.lines(from: [fragment("3x2+2x-3=0", raised: [2]), fragment("x=", y: 0.7)])
        let evaluation = NotebookEngine.evaluate(lines.joined(separator: "\n"))
        XCTAssertEqual(evaluation.lines[1].formattedValue, "(−1 ± √10)/3 ≈ 0,720759 ; −1,38743")
    }
}
