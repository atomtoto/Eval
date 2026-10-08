import XCTest
@testable import EvalCore

final class ExampleLibraryTests: XCTestCase {
    /// Lines that are meant to fail, to teach what an error looks like.
    private let intentionalErrors: [String: Set<String>] = ["dimensions": ["2 m + 3 s"]]

    /// The displayed result of each bare line, as the app shows it.
    private let pinned: [String: [String: String]] = [
        "free-fall": ["d": "44,1299 m", "v": "29,42 m·s⁻¹", "v → km/h": "105,912 km/h"],
        "kinetic-energy": ["E": "1000 J", "c": "299792458 m·s⁻¹"],
        "projectile": ["portee": "40,7886 m", "h_max": "10,1972 m", "duree": "2,88419 s"],
        "pendulum": ["T": "2,00641 s"],
        "spring": ["T": "0,314159 s", "f → Hz": "3,1831 Hz"],
        "relativity": ["gamma": "1,66667", "v → km/s": "239834 km/s"],
        "heater": ["I": "4,34783 A", "P": "1000 W", "E → kWh": "2 kWh"],
        "rc-circuit": ["tau": "1 s", "U_C": "7,58545 V"],
        "coulomb": ["F": "−21,5701 N"],
        "lens": ["d_i": "0,0512821 m", "gamma": "−0,025641"],
        "young": ["i → mm": "13 mm"],
        "ideal-gas": ["p → atm": "1,0023 atm"],
        "water-heating": ["Q → kJ": "501,6 kJ", "duree → min": "4,18 min"],
        "black-body": ["lambda_max → nm": "502,039 nm", "M → W/m²": "62938592 W/m²"],
        "electron": ["v → km/s": "5930,97 km/s", "lambda → pm": "122,643 pm"],
        "photoelectric": ["E_c → eV": "0,819605 eV"],
        "hydrogen": ["lambda → nm": "656,112 nm"],
        "light-energy": ["E → eV": "2,25426 eV", "c / lambda → THz": "545,077 THz"],
        "kepler": ["T": "31558196 s", "T → jour": "365,257 jour"],
        "escape-velocity": ["v_lib → km/s": "11,1799 km/s"],
        "geostationary": ["r": "42164171 m", "altitude → km": "35786,1 km"],
        "dimensions": ["m * a == F": "14,4 N"],
        "solve-unknown": ["E == 0,5 * m * v²": "1000 J", "v → km/h": "18 km/h"]
    ]

    func testEveryExampleEvaluatesWithoutUnexpectedErrors() {
        for example in ExampleLibrary.all {
            let evaluation = NotebookEngine.evaluate(example.source)
            for line in evaluation.lines where line.status == .error {
                XCTAssertTrue(intentionalErrors[example.id]?.contains(line.source) == true,
                              "\(example.id): \(line.source) — \(line.message ?? "")")
            }
            // Names that fall back to units would be mistaken for variables.
            XCTAssertTrue(evaluation.symbolUnits.isEmpty, "\(example.id): \(evaluation.symbolUnits.map(\.symbol))")
        }
        XCTAssertEqual(ExampleLibrary.all.flatMap { example in
            NotebookEngine.evaluate(example.source).lines.filter { $0.status == .error }.map(\.source)
        }, ["2 m + 3 s"])
    }

    func testKeyValuesArePinned() {
        for example in ExampleLibrary.all {
            let expected = pinned[example.id] ?? [:]
            XCTAssertFalse(expected.isEmpty, example.id)
            let shown = Dictionary(NotebookEngine.evaluate(example.source).lines.compactMap { line -> (String, String)? in
                guard line.kind == .expression || line.kind == .equation, let quantity = line.quantity else { return nil }
                return (line.source, QuantityFormatter.string(quantity, in: line.displayUnit))
            }, uniquingKeysWith: { first, _ in first })
            XCTAssertEqual(shown, expected, example.id)
        }
        XCTAssertEqual(Set(pinned.keys), Set(ExampleLibrary.all.map(\.id)))
    }

    func testExamplesFollowTheSheetConventions() {
        XCTAssertEqual(Set(ExampleLibrary.all.map(\.id)).count, ExampleLibrary.all.count)
        XCTAssertEqual(Set(ExampleLibrary.all.map(\.title)).count, ExampleLibrary.all.count)
        for example in ExampleLibrary.all {
            XCTAssertTrue(example.source.hasPrefix("# "), example.id)
            XCTAssertFalse(example.summary.isEmpty, example.id)
            XCTAssertLessThanOrEqual(example.source.components(separatedBy: "\n").count, 20, example.id)
            let evaluation = NotebookEngine.evaluate(example.source)
            XCTAssertTrue(evaluation.lines.contains { $0.kind == .expression || $0.kind == .equation }, example.id)
        }
        for title in ["Énergie cinétique", "Énergie et lumière", "Vérifier les dimensions", "Chute libre"] {
            XCTAssertTrue(ExampleLibrary.all.contains { $0.title == title }, title)
        }
    }

    func testDomainsAreGroupedWithFrenchTitles() {
        XCTAssertEqual(ExampleDomain.allCases.map(\.title), ["Mécanique", "Électricité", "Optique et ondes",
                                                             "Thermodynamique", "Quantique", "Astronomie", "Méthode"])
        for domain in ExampleDomain.allCases {
            XCTAssertFalse(ExampleLibrary.examples(in: domain).isEmpty, domain.title)
        }
        XCTAssertEqual(ExampleLibrary.examples(in: .method).map(\.id), ["dimensions", "solve-unknown"])
        XCTAssertEqual(ExampleLibrary.example(id: "free-fall")?.title, "Chute libre")
        XCTAssertNil(ExampleLibrary.example(id: "inconnu"))
        XCTAssertEqual(ExampleLibrary.all.map(\.domain).reduce(into: [ExampleDomain]()) { if $1 != $0.last { $0.append($1) } },
                       ExampleDomain.allCases, "examples are listed domain by domain")
    }

    func testSolveUnknownExampleFindsBothSpeeds() throws {
        let example = try XCTUnwrap(ExampleLibrary.example(id: "solve-unknown"))
        XCTAssertEqual(example.title, "Trouver une inconnue")
        XCTAssertEqual(example.domain, .method)
        let unknown = try XCTUnwrap(NotebookEngine.evaluate(example.source).lines.first { $0.source == "v = ? m/s" })
        XCTAssertEqual(QuantityFormatter.string(try XCTUnwrap(unknown.quantity), in: unknown.displayUnit), "5 m/s")
        XCTAssertEqual(unknown.message, "Autre solution : −5 m/s.")
    }

    func testFreeFallCoversTheDistanceOfARealFall() throws {
        let evaluation = NotebookEngine.evaluate(try XCTUnwrap(ExampleLibrary.example(id: "free-fall")).source)
        // The former sheet used 7,2 m/s² and gave 32,4 m.
        XCTAssertEqual(evaluation.variables.first { $0.name == "d" }?.quantity.value ?? 0, 44.129925, accuracy: 1e-9)
    }
}
