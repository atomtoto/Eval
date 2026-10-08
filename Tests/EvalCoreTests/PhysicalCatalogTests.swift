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

    func testNonSIUnitReferenceValues() throws {
        typealias Dim = EvalCore.Dimension
        let pressure = Dim(length: -1, mass: 1, time: -2)
        let energy = Dim(length: 2, mass: 1, time: -2)
        let force = Dim(length: 1, mass: 1, time: -2)
        let expected: [(String, Double, Dim)] = [
            ("atm", 101_325, pressure), ("Torr", 101_325.0 / 760, pressure),
            ("mmHg", 133.322_387_415, pressure), ("cal", 4.184, energy), ("Wh", 3_600, energy),
            ("Ah", 3_600, Dim(time: 1, electricCurrent: 1)), ("Å", 1e-10, .length),
            ("ly", 9_460_730_472_580_800, .length), ("pc", 3.085_677_581_491_367e16, .length),
            ("Da", 1.660_539_068_92e-27, .mass), ("jour", 86_400, .time), ("an", 31_557_600, .time),
            ("tr", 2 * Double.pi, .dimensionless), ("rpm", 2 * Double.pi / 60, Dim(time: -1)),
            ("%", 0.01, .dimensionless), ("ppm", 1e-6, .dimensionless), ("ft", 0.3048, .length),
            ("mi", 1_609.344, .length), ("lb", 0.453_592_37, .mass), ("lbf", 4.448_221_615_260_5, force)
        ]
        for (symbol, value, dimension) in expected {
            let unit = try XCTUnwrap(UnitCatalog.lookup(symbol), symbol)
            XCTAssertEqual(unit.quantity.value, value, accuracy: abs(value) * 1e-15, symbol)
            XCTAssertTrue(unit.quantity.dimension.isEquivalent(to: dimension), symbol)
        }
        for (alias, symbol) in [("angstrom", "Å"), ("day", "jour"), ("yr", "an"), ("year", "an")] {
            XCTAssertEqual(UnitCatalog.lookup(alias)?.quantity, UnitCatalog.lookup(symbol)?.quantity, alias)
        }
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("Da")).quantity.value,
                       try constant("m_u").quantity.value)
    }

    func testNonSIUnitsAcceptOnlyListedPrefixes() throws {
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("mbar")).quantity.value, 100, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("kWh")).quantity.value, 3.6e6)
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("mAh")).quantity.value, 3.6, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("kcal")).quantity.value, 4184, accuracy: 1e-9)
        for symbol in ["kpc", "Mpc", "kDa", "mTorr", "hPa", "kbar", "MWh"] {
            XCTAssertNotNil(UnitCatalog.lookup(symbol), symbol)
        }
        for symbol in ["kmi", "Min", "kft", "kan", "Matm", "hbar", "Mbar", "mcal", "kly", "mmmHg", "kjour", "k%", "mrpm"] {
            XCTAssertNil(UnitCatalog.lookup(symbol), symbol)
        }
        for symbol in ["mbar", "hPa", "kWh", "MWh", "mAh", "kcal", "kpc", "Mpc", "kDa", "mTorr"] {
            XCTAssertTrue(UnitCatalog.all.contains { $0.symbol == symbol }, symbol)
        }
    }

    func testHbarRemainsReducedPlanckConstant() throws {
        let evaluation = NotebookEngine().evaluate("hbar\n1 hbar\nhbar / h")
        let planck = try constant("hbar").quantity
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]), planck)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]), planck)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 1 / (2 * .pi), accuracy: 1e-15)
    }

    func testCommonVariableNamesAreNotUnits() throws {
        let names = ["t", "d", "a", "u", "j", "x", "y", "z", "v", "r", "p", "q", "n", "psi", "phi", "chi", "rho",
                     "eta", "theta", "omega", "lambda", "mu", "nu", "xi", "pt", "Mt", "kt", "dt", "da", "in", "kn",
                     "G", "Gs"]
        for name in names where name != "Gs" {
            XCTAssertNil(UnitCatalog.lookup(name), name)
        }
        // Gigasecond predates this policy and stays.
        XCTAssertNotNil(UnitCatalog.lookup("Gs"))
        let grandfathered: Set = ["g", "h"]
        for constant in ConstantCatalog.all {
            let spellings = [constant.id, constant.symbol] + ConstantCatalog.aliases(for: constant)
            for spelling in spellings where !grandfathered.contains(spelling) {
                XCTAssertNil(UnitCatalog.lookup(spelling), spelling)
            }
        }
    }

    func testAngstromAcceptsBothUnicodeForms() throws {
        let angstromSign = try XCTUnwrap(UnitCatalog.lookup("\u{212B}"))
        let latinA = try XCTUnwrap(UnitCatalog.lookup("\u{00C5}"))
        XCTAssertEqual(angstromSign.quantity, latinA.quantity)
        XCTAssertEqual(latinA.quantity.value, 1e-10)
    }

    func testPrefixedLitreOhmAndBarSpellings() throws {
        let litre = try XCTUnwrap(UnitCatalog.lookup("L")).quantity.value
        for (symbol, factor) in [("ml", 1e-3), ("mL", 1e-3), ("cl", 1e-2), ("dl", 1e-1), ("hl", 1e2), ("kl", 1e3),
                                 ("µl", 1e-6), ("μl", 1e-6), ("ul", 1e-6), ("l", 1)] {
            XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup(symbol), symbol).quantity.value, litre * factor,
                           accuracy: litre * factor * 1e-12, symbol)
        }
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("kohm")).quantity.value, 1e3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("Mohm")).quantity.value, 1e6)
        XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup("kΩ")).quantity.value, 1e3)
        XCTAssertEqual(UnitCatalog.lookup("kohm")?.symbol, "kohm")
        // Explicit aliases keep short variable names free.
        for symbol in ["al", "pl", "fl", "kh", "mmin", "kdeg"] { XCTAssertNil(UnitCatalog.lookup(symbol), symbol) }
        for source in ["5 ml", "33 cl", "2 hl", "4,7 kohm", "1013 mbar", "2 kWh", "1 atm"] {
            XCTAssertEqual(NotebookEngine.evaluate(source).lines[0].status, .success, source)
        }
    }

    func testUnitIndexFollowsPrefixPolicyForEveryPrefixAndUnit() throws {
        for prefix in UnitCatalog.prefixes {
            for base in UnitCatalog.baseAndDerived {
                let symbol = prefix.symbol + base.symbol
                let found = UnitCatalog.lookup(symbol)
                let allowed = UnitCatalog.allowedPrefixes[base.symbol]?.contains(prefix.symbol) ?? true
                let listed = UnitCatalog.baseAndDerived.contains { $0.symbol == symbol }
                    || UnitCatalog.all.contains { $0.symbol == symbol }
                if allowed || listed {
                    XCTAssertNotNil(found, symbol)
                    if listed { continue }
                    // Another prefix may read the same letters (dam, mmol): the first one wins.
                    let candidates = UnitCatalog.prefixes.compactMap { other -> Double? in
                        guard symbol.hasPrefix(other.symbol),
                              let unit = UnitCatalog.baseAndDerived.first(where: { $0.symbol == String(symbol.dropFirst(other.symbol.count)) }),
                              UnitCatalog.allowedPrefixes[unit.symbol]?.contains(other.symbol) ?? true
                        else { return nil }
                        return other.scale * unit.quantity.value
                    }
                    XCTAssertEqual(found?.quantity.value, candidates.first, symbol)
                } else {
                    XCTAssertNil(found, symbol)
                }
            }
        }
        for (symbol, value) in [("mm", 1e-3), ("Pa", 1), ("dam", 10), ("kmol", 1e3), ("µs", 1e-6)] {
            XCTAssertEqual(try XCTUnwrap(UnitCatalog.lookup(symbol)).quantity.value, value, symbol)
        }
        XCTAssertEqual(UnitCatalog.lookup("μs"), UnitCatalog.lookup("µs"))
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
