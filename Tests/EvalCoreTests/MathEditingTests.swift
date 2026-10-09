import XCTest
@testable import EvalCore

final class MathEditingTests: XCTestCase {
    private func row(_ text: String) -> MathRow { MathRow(text: text) }

    private func typed(_ keys: String) -> MathEditorState {
        var state = MathEditorState(source: "")
        state.insert(keys)
        return state
    }

    // MARK: - Round trip

    /// Declarations shared by the dedicated corpus.
    private let context = """
        a = 3
        b = 4
        c_1 = 2
        n = 2
        x = 5
        y = 2 m
        t = 1 s
        tau = 2 s
        m = 80 kg
        v = 5 m/s
        θ = 30 deg
        """

    private let corpus = [
        "5 m/s²", "72 km/h", "72km/h", "3g/cm³", "10 m/s^2", "5 kg*m/s²", "4180 J/kg/K",
        "v → km/h", "v -> km/h", "v → km/h =", "E = 0,5*m*v² =", "E =", "a =", "E = 0,5 * m * v² → J",
        "a / b # une note", "a/b // note", "a/b//note", "# titre", "// seul", "",
        "max(2,5; 3)", "atan2(a; x)", "root(27; 3)", "cbrt(27)", "cbrt(-8)", "root(a/b; n + 1)",
        "a/b/c_1", "a / (b/c_1)", "x / (a/b)", "(a/b)²", "(a/b)^n", "1/(1/a - 1/b)", "a/b/(c_1/x)",
        "2^(n+1)", "2^n+1", "e^(-t/tau)", "x^-1", "x⁻¹", "x^(1/3)", "2^3^2", "(x + a)^(n - 1)", "10^-19",
        "v = ? m/s", "w = ? m/s", "m * v == 400 kg*m/s", "a + b == 7",
        "√2 m", "√(2) m", "√x", "√x²", "sqrt(x)²", "sqrt(a² + b²)", "2√a", "a√b", "√(a/b)", "√a/b",
        "-5", "-a/b", "- a / b", "-(a + b)/c_1", "a * -b/x", "2,5 / 0,5", "1,5e3/3", "0.5 * a",
        "a² + b²", "x²/2", "-x²/2", "x²³", "n!/2", "(n+1)!/n", "sin(θ)/cos(θ)", "sin(θ)²", "y/2 m", "1/2 m",
        "y / t / 2", "y / 2 t", "2 x/a", "a*b/c_1", "a b/c_1", "(a + b)/(a - b)", "π/2", "100 %",
        "a/b²", "a/(b²)", "(a/b)/c_1", "y/(t*2)²", "exp(-(t/tau)²)", "abs(-a)/a",
        "F = m * a", "p = m * v", "p", "q = a/b + b/a", "r = root(x; 3) + cbrt(a)",
        "a/b + ", "a ++ b", "?", "(a", "a)/b", "1 / 0", "2 m + 3 s"
    ]

    func testExamplesRoundTripToTheSameValues() {
        for example in ExampleLibrary.all {
            assertRoundTrip(sheet: example.source, label: example.id)
        }
    }

    func testCorpusRoundTripsToTheSameValues() {
        for line in corpus {
            assertRoundTrip(sheet: context + "\n" + line, onlyLast: true, label: line)
        }
    }

