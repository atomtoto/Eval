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

    func testExpandedCatalogueHasUniqueUsableIdentifiersAndSources() throws {
        XCTAssertGreaterThanOrEqual(ConstantCatalog.all.count, 60)
        XCTAssertEqual(Set(ConstantCatalog.all.map(\.id)).count, ConstantCatalog.all.count)
        XCTAssertEqual(Set(ConstantCatalog.all.map(\.symbol)).count, ConstantCatalog.all.count)
        for category in ConstantCategory.allCases {
            XCTAssertTrue(ConstantCatalog.all.contains { $0.category == category }, category.title)
        }
        for constant in ConstantCatalog.all {
            XCTAssertTrue(constant.quantity.value.isFinite, constant.id)
            XCTAssertFalse(constant.detail.isEmpty, constant.id)
            XCTAssertFalse(constant.sourceName.isEmpty, constant.id)
            XCTAssertEqual(try XCTUnwrap(constant.sourceURL, constant.id).scheme, "https")
            let result = NotebookEngine().evaluate(constant.id)
            let value = try successfulQuantity(try XCTUnwrap(result.lines.first))
            XCTAssertEqual(value, constant.quantity, constant.id)
            XCTAssertEqual(result.constants.map(\.id), [constant.id], constant.id)
        }
    }

    func testCODATA2022ParticleAndChemistryValues() throws {
        XCTAssertEqual(try constant("m_n").quantity.value, 1.67492750056e-27)
        XCTAssertEqual(try constant("m_u").quantity.value, 1.66053906892e-27)
        XCTAssertEqual(try constant("M_u").quantity.value, 1.00000000105e-3)
        XCTAssertEqual(try constant("R_inf").quantity.value, 10_973_731.568157)
        XCTAssertEqual(try constant("E_h").quantity.value, 4.3597447222060e-18)
        XCTAssertTrue(try constant("m_u").quantity.dimension.isEquivalent(to: .mass))
        XCTAssertTrue(try constant("M_u").quantity.dimension.isEquivalent(to: .mass - .amount))
        XCTAssertTrue(try constant("R_inf").quantity.dimension.isEquivalent(to: .dimensionless - .length))
        XCTAssertFalse(try constant("M_u").isExact)
        XCTAssertFalse(try constant("mu_0").isExact)
        XCTAssertFalse(try constant("l_P").isExact)
        XCTAssertEqual(try constant("m_u").nature, .measured)
    }

    func testDerivedElectricalConstantsKeepSIUnitsAndExactness() throws {
        let evaluation = NotebookEngine().evaluate("Phi_0 = h/(2e)\nR_K = h/e^2\nG_0 = 2e^2/h\nK_J = 2e/h\nF_const = N_A*e")
        for (line, identifier) in zip(evaluation.lines, ["Phi_0", "R_K", "G_0", "K_J", "F_const"]) {
            let value = try successfulQuantity(line)
            let expected = try constant(identifier)
            XCTAssertEqual(value.value, expected.quantity.value, accuracy: abs(value.value) * 1e-14)
            XCTAssertTrue(value.dimension.isEquivalent(to: expected.quantity.dimension))
            XCTAssertTrue(expected.isExact)
            XCTAssertEqual(expected.nature, .exact)
        }
        XCTAssertEqual(try constant("F_const").quantity.value, 96_485.33212331002, accuracy: 1e-9)
        XCTAssertEqual(try constant("R_K").quantity.value, 25_812.8074593045, accuracy: 1e-8)
        XCTAssertEqual(try constant("K_J").quantity.value, 4.835978484169836e14, accuracy: 100)
    }

    func testChemistryFormulaResolvesConstantsAndForwardDeclarations() throws {
        let evaluation = NotebookEngine().evaluate("Q = n*F_const\nN = n*N_A\nn = 2 mol\nQ\nN")
        let charge = try successfulQuantity(evaluation.lines[0])
        let count = try successfulQuantity(evaluation.lines[1])
        XCTAssertEqual(charge.value, 192_970.66424662004, accuracy: 1e-8)
        XCTAssertTrue(charge.dimension.isEquivalent(to: .electricCurrent + .time))
        XCTAssertEqual(count.value, 1.204428152e24, accuracy: 1e10)
        XCTAssertTrue(count.dimension.isDimensionless)
        XCTAssertEqual(Set(evaluation.constants.map(\.id)), ["F_const", "N_A"])
    }

    func testReferenceGasVolumesDistinguishPressureConditions() throws {
        let evaluation = NotebookEngine().evaluate("p_atm*V_m_atm/(R*273,15 K)\np_standard*V_m_100kPa/(R*273,15 K)\nN_A/V_m_atm\nN_A/V_m_100kPa")
        for line in evaluation.lines.prefix(2) {
            let value = try successfulQuantity(line)
            XCTAssertEqual(value.value, 1, accuracy: 1e-14)
            XCTAssertTrue(value.dimension.isDimensionless)
        }
        let atAtmosphere = try successfulQuantity(evaluation.lines[2])
        let atBar = try successfulQuantity(evaluation.lines[3])
        XCTAssertEqual(atAtmosphere.value, try constant("n_L_atm").quantity.value, accuracy: 1e11)
        XCTAssertEqual(atBar.value, try constant("n_L_100kPa").quantity.value, accuracy: 1e11)
        XCTAssertGreaterThan(atAtmosphere.value, atBar.value)
        XCTAssertTrue(atBar.dimension.isEquivalent(to: .dimensionless - .length.scaled(by: 3)))
        XCTAssertEqual(try constant("V_m_atm").quantity.value, 0.02241396954501414, accuracy: 1e-14)
        XCTAssertEqual(try constant("V_m_100kPa").quantity.value, 0.022710954641485576, accuracy: 1e-14)
        XCTAssertTrue(try constant("V_m_atm").detail.contains("101,325 kPa"))
        XCTAssertTrue(try constant("V_m_100kPa").detail.contains("100 kPa"))
    }

    func testThermalRadiationConstantsGivePowerAndWavelength() throws {
        let evaluation = NotebookEngine().evaluate("P = sigma_SB*A*temperature^4\nlambda = b_Wien/temperature\nA = 2 m^2\ntemperature = 300 K")
        let power = try successfulQuantity(evaluation.lines[0])
        let wavelength = try successfulQuantity(evaluation.lines[1])
        XCTAssertEqual(try constant("sigma_SB").quantity.value, 5.670374419184429e-8, accuracy: 1e-20)
        XCTAssertEqual(power.value, 918.6006559078775, accuracy: 1e-7)
        XCTAssertTrue(power.dimension.isEquivalent(to: try XCTUnwrap(UnitCatalog.lookup("W")).quantity.dimension))
        XCTAssertEqual(wavelength.value, 9.65923985e-6, accuracy: 1e-14)
        XCTAssertTrue(wavelength.dimension.isEquivalent(to: .length))
        XCTAssertTrue(try constant("sigma_SB").isExact)
    }

    func testNominalAstronomicalReferencesAreClearlyConventional() throws {
        XCTAssertEqual(try constant("au").quantity.value, 149_597_870_700)
        XCTAssertEqual(try constant("R_sun_N").quantity.value, 6.957e8)
        XCTAssertEqual(try constant("GM_earth_N").quantity.value, 3.986004e14)
        for definition in ConstantCatalog.all where definition.category == .astronomy {
            XCTAssertEqual(definition.nature, .conventional, definition.id)
            XCTAssertTrue(definition.isExact, definition.id)
        }
        let evaluation = NotebookEngine().evaluate("sqrt(GM_earth_N/R_earth_equatorial_N)")
        let speed = try successfulQuantity(evaluation.lines[0])
        XCTAssertEqual(speed.value, 7_905.388234385281, accuracy: 1e-7)
        XCTAssertTrue(speed.dimension.isEquivalent(to: .length - .time))
    }

    func testAliasesPreserveOriginalConstantsWithoutTakingFaradUnit() throws {
        let aliases = ["c0": "c", "g_n": "g", "ℏ": "hbar", "k": "k_B", "Na": "N_A", "ε₀": "epsilon_0",
                       "µ₀": "mu_0", "π": "pi", "α": "alpha", "me": "m_e", "mp": "m_p",
                       "Faraday": "F_const", "μ_B": "mu_B", "σ": "sigma_SB", "AU": "au"]
        for (alias, expectedID) in aliases {
            XCTAssertEqual(try constant(alias).id, expectedID)
            XCTAssertTrue(ConstantCatalog.aliases(for: try constant(expectedID)).contains(alias))
        }
        XCTAssertNil(ConstantCatalog.lookup("F"))
        XCTAssertNil(ConstantCatalog.lookup("u"))
        let evaluation = NotebookEngine().evaluate("F\n1 F\ne\neuler\nF_const\nF_const = 2 C/mol")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).dimension,
                       try XCTUnwrap(UnitCatalog.lookup("F")).quantity.dimension)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 1)
        XCTAssertFalse(try successfulQuantity(evaluation.lines[2]).dimension.isDimensionless)
        XCTAssertTrue(try successfulQuantity(evaluation.lines[3]).dimension.isDimensionless)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[4]).value, 2)
        XCTAssertFalse(evaluation.constants.contains { $0.id == "F_const" })
    }

    private func constant(_ identifier: String) throws -> ConstantDefinition {
        try XCTUnwrap(ConstantCatalog.lookup(identifier), identifier)
    }

    private func successfulQuantity(
        _ line: EvaluatedLine,
        file: StaticString = #filePath,
        line sourceLine: UInt = #line
    ) throws -> Quantity {
        XCTAssertEqual(line.status, .success, line.message ?? line.source, file: file, line: sourceLine)
        return try XCTUnwrap(line.quantity, line.message ?? line.source, file: file, line: sourceLine)
    }
}
