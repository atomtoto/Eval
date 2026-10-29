import Testing
@testable import EvalBridge

@Suite struct SheetEvaluatorTests {
    @Test func kineticEnergyShowsItsValue() {
        let lines = SheetEvaluator().evaluate("E = 0,5 * m * v²\nm = 80 kg\nv = 5 m/s\nE =")
        #expect(lines.count == 4)
        #expect(lines[3].value == "1000 J")
        #expect(lines[3].status == "success")
    }

    @Test func equalityShowsItsVerdictAndNoValue() {
        let lines = SheetEvaluator().evaluate("1 km = 1000 m → cm\n1 km = 2 m → cm")
        #expect(lines.allSatisfy { $0.kind == "equation" && $0.value == nil })
        #expect(lines[0].status == "success")
        #expect(lines[1].status == "error")
        #expect(lines[1].message != nil)
    }
}