    /// Every line rewritten through the editor evaluates like the original, in its sheet.
    private func assertRoundTrip(sheet: String, onlyLast: Bool = false, label: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let lines = sheet.components(separatedBy: "\n")
        let original = NotebookEngine.evaluate(sheet).lines
        for index in lines.indices where !onlyLast || index == lines.count - 1 {
            var rewritten = lines
            rewritten[index] = MathEditorState(source: lines[index]).source
            let evaluation = NotebookEngine.evaluate(rewritten.joined(separator: "\n")).lines
            let context = "\(label): \(lines[index]) → \(rewritten[index])"
            XCTAssertEqual(evaluation.count, original.count, context, file: file, line: line)
            for (before, after) in zip(original, evaluation) {
                XCTAssertEqual(after.kind, before.kind, context, file: file, line: line)
                XCTAssertEqual(after.status, before.status, "\(context) [\(after.message ?? "")]", file: file, line: line)
                XCTAssertEqual(after.displayUnit, before.displayUnit, context, file: file, line: line)
                XCTAssertEqual(after.quantity?.dimension, before.quantity?.dimension, context, file: file, line: line)
                if let value = before.quantity?.value, let other = after.quantity?.value {
                    XCTAssertEqual(other, value, accuracy: abs(value) * 1e-12, context, file: file, line: line)
                } else {
                    XCTAssertEqual(after.quantity == nil, before.quantity == nil, context, file: file, line: line)
                }
            }
        }
    }

    func testSerializationIsCanonical() {
        let expected: [String: String] = [
            "1/2": "1/2", "a / b": "a/b", "x / (a/b)": "x/(a/b)", "(a/b)²": "(a/b)²", "(a/b)^2": "(a/b)²",
            "a/b/c": "(a/b)/c", "2^(n+1)": "2^(n+1)", "e^(-t/tau)": "e^(-t/tau)", "x^-1": "x⁻¹", "10^-19": "10⁻¹⁹",
            "x^(1/3)": "x^(1/3)", "x^n": "x^n", "x^(n)": "x^n", "2^10": "2¹⁰",
            "√2 m": "√(2) m", "sqrt(l / g)": "√(l/g)", "root(27; 3)": "root(27; 3)", "cbrt(27)": "root(27; 3)",
            "-d_i / d_o": "-d_i/d_o", "-a / b / c": "(-a/b)/c", "a*b/c": "(a*b)/c", "1/(1/f - 1/d)": "1/(1/f - 1/d)",
            "(v0 * sin(theta))² / (2 * g)": "(v0 * sin(theta))²/(2 * g)", "sin(x)/2": "sin(x)/2",
            "5 m/s²": "5 m/s²", "72km/h": "72km/h", "3g/cm³": "3g/cm³", "4180 J/kg/K": "4180 J/kg/K",
            "v → km/h": "v → km/h", "M → W/m²": "M → W/m²", "E =": "E =", "E = 0,5*m*v² =": "E = 0,5*m*v² =",
            "v = ? m/s": "v = ? m/s", "F == m * a": "F == m * a", "max(2,5; 3)": "max(2,5; 3)",
            "a/b # note": "a/b # note", "a/b// note": "a/b// note", "?": "?", "(a": "(a"
        ]
        for (source, serialized) in expected {
            XCTAssertEqual(MathEditorState(source: source).source, serialized, source)
        }
    }

    // MARK: - Reading

    func testReadingBuildsStructures() {
        XCTAssertEqual(MathEditorState(source: "1/2").root, MathRow([.fraction(row("1"), row("2"))]))
        XCTAssertEqual(MathEditorState(source: "E = m*c²").root.items.suffix(2),
                       [.symbol("c"), .superscript(row("2"))])
        XCTAssertEqual(MathEditorState(source: "x⁻¹").root, MathRow([.symbol("x"), .superscript(row("-1"))]))
        XCTAssertEqual(MathEditorState(source: "(a+b)/(c-d)").root, MathRow([.fraction(row("a+b"), row("c-d"))]))
        XCTAssertEqual(MathEditorState(source: "(a/b)²").root,
                       MathRow([.symbol("("), .fraction(row("a"), row("b")), .symbol(")"), .superscript(row("2"))]))
        XCTAssertEqual(MathEditorState(source: "e^(-t/tau)").root,
                       MathRow([.symbol("e"), .superscript(MathRow([.symbol("-"), .fraction(row("t"), row("tau"))]))]))
        XCTAssertEqual(MathEditorState(source: "sqrt(x)").root, MathRow([.radical(row("x"))]))
        XCTAssertEqual(MathEditorState(source: "√2 m").root, MathRow([.radical(row("2")), .symbol(" "), .symbol("m")]))
        XCTAssertEqual(MathEditorState(source: "root(27; 3)").root, MathRow([.root(index: row("3"), radicand: row("27"))]))
        XCTAssertEqual(MathEditorState(source: "cbrt(8)").root, MathRow([.root(index: row("3"), radicand: row("8"))]))
        // Unit suffixes keep their slash; their powers are structures.
        XCTAssertEqual(MathEditorState(source: "5 m/s²").root, MathRow(row("5 m/s").items + [.superscript(row("2"))]))
        XCTAssertEqual(MathEditorState(source: "72km/h").root, row("72km/h"))
        // Conversion targets and unparseable members stay text.
        XCTAssertEqual(MathEditorState(source: "v → km/h").root, row("v → km/h"))
        XCTAssertEqual(MathEditorState(source: "v = ? m/s").root, row("v = ? m/s"))
        XCTAssertEqual(MathEditorState(source: "a/ = 2").root, row("a/ = 2"))
        let unknown = MathEditorState(source: "E == m/2")
        XCTAssertEqual(unknown.root, MathRow(row("E == ").items + [.fraction(row("m"), row("2"))]))
    }

