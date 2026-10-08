import XCTest
@testable import EvalCore

final class VariableSweepTests: XCTestCase {
    private let projectile = """
        v0 = 20 m/s
        theta = 45 deg
        portee = v0² * sin(2 * theta) / g
        portee
        """

    private func range(_ lower: Double, _ upper: Double, _ step: Double = 1) throws -> VariableAdjustmentRange {
        try XCTUnwrap(VariableAdjustmentRange(lowerBound: lower, upperBound: upper, step: step))
    }

    func testSamplesAreEvenlySpacedInTheEnteredUnit() throws {
        let points = VariableSweep.sample(source: "v = 5 km/h\nE = 0,5 * 80 kg * v²\nE", variableLineIndex: 0,
                                          resultLineIndex: 2, range: try range(0, 10, 1), count: 11)
        XCTAssertEqual(points.map(\.x), (0...10).map(Double.init))
        XCTAssertEqual(points.map(\.index), Array(0...10))
        // 40 · (v / 3,6)² in joules, v in km/h.
        XCTAssertEqual(points[10].y, 40 * Foundation.pow(10 / 3.6, 2), accuracy: 1e-9)
        XCTAssertEqual(points[0].y, 0)
    }

    func testResultsUseTheDisplayUnitOfTheLine() throws {
        let source = "v = 5 m/s\nE = 0,5 * 80 kg * v²\nE → kJ"
        let points = VariableSweep.sample(source: source, variableLineIndex: 0, resultLineIndex: 2,
                                          range: try range(0, 10, 1), count: 3)
        XCTAssertEqual(points.map(\.y), [0, 1, 4])
        XCTAssertEqual(points.map(\.x), [0, 5, 10])
    }

    func testProjectileRangePeaksAtFortyFiveDegrees() throws {
        let points = VariableSweep.sample(source: projectile, variableLineIndex: 1, resultLineIndex: 3,
                                          range: try range(0, 90, 1), count: 91)
        XCTAssertEqual(points.count, 91)
        let best = try XCTUnwrap(points.max { $0.y < $1.y })
        XCTAssertEqual(best.x, 45)
        XCTAssertEqual(best.y, 400 / 9.80665, accuracy: 1e-9)
    }

    func testFailingSamplesAreSkippedAndGapsAreVisible() throws {
        // sqrt(x) needs x ≥ 0: samples at −2 and −1 fail.
        let source = "x = 1 m\ny = sqrt(x / 1 m)\ny"
        let points = VariableSweep.sample(source: source, variableLineIndex: 0, resultLineIndex: 2,
                                          range: try range(-2, 3, 1), count: 6)
        XCTAssertEqual(points.map(\.x), [0, 1, 2, 3])
        XCTAssertEqual(points.map(\.index), [2, 3, 4, 5])
        XCTAssertEqual(VariableSweep.segments(points).count, 1)

        let hole = VariableSweep.sample(source: "x = 1\ny = 1 / (x - 2)\ny", variableLineIndex: 0, resultLineIndex: 2,
                                        range: try range(0, 4, 1), count: 5)
        XCTAssertEqual(hole.map(\.x), [0, 1, 3, 4])
        XCTAssertEqual(VariableSweep.segments(hole).map { $0.map(\.x) }, [[0, 1], [3, 4]])
        XCTAssertEqual(hole.map(\.y), [-0.5, -1, 1, 0.5])
    }

    func testInvalidRequestsGiveNoPoints() throws {
        let range = try range(0, 1)
        XCTAssertEqual(VariableSweep.sample(source: "a = 2 m\na", variableLineIndex: 5, resultLineIndex: 1, range: range), [])
        XCTAssertEqual(VariableSweep.sample(source: "a = 2 m\na", variableLineIndex: 0, resultLineIndex: 9, range: range), [])
        // Only a literal declaration can be swept.
        XCTAssertEqual(VariableSweep.sample(source: "a = 2 m\nb = 3 * a\nb", variableLineIndex: 1, resultLineIndex: 2, range: range), [])
        XCTAssertEqual(VariableSweep.sample(source: "a = ? m\na == 1 m", variableLineIndex: 0, resultLineIndex: 1, range: range), [])
        // A comment or a blank line is not a result.
        XCTAssertEqual(VariableSweep.sample(source: "a = 2 m\n# note", variableLineIndex: 0, resultLineIndex: 1, range: range), [])
    }

    func testCountIsClampedAndEndpointsAreExact() throws {
        let range = try range(0.1, 0.7, 0.1)
        let two = VariableSweep.sample(source: "a = 0,3\na", variableLineIndex: 0, resultLineIndex: 1, range: range, count: 0)
        XCTAssertEqual(two.map(\.x), [0.1, 0.7])
        let many = VariableSweep.sample(source: "a = 0,3\na", variableLineIndex: 0, resultLineIndex: 1, range: range, count: 1_000_000)
        XCTAssertEqual(many.count, VariableSweep.maximumCount)
        XCTAssertEqual(many.last?.x, 0.7)
        XCTAssertEqual(VariableSweep.sample(source: "a = 0,3\na", variableLineIndex: 0, resultLineIndex: 1, range: range).count, 101)
    }

    func testCRLFSourcesAndTheDefaultCount() throws {
        let points = VariableSweep.sample(source: "a = 1 m\r\nb = a * 2\r\nb", variableLineIndex: 0, resultLineIndex: 2,
                                          range: try range(0, 10, 1))
        XCTAssertEqual(points.count, 101)
        XCTAssertEqual(points[50].x, 5)
        XCTAssertEqual(points[50].y, 10)
    }

    func testAxisUnitSymbols() {
        XCTAssertEqual(QuantityFormatter.unitSymbol(for: Dimension.mass + .length - .time.scaled(by: 2) + .length), "J")
        XCTAssertEqual(QuantityFormatter.unitSymbol(for: .dimensionless), "")
        XCTAssertEqual(QuantityFormatter.unitSymbol(for: .length - .time), "m·s⁻¹")
        XCTAssertEqual(QuantityFormatter.unitSymbol(for: .length, in: DisplayUnit(symbol: "km", scale: 1000)), "km")
    }

    func testCancellationStopsTheSweep() throws {
        let done = expectation(description: "Terminé")
        let range = try range(0, 1000, 1)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            let points = VariableSweep.sample(source: "a = 1\na", variableLineIndex: 0, resultLineIndex: 1, range: range)
            XCTAssertTrue(points.isEmpty)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        _ = task
    }
}
