import XCTest
@testable import EvalCore

final class PhysicalCatalogTests: XCTestCase {
    func testSIBaseAndDerivedUnitsAreConsistent() throws {
        let newton = try XCTUnwrap(UnitCatalog.lookup("N")).quantity
        let joule = try XCTUnwrap(UnitCatalog.lookup("J")).quantity
        let watt = try XCTUnwrap(UnitCatalog.lookup("W")).quantity
        XCTAssertTrue(newton.dimension.isEquivalent(to: Dimension(length: 1, mass: 1, time: -2)))
        XCTAssertTrue(joule.dimension.isEquivalent(to: newton.dimension + .length))
        XCTAssertTrue(watt.dimension.isEquivalent(to: joule.dimension - .time))
    }

    func testDecimalPrefixesScaleMassFromGrams() throws {
        let milligram = try XCTUnwrap(UnitCatalog.lookup("mg")).quantity
        let kilogram = try XCTUnwrap(UnitCatalog.lookup("kg")).quantity
        XCTAssertEqual(milligram.value, 1e-6, accuracy: 1e-18)
        XCTAssertEqual(kilogram.value, 1)
        XCTAssertTrue(milligram.dimension.isEquivalent(to: kilogram.dimension))
        XCTAssertNil(UnitCatalog.lookup("mkg"))
    }

    func testMicroAliasesAndCaseSensitivePrefixes() throws {
        let greekMu = try XCTUnwrap(UnitCatalog.lookup("μm")).quantity
        let microSign = try XCTUnwrap(UnitCatalog.lookup("µm")).quantity
        let asciiMicro = try XCTUnwrap(UnitCatalog.lookup("um")).quantity
        XCTAssertEqual(greekMu.value, microSign.value)
        XCTAssertEqual(asciiMicro.value, microSign.value)
        let milliwatt = try XCTUnwrap(UnitCatalog.lookup("mW")).quantity
        let megawatt = try XCTUnwrap(UnitCatalog.lookup("MW")).quantity
        XCTAssertEqual(milliwatt.value, 1e-3)
        XCTAssertEqual(megawatt.value, 1e6)
    }

    func testTimeAndAngleConversions() throws {
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("h")).quantity.value, 3_600)
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("min")).quantity.value, 60)
        let degree = try XCTUnwrap(UnitCatalog.lookup("deg")).quantity
        XCTAssertEqual(degree.value * 180, .pi, accuracy: 1e-12)
        XCTAssertTrue(degree.dimension.isEquivalent(to: .dimensionless))
    }

    func testLightSpeedAndStandardGravityHaveCorrectDimensions() throws {
        let lightSpeed = try XCTUnwrap(ConstantCatalog.lookup("c")).quantity
        let gravity = try XCTUnwrap(ConstantCatalog.lookup("g")).quantity
        XCTAssertEqual(lightSpeed.value, 299_792_458)
        XCTAssertEqual(gravity.value, 9.80665, accuracy: 1e-12)
        XCTAssertTrue(lightSpeed.dimension.isEquivalent(to: Dimension(length: 1, time: -1)))
        XCTAssertTrue(gravity.dimension.isEquivalent(to: Dimension(length: 1, time: -2)))
    }

    func testUnknownUnitsAndConstantsAreNotSilentlyAccepted() {
        XCTAssertNil(UnitCatalog.lookup("banane"))
        XCTAssertNil(ConstantCatalog.lookup("missing"))
    }

    func testFrenchFormattingAndScientificNotationRespectRounding() {
        XCTAssertEqual(QuantityFormatter.number(7.2), "7,2")
        XCTAssertEqual(QuantityFormatter.number(999_999_999.99), "1 × 10⁹")
        XCTAssertEqual(QuantityFormatter.number(0.000_099_999_999_999), "0,0001")
        let energy = Quantity(value: 1, dimension: Dimension(length: 2, mass: 1, time: -2))
        XCTAssertEqual(QuantityFormatter.string(energy), "1 J")
    }
}