    func testCommentIsKeptOutsideTheTree() {
        let state = MathEditorState(source: "a/b   # rapport")
        XCTAssertEqual(state.root, MathRow([.fraction(row("a"), row("b"))]))
        XCTAssertEqual(state.comment, "   # rapport")
        XCTAssertEqual(state.source, "a/b   # rapport")
        XCTAssertEqual(MathEditorState(source: "# titre").root, MathRow())
        XCTAssertEqual(MathEditorState(source: "x // a/b").comment, " // a/b")
    }

    func testTrailingResultRequestStaysASymbol() {
        for source in ["E =", "E = 0,5*m*v² =", "v → km/h =", "m * v =", "E = → J", "=", "= =", "→"] {
            let state = MathEditorState(source: source)
            XCTAssertEqual(state.source, source)
            XCTAssertEqual(state.cursor, MathCursor(offset: state.root.items.count))
        }
        XCTAssertEqual(MathEditorState(source: "E = 0,5*m*v² =").root.items.last, .symbol("="))
    }

    func testNewlinesAreDropped() {
        XCTAssertEqual(MathEditorState(source: "a\nb").source, "ab")
        XCTAssertEqual(typed("a\nb").source, "ab")
    }

    // MARK: - Typing

    func testTypingBuildsTheExpectedSource() {
        XCTAssertEqual(typed("E=m*c^2").source, "E=m*c²")
        XCTAssertEqual(typed("1/2").root, MathRow([.fraction(row("1"), row("2"))]))
        XCTAssertEqual(typed("1/2").source, "1/2")
        XCTAssertEqual(typed("v0²/2").root, MathRow([.fraction(MathRow([.symbol("v"), .symbol("0"), .superscript(row("2"))]), row("2"))]))
        XCTAssertEqual(typed("sin(x)/2").root, MathRow([.fraction(row("sin(x)"), row("2"))]))
        XCTAssertEqual(typed("a+bc/2").root, MathRow(row("a+").items + [.fraction(row("bc"), row("2"))]))
        XCTAssertEqual(typed("2,5/2").source, "2,5/2")
        XCTAssertEqual(typed("x⁻¹").root, MathRow([.symbol("x"), .superscript(row("-1"))]))
        XCTAssertEqual(typed("x⁻¹").source, "x⁻¹")
        XCTAssertEqual(typed("5 m/s").source, "5 m/s")
        // Spaces before a typed slash are dropped, the operand is still captured.
        XCTAssertEqual(typed("a / b").root, MathRow([.fraction(row("a"), row(" b"))]))
        XCTAssertEqual(typed("a / b").source, "a/ b")
        XCTAssertEqual(typed("2 * /").root, MathRow(row("2 * ").items + [.fraction(MathRow(), MathRow())]))

        var state = MathEditorState(source: "")
        state.insertRadical()
        state.insert("x")
        XCTAssertEqual(state.source, "√(x)")
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .radicand)], offset: 1))

        state = MathEditorState(source: "")
        state.insert("√2")
        state.moveRight()
        state.insert(" m")
        XCTAssertEqual(state.source, "√(2) m")
    }

    func testFractionCapturesTheOperandBeforeTheCursor() {
        var state = typed("a+")
        state.insertFraction()
        XCTAssertEqual(state.root, MathRow(row("a+").items + [.fraction(MathRow(), MathRow())]))
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 2, slot: .numerator)], offset: 0))

        state = typed("(a+b)/")
        XCTAssertEqual(state.root, MathRow([.fraction(row("(a+b)"), MathRow())]))
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .denominator)], offset: 0))

        state = typed("1/2/")
        XCTAssertEqual(state.root, MathRow([.fraction(row("1"), MathRow([.fraction(row("2"), MathRow())]))]))

        state = typed("1/2")
        state.moveRight()
        state.insert("/3")
        XCTAssertEqual(state.root, MathRow([.fraction(MathRow([.fraction(row("1"), row("2"))]), row("3"))]))
        XCTAssertEqual(state.source, "(1/2)/3")

        state = typed("n!/2")
        XCTAssertEqual(state.source, "n!/2")
    }

    func testTypedStructuresKeepTheirMeaning() {
        func value(_ keys: String) -> Double? {
            NotebookEngine.evaluate(typed(keys).source).lines.first?.quantity?.value
        }
        XCTAssertEqual(value("1/2"), 0.5)
        var state = typed("1/2")
        state.moveRight()
        state.insert(" m")
        XCTAssertEqual(state.source, "(1/2) m")
        state = typed("6/2")
        state.moveRight()
        state.insert("3")
        XCTAssertEqual(state.source, "(6/2)3")
        XCTAssertEqual(NotebookEngine.evaluate(state.source).lines.first?.quantity?.value, 9)
        state = typed("6/")
        state.insert("2")
        state.moveRight()
        state.insertPower()
        state.insert("2")
        XCTAssertEqual(state.source, "(6/2)²")
        state = typed("2^n")
        state.moveRight()
        state.insert("3")
        XCTAssertEqual(state.source, "2^(n)3")
        state = typed("2^1")
        state.moveRight()
        state.insert("0")
        XCTAssertEqual(state.source, "2^(1)0")
        XCTAssertEqual(NotebookEngine.evaluate(state.source).lines.first?.quantity?.value, 0)
        state = typed("2")
        state.insertRoot()
        state.insert("3")
        state.moveRight()
        state.insert("8")
        XCTAssertEqual(state.source, "2 root(8; 3)")
        XCTAssertEqual(NotebookEngine.evaluate(state.source).lines.first?.quantity?.value, 4)
        XCTAssertEqual(typed("1/").source, "1/()")
        XCTAssertEqual(typed("x^").source, "x^()")
        XCTAssertEqual(NotebookEngine.evaluate(typed("1/").source + " + 2").lines.first?.status, .error)
        var root = MathEditorState(source: "")
        root.insertRoot()
        XCTAssertEqual(root.source, "root((); ())")
        XCTAssertEqual(NotebookEngine.evaluate(root.source).lines.first?.status, .error)
    }

    // MARK: - Nested exponents

    private func lastLine(_ line: String) -> (status: LineStatus, value: Double?) {
        let result = NotebookEngine.evaluate("a = 3\nx = 2\n" + line).lines.last!
        return (result.status, result.quantity?.value)
    }

    /// `x²^3` is x^(2^3): the superscript `²` is the base of the nested power, not a symbol of the exponent row.
    func testSuperscriptFollowedByCaretSurvivesTheEditor() {
        for source in ["a²^2", "x²^3", "x²^-1", "(a + x)²^2", "5 m²^2", "5 K³^3"] {
            let written = MathEditorState(source: source).source
            let before = lastLine(source), after = lastLine(written)
            XCTAssertEqual(after.status, before.status, "\(source) → \(written)")
            XCTAssertEqual(after.value ?? .nan, before.value ?? .nan, "\(source) → \(written)")
            XCTAssertEqual(MathEditorState(source: written).source, written, "\(source) is stable")
        }
        XCTAssertEqual(lastLine("x²^3").value, 256)
    }

    /// Typing x, ^, 2, →, ^, 3 raises x² to the third power: `(x²)³`.
    func testConsecutiveExponentsParenthesizeTheBase() {
        var state = MathEditorState(source: "x")
        state.insertPower(); state.insert("2"); state.moveRight()
        state.insertPower(); state.insert("3")
        XCTAssertEqual(state.source, "(x²)³")
        XCTAssertEqual(lastLine(state.source).value, 64)
        XCTAssertEqual(MathEditorState(source: state.source).source, "(x²)³")
        XCTAssertEqual(typed("x²³").source, "x²³")
        XCTAssertEqual(lastLine(typed("(a + x)²").source).value, 25)

        var third = MathEditorState(source: "x")
        for exponent in ["1", "2", "2"] { third.insertPower(); third.insert(exponent); third.moveRight() }
        XCTAssertEqual(third.source, "((x¹)²)²")
        XCTAssertEqual(MathEditorState(source: third.source).source, third.source)

        var general = MathEditorState(source: "a")
        general.insertPower(); general.insert("x+1"); general.moveRight()
        general.insertPower(); general.insert("2")
        XCTAssertEqual(general.source, "(a^(x+1))²")
        XCTAssertEqual(lastLine(general.source).value, pow(27.0, 2))
    }

    /// An exponent with nothing to raise stands over an empty base: the line never starts with `^`.
    func testExponentWithoutBaseReadsAsAnEmptyBase() {
        var state = MathEditorState(source: "")
        state.insertPower()
        XCTAssertEqual(state.source, "()^()")
        state.insertPower()
        XCTAssertFalse(state.source.hasPrefix("^"))
        XCTAssertEqual(state.source, "()^()^()")
        XCTAssertTrue(state.root.lacksBase(at: 0))
        XCTAssertTrue(MathEditorState(source: "").root.lacksBase(at: 0) == false)

        var raised = MathEditorState(source: "x")
        raised.insertPower()
        XCTAssertFalse(raised.root.lacksBase(at: 1))
        XCTAssertEqual(raised.source, "x^()")

        var afterOperator = MathEditorState(source: "2+")
        afterOperator.insertPower()
        XCTAssertTrue(afterOperator.root.lacksBase(at: 2))
        XCTAssertEqual(afterOperator.source, "2+()^()")
    }

    // MARK: - Deleting

    func testDeleteBackward() {
        var state = typed("ab")
        state.deleteBackward()
        XCTAssertEqual(state.source, "a")

        // A filled structure is entered, then emptied, then removed.
        state = typed("1/2")
        state.moveToEnd()
        state.deleteBackward()
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .denominator)], offset: 1))
        state.deleteBackward()
        XCTAssertEqual(state.root, MathRow([.fraction(row("1"), MathRow())]))
        // At the start of the denominator, goes to the end of the numerator.
        state.deleteBackward()
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .numerator)], offset: 1))
        state.deleteBackward()
        XCTAssertEqual(state.root, MathRow([.fraction(MathRow(), MathRow())]))
        // At the start of the first row, the (now empty) structure goes away.
        state.deleteBackward()
        XCTAssertEqual(state.root, MathRow())
        XCTAssertEqual(state.cursor, MathCursor())
        state.deleteBackward()
        XCTAssertEqual(state.root, MathRow())

        // At the start of a first row, a filled structure is unwrapped.
        state = typed("x^2")
        state.moveLeft()
        state.deleteBackward()
        XCTAssertEqual(state.root, row("x2"))
        XCTAssertEqual(state.cursor, MathCursor(offset: 1))

        state = typed("a/b")
        state.setCursor(MathCursor(path: [MathPathStep(item: 0, slot: .numerator)], offset: 0))
        state.deleteBackward()
        XCTAssertEqual(state.root, row("ab"))
        XCTAssertEqual(state.cursor, MathCursor(offset: 0))

        // An empty structure before the cursor is removed at once.
        state = MathEditorState(root: MathRow([.symbol("a"), .radical(MathRow())]))
        state.deleteBackward()
        XCTAssertEqual(state.root, row("a"))
    }

    // MARK: - Moving

    func testHorizontalMovesEnterAndLeaveStructures() {
        var state = MathEditorState(source: "a/b+c")
        XCTAssertEqual(state.cursor, MathCursor(offset: 3))
        state.moveToStart()
        XCTAssertEqual(state.cursor, MathCursor(offset: 0))
        state.moveRight()
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .numerator)], offset: 0))
        state.moveRight()
        XCTAssertEqual(state.cursor.offset, 1)
        state.moveRight()
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .denominator)], offset: 0))
        state.moveRight()
        state.moveRight()
        XCTAssertEqual(state.cursor, MathCursor(offset: 1))
        state.moveRight()
        state.moveRight()
        XCTAssertFalse(state.moveRight())
        XCTAssertEqual(state.cursor, MathCursor(offset: 3))

        state.moveLeft()
        state.moveLeft()
        XCTAssertEqual(state.cursor, MathCursor(offset: 1))
        state.moveLeft()
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .denominator)], offset: 1))
        state.moveLeft()
        state.moveLeft()
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .numerator)], offset: 1))
        state.moveLeft()
        state.moveLeft()
        XCTAssertEqual(state.cursor, MathCursor(offset: 0))
        XCTAssertFalse(state.moveLeft())

        state = MathEditorState(source: "root(8; 3)")
        state.moveToStart()
        state.moveRight()
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .index)], offset: 0))
        state.moveRight()
        state.moveRight()
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .radicand)], offset: 0))
    }

    func testVerticalMoves() {
        var state = MathEditorState(source: "1/23")
        state.setCursor(MathCursor(path: [MathPathStep(item: 0, slot: .denominator)], offset: 2))
        XCTAssertTrue(state.moveUp())
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .numerator)], offset: 1))
        XCTAssertFalse(state.moveUp())
        XCTAssertTrue(state.moveDown())
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .denominator)], offset: 1))
        XCTAssertFalse(state.moveDown())

        // Base ↔ exponent.
        state = MathEditorState(source: "x²+1")
        state.setCursor(MathCursor(offset: 1))
        XCTAssertTrue(state.moveUp())
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 1, slot: .exponent)], offset: 0))
        XCTAssertTrue(state.moveDown())
        XCTAssertEqual(state.cursor, MathCursor(offset: 2))
        XCTAssertTrue(state.moveUp())
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 1, slot: .exponent)], offset: 1))

        // Index ↔ radicand.
        state = MathEditorState(source: "root(8; 3)")
        state.setCursor(MathCursor(path: [MathPathStep(item: 0, slot: .radicand)], offset: 1))
        XCTAssertTrue(state.moveUp())
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .index)], offset: 1))
        XCTAssertTrue(state.moveDown())
        XCTAssertEqual(state.cursor.path.last?.slot, .radicand)

        // An exponent inside a denominator moves up to the numerator.
        state = MathEditorState(source: "a/b^n")
        let exponent = [MathPathStep(item: 0, slot: .denominator), MathPathStep(item: 1, slot: .exponent)]
        state.setCursor(MathCursor(path: exponent, offset: 1))
        XCTAssertTrue(state.moveUp())
        XCTAssertEqual(state.cursor, MathCursor(path: [MathPathStep(item: 0, slot: .numerator)], offset: 1))
    }

    func testCursorPlacement() {
        var state = MathEditorState(source: "a/bc")
        let denominator = [MathPathStep(item: 0, slot: .denominator)]
        XCTAssertTrue(state.setCursor(MathCursor(path: denominator, offset: 9)))
        XCTAssertEqual(state.cursor, MathCursor(path: denominator, offset: 2))
        XCTAssertEqual(state.cursorOffset(at: denominator), 2)
        XCTAssertNil(state.cursorOffset(at: []))
        XCTAssertEqual(state.cursorRow, row("bc"))
        XCTAssertFalse(state.setCursor(MathCursor(path: [MathPathStep(item: 0, slot: .exponent)])))
        XCTAssertFalse(state.setCursor(MathCursor(path: [MathPathStep(item: 4, slot: .numerator)])))
        XCTAssertEqual(state.cursor, MathCursor(path: denominator, offset: 2))
        XCTAssertEqual(state.root.row(at: denominator), row("bc"))

        state = MathEditorState(root: row("ab"), cursor: MathCursor(path: denominator))
        XCTAssertEqual(state.cursor, MathCursor(offset: 2))
    }

    func testEditingInsideNestedRows() {
        var state = MathEditorState(source: "")
        state.insert("a^-t/tau")
        XCTAssertEqual(state.source, "a^(-t/tau)")
        state.moveToEnd()
        state.insert("+1")
        XCTAssertEqual(state.source, "a^(-t/tau)+1")
        let evaluation = NotebookEngine.evaluate("a = 2\nt = 1 s\ntau = 2 s\n" + state.source)
        XCTAssertEqual(evaluation.lines.last?.quantity?.value ?? 0, pow(2, -0.5) + 1, accuracy: 1e-12)
    }

    /// Random edits never break the cursor, and what they write reads back to
    /// a tree that writes the same value again.
    func testRandomEditingIsStable() {
        var generator = RandomLayout(seed: 42)
        let keys = Array("ab2 3+-*/^()√²,!=")
        for _ in 0..<400 {
            var state = MathEditorState(source: "")
            for _ in 0..<Int.random(in: 1...14, using: &generator) {
                switch Int.random(in: 0..<12, using: &generator) {
                case 0: state.deleteBackward()
                case 1: state.moveLeft()
                case 2: state.moveRight()
                case 3: state.moveUp()
                case 4: state.moveDown()
                case 5: state.insertRoot()
                default: state.insert(String(keys.randomElement(using: &generator)!))
                }
                XCTAssertNotNil(state.root.row(at: state.cursor.path))
                XCTAssertLessThanOrEqual(state.cursor.offset, state.cursorRow.items.count)
            }
            let source = state.source
            let reread = MathEditorState(source: source).source
            let sheet = "a = 3\nb = 5\n"
            let first = NotebookEngine.evaluate(sheet + source).lines.last
            let second = NotebookEngine.evaluate(sheet + reread).lines.last
            XCTAssertEqual(first?.status, second?.status, "\(source) → \(reread)")
            if let value = first?.quantity?.value, let other = second?.quantity?.value, value.isFinite {
                XCTAssertEqual(other, value, accuracy: abs(value) * 1e-12, "\(source) → \(reread)")
            }
        }
    }

    /// Random layouts write text that the engine reads with the layout's value.
    func testRandomLayoutsKeepTheirValue() {
        var generator = RandomLayout(seed: 7)
        var checked = 0
        for _ in 0..<1_500 {
            generator.isUndefined = false
            let (row, value) = generator.expression(depth: 2)
            guard !generator.isUndefined, abs(value) < 1e12 else { continue }
            let source = MathEditorState(root: MathRow(row)).source
            let line = NotebookEngine.evaluate("a = 3\nb = 5\n" + source).lines.last
            XCTAssertEqual(line?.status, .success, "\(source): \(line?.message ?? "")")
            XCTAssertEqual(line?.quantity?.value ?? .nan, value, accuracy: max(abs(value), 1) * 1e-9, source)
            // Reading the text back gives a tree of the same value, written the same way from then on.
            let reread = MathEditorState(source: source).source
            XCTAssertEqual(NotebookEngine.evaluate("a = 3\nb = 5\n" + reread).lines.last?.quantity?.value ?? .nan,
                           value, accuracy: max(abs(value), 1) * 1e-9, reread)
            XCTAssertEqual(MathEditorState(source: reread).source, reread, source)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 700)
    }
}

/// Random trees with their mathematical value, `a` = 3 and `b` = 5.
/// Seeded (SplitMix64), so that failures are reproducible.
private struct RandomLayout: RandomNumberGenerator {
    var seed: UInt64
    /// Set when a step leaves the real numbers or divides by (nearly) zero.
    var isUndefined = false

    private mutating func checked(_ value: Double) -> Double {
        if !value.isFinite { isUndefined = true }
        return value
    }

    mutating func next() -> UInt64 {
        seed &+= 0x9E37_79B9_7F4A_7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    private mutating func next(_ count: Int) -> Int { Int(next() % UInt64(count)) }

    /// Products joined by + or −, possibly after a unary minus.
    mutating func expression(depth: Int) -> ([MathItem], Double) {
        var (items, value) = product(depth: depth)
        if next(5) == 0 {
            items = [.symbol("-")] + items
            value = -value
        }
        for _ in 0..<next(depth > 0 ? 3 : 2) {
            let minus = next(2) == 0
            let (term, termValue) = product(depth: depth)
            items += MathRow(text: minus ? " - " : "+").items + term
            value = checked(value + (minus ? -termValue : termValue))
        }
        return (items, value)
    }

    /// Powers joined by `*`, a typed `/` or, before a structure or a group, by juxtaposition.
    private mutating func product(depth: Int) -> ([MathItem], Double) {
        var (items, value) = power(depth: depth)
        for _ in 0..<next(3) {
            let (factor, factorValue) = power(depth: depth)
            let juxtaposed: Bool
            switch factor.first {
            case .symbol("(")?, .fraction?, .radical?, .root?: juxtaposed = next(2) == 0
            default: juxtaposed = false
            }
            if !juxtaposed, next(4) == 0 {
                if abs(factorValue) < 1e-9 { isUndefined = true }
                items += MathRow(text: next(2) == 0 ? "/" : " / ").items + factor
                value = checked(value / factorValue)
            } else {
                items += (juxtaposed ? [] : MathRow(text: next(2) == 0 ? "*" : " * ").items) + factor
                value = checked(value * factorValue)
            }
        }
        return (items, value)
    }

    private mutating func power(depth: Int) -> ([MathItem], Double) {
        let (base, baseValue) = atom(depth: depth)
        guard depth > 0, next(4) == 0 else { return (base, baseValue) }
        let (exponent, exponentValue) = next(2) == 0 ? ([MathItem.symbol("2")], 2) : expression(depth: 0)
        return (base + [.superscript(MathRow(exponent))], checked(pow(baseValue, exponentValue)))
    }

    private mutating func atom(depth: Int) -> ([MathItem], Double) {
        let choice = depth > 0 ? next(9) : next(4)
        switch choice {
        case 0: return (MathRow(text: "a").items, 3)
        case 1: return (MathRow(text: "b").items, 5)
        case 2: return (MathRow(text: "2").items, 2)
        case 3: return (MathRow(text: "0,5").items, 0.5)
        case 4, 5:
            let (numerator, n) = expression(depth: depth - 1), (denominator, d) = expression(depth: depth - 1)
            if abs(d) < 1e-9 { isUndefined = true }
            return ([.fraction(MathRow(numerator), MathRow(denominator))], checked(n / d))
        case 6:
            let (radicand, r) = expression(depth: depth - 1)
            return ([.radical(MathRow(radicand))], checked(r.squareRoot()))
        case 7:
            let (radicand, r) = expression(depth: depth - 1)
            return ([.root(index: MathRow(text: "3"), radicand: MathRow(radicand))], cbrt(r))
        default:
            let (inner, value) = expression(depth: depth - 1)
            return (MathRow(text: "(").items + inner + MathRow(text: ")").items, value)
        }
    }
}
