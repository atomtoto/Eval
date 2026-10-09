import Foundation

/// Spoken French for assistive technologies, built from the same parser and
/// syntax tree as `MathNotation`: operators become words, fractions announce
/// their numerator and denominator, and units use their catalogue names.
public enum MathSpeech {
    /// Describes one sheet line, or returns `nil` when `MathNotation` would draw
    /// nothing (invalid or incomplete input): callers then read the source itself.
    /// A trailing comment is spoken after a note marker; a comment-only line gives its note.
    public static func description(_ source: String) -> String? {
        guard source.count <= 2_000, !source.contains(where: \.isNewline) else { return nil }
        let line = LineSyntax(source)
        guard line.arrowCount <= 1 else { return nil }
        let note = line.comment.map(noteText).flatMap { $0.isEmpty ? nil : "note : " + $0 }
        let body = line.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return line.arrowRange == nil ? note : nil }

        do {
            var parts = [try sentence(source, line, body)]
            if line.arrowRange != nil {
                guard let target = line.conversion, !target.isEmpty else { return nil }
                parts.append("affiché en " + (try unitPhrase(target, plural: true)))
            }
            // « a égale » announces the value that the app reads next, after any conversion:
            // « v, affiché en kilomètres par heure, égale ». A declared literal already states it.
            if line.requestsResult, line.separatorRange == nil || line.definitionName != nil, !declaresLiteral(source, line) {
                if line.arrowRange == nil { parts[0] += " égale" } else { parts.append("égale") }
            }
            if let note { parts.append(note) }
            return parts.joined(separator: ", ")
        } catch {
            return nil
        }
    }

    /// `m = 80 kg`: a name set to a number with units, whose sentence already says its value.
    private static func declaresLiteral(_ source: String, _ line: LineSyntax) -> Bool {
        guard line.definitionName != nil, line.separatorCount == 1, let separator = line.separatorRange else { return false }
        let value = source[separator.upperBound..<line.bodyRange.upperBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parser = try? ExpressionParser(value), let expression = try? parser.parse() else { return false }
        return AdjustableVariable.isLiteralWithUnits(expression)
    }

    private static func sentence(_ source: String, _ line: LineSyntax, _ body: String) throws -> String {
        guard let separator = line.separatorRange else { return try speak(body) }
        guard line.separatorCount == 1 else { throw SpeechError.unsupported }
        let leftSource = source[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
        let rightSource = source[separator.upperBound..<line.bodyRange.upperBound].trimmingCharacters(in: .whitespaces)
        guard !leftSource.isEmpty, !rightSource.isEmpty else { throw SpeechError.unsupported }
        let left = try line.definitionName.map { name(for: $0) } ?? speak(leftSource)
        let right: String
        if let unit = line.unknownUnit {
            right = unit.isEmpty ? "inconnue" : "inconnue en " + (try unitPhrase(unit, plural: true))
        } else {
            right = try speak(rightSource)
        }
        return "\(left) \(line.isComparison ? "comparé à" : "égale") \(right)"
    }

    private static func noteText(_ comment: String) -> String {
        var text = Substring(comment)
        while let first = text.first, first == "#" || first == "/" { text = text.dropFirst() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func speak(_ source: String) throws -> String {
        var parser = try ExpressionParser(source)
        return try Speaker().speak(try parser.parse(), depth: 0)
    }

    /// A unit expression such as `km/h` or `MeV/c²`, spoken with catalogue names.
    static func unitPhrase(_ symbol: String, plural: Bool) throws -> String {
        var parser = try ExpressionParser(symbol)
        return try Speaker().unit(try parser.parse(), plural: plural, depth: 0)
    }

    private enum SpeechError: Error { case unsupported, tooDeep }

    // MARK: Names and numbers

    /// A variable name: Greek letters by name, `_` as « indice ».
    static func name(for identifier: String) -> String {
        if identifier == "%" { return "pour cent" }
        if identifier == "hbar" || identifier == "ℏ" { return "h barre" }
        var pieces: [String] = []
        for part in identifier.split(separator: "_", omittingEmptySubsequences: false) {
            var spoken = ""
            for character in part {
                if let greek = greekNames[character] {
                    spoken += (spoken.isEmpty || spoken.hasSuffix(" ") ? "" : " ") + greek + " "
                } else if let digit = subscripts[character] {
                    spoken.append(digit)
                } else {
                    spoken.append(character)
                }
            }
            pieces.append(spoken.trimmingCharacters(in: .whitespaces))
        }
        return pieces.filter { !$0.isEmpty }.joined(separator: " indice ")
    }

    private static let greekNames: [Character: String] = {
        var table: [Character: String] = ["µ": "mu", "Ω": "oméga"]
        for (spelling, letter) in MathNotation.greek where spelling != "hbar" {
            if let character = letter.first, spelling.first?.isLowercase == true || table[character] == nil {
                table[character] = spelling
            }
        }
        return table
    }()

    private static let subscripts: [Character: Character] = [
        "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4", "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9"
    ]

    private static let superscriptDigits: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9"
    ]

    /// `QuantityFormatter.number` read aloud: signs and powers of ten are spelled out.
    static func number(_ value: Double, digits: Int = QuantityFormatter.significantDigits) -> String {
        let text = QuantityFormatter.number(value, significantDigits: digits)
        switch text {
        case "∞": return "infini"
        case "−∞": return "moins l’infini"
        default: break
        }
        let parts = text.components(separatedBy: " × 10")
        var spoken = signed(parts[0])
        if parts.count == 2 {
            let exponent = parts[1].map { $0 == "⁻" ? "-" : String(superscriptDigits[$0] ?? $0) }.joined()
            spoken += " fois 10 puissance " + signed(exponent)
        }
        return spoken
    }

    private static func signed(_ text: String) -> String {
        text.hasPrefix("-") || text.hasPrefix("−") ? "moins " + text.dropFirst() : text
    }

    /// French writes the plural from two units on: 1,5 mètre, 2 mètres.
    static func isPlural(_ value: Double) -> Bool { abs(value) >= 2 }

    // MARK: Units

    private static let feminineUnits: Set<String> = [
        "seconde", "minute", "heure", "année", "année-lumière", "calorie", "atmosphère normale",
        "livre", "livre-force", "mole", "candela", "partie par million"
    ]

    /// The catalogue name of a unit symbol, lowercase, in the plural when asked.
    static func unitName(_ symbol: String, plural: Bool) -> (name: String, feminine: Bool) {
        guard let definition = UnitCatalog.lookup(symbol) else { return (name(for: symbol), false) }
        let singular = definition.name.lowercased()
        var base = singular
        if !feminineUnits.contains(base), let prefix = UnitCatalog.prefixes.first(where: { singular.hasPrefix($0.name) }) {
            base = String(singular.dropFirst(prefix.name.count))
        }
        return (plural ? pluralized(singular) : singular, feminineUnits.contains(base))
    }

    private static let irregularPlurals = [
        "pour cent": "pour cent", "atmosphère normale": "atmosphères normales",
        "partie par million": "parties par million"
    ]

    private static func pluralized(_ name: String) -> String {
        if let plural = irregularPlurals[name] { return plural }
        // Only the first word of « tour par minute » or « année-lumière » varies.
        let end = name.firstIndex { $0 == " " || $0 == "-" } ?? name.endIndex
        let word = name[..<end]
        let plural = word.last.map { "sxz".contains($0) } == true ? String(word) : word + "s"
        return plural + name[end...]
    }

    /// « carré », « cube » or « puissance n » after a unit name.
    static func powerWords(_ exponent: Double, feminine: Bool, plural: Bool) -> String {
        let s = plural ? "s" : ""
        if exponent == 2 { return (feminine ? "carrée" : "carré") + s }
        if exponent == 3 { return "cube" + s }
        return "puissance " + number(exponent, digits: QuantityFormatter.preciseDigits)
    }

    // MARK: Syntax tree

    private struct Speaker {
        func speak(_ expression: Expression, depth: Int) throws -> String {
            guard depth <= 200 else { throw SpeechError.tooDeep }
            switch expression {
            case .number(let value):
                return MathSpeech.number(value, digits: QuantityFormatter.preciseDigits)
            case .identifier(let name):
                return MathSpeech.name(for: name)
            case .unit(let symbol):
                return MathSpeech.unitName(symbol, plural: false).name
            case .compactUnits(let units):
                return try unit(units, plural: false, depth: depth + 1)
            case .unary(let operation, let argument):
                let grouped = isSum(argument) || isUnary(argument)
                return (operation == .minus ? "moins " : "plus ") + (try operand(argument, group: grouped, depth: depth))
            case .factorial(let argument):
                return try operand(argument, group: !isAtom(argument), depth: depth) + " factorielle"
            case .function(let name, let arguments):
                return try call(name, arguments, depth: depth)
            case .binary(let operation, let left, let right):
                return try binary(operation, left, right, depth: depth)
            }
        }

        private func binary(_ operation: Expression.BinaryOperator, _ left: Expression, _ right: Expression,
                            depth: Int) throws -> String {
            // 45° is a number and the degree symbol, written without a space.
            var isDegree = false
            if case .identifier("°") = right { isDegree = true }
            if operation == .multiply, left.isNumericExpression, isDegree || MathNotation.isUnitExpression(right) {
                return try quantity(left, right, depth: depth)
            }
            switch operation {
            case .add, .subtract:
                let rhs = try operand(right, group: isSum(right) || isUnary(right) || isMultiple(right), depth: depth)
                let lhs = try operand(left, group: isMultiple(left), depth: depth)
                return lhs + (operation == .add ? " plus " : " moins ") + rhs
            case .multiply:
                let lhs = try operand(left, group: isSum(left) || isMultiple(left), depth: depth)
                let rhs = try operand(right, group: isSum(right) || isUnary(right) || isMultiple(right), depth: depth)
                return lhs + " fois " + rhs
            case .divide:
                if isSimple(left), isSimple(right) {
                    return try speak(left, depth: depth + 1) + " sur " + (try speak(right, depth: depth + 1))
                }
                return "fraction, numérateur : " + (try speak(left, depth: depth + 1))
                    + " ; dénominateur : " + (try speak(right, depth: depth + 1)) + " ; fin de fraction"
            case .power:
                let base = try operand(left, group: !isPlainAtom(left), depth: depth)
                switch right {
                case .number(2): return base + " au carré"
                case .number(3): return base + " au cube"
                default:
                    let signedAtom: Bool
                    if case .unary(.minus, let inner) = right { signedAtom = isPlainAtom(inner) } else { signedAtom = false }
                    return base + " puissance " + (try operand(right, group: !isPlainAtom(right) && !signedAtom, depth: depth))
                }
            }
        }

        /// `5 m/s`: the number and its unit side by side, with the unit in the
        /// plural from two on.
        private func quantity(_ amount: Expression, _ units: Expression, depth: Int) throws -> String {
            let value = (try? NotebookEngine.standaloneQuantity(amount))?.value ?? 1
            let number = try operand(amount, group: isSum(amount) || isMultiple(amount) || isUnary(amount), depth: depth)
            return number + " " + (try unit(units, plural: MathSpeech.isPlural(value), depth: depth + 1))
        }

        /// A unit expression: « mètre par seconde carrée ». Only the numerator takes the plural.
        func unit(_ expression: Expression, plural: Bool, depth: Int) throws -> String {
            guard depth <= 200 else { throw SpeechError.tooDeep }
            switch expression {
            case .unit(let symbol), .identifier(let symbol):
                return MathSpeech.unitName(symbol, plural: plural).name
            case .compactUnits(let units):
                return try unit(units, plural: plural, depth: depth + 1)
            case .binary(.multiply, let left, let right):
                return try unit(left, plural: plural, depth: depth + 1) + " " + (try unit(right, plural: plural, depth: depth + 1))
            case .binary(.divide, let left, let right):
                let denominator = "par " + (try unit(right, plural: false, depth: depth + 1))
                if case .number(1) = left { return denominator }
                return try unit(left, plural: plural, depth: depth + 1) + " " + denominator
            case .binary(.power, let base, let exponent) where exponent.isNumericExpression:
                let value = (try? NotebookEngine.standaloneQuantity(exponent))?.value ?? 1
                switch base {
                case .unit(let symbol), .identifier(let symbol):
                    let (name, feminine) = MathSpeech.unitName(symbol, plural: plural)
                    return name + " " + MathSpeech.powerWords(value, feminine: feminine, plural: plural)
                default:
                    break
                }
            default:
                break
            }
            return try speak(expression, depth: depth + 1)
        }

        private func call(_ name: String, _ arguments: [Expression], depth: Int) throws -> String {
            if arguments.count == 1 {
                guard let phrase = Self.phrases[name] else { throw SpeechError.unsupported }
                return phrase + " " + (try operand(arguments[0], group: !isAtom(arguments[0]) || isPower(arguments[0]), depth: depth))
            }
            let list = try arguments.map { try speak($0, depth: depth + 1) }
            switch name {
            case "min", "max":
                return (name == "min" ? "minimum de " : "maximum de ") + Self.enumeration(list)
            case "atan2":
                return "arc tangente à deux arguments de " + Self.enumeration(list)
            case "root":
                let index = arguments[1]
                if case .number(let n) = index, let ordinal = Self.ordinals[n] {
                    return "racine \(ordinal) de " + (try operand(arguments[0], group: !isAtom(arguments[0]), depth: depth))
                }
                return "racine d’indice " + list[1] + " de " + (try operand(arguments[0], group: !isAtom(arguments[0]), depth: depth))
            case "log":
                return "logarithme de " + (try operand(arguments[0], group: !isAtom(arguments[0]), depth: depth))
                    + " en base " + (try operand(arguments[1], group: !isAtom(arguments[1]), depth: depth))
            default:
                throw SpeechError.unsupported
            }
        }

        private static let phrases = [
            "sqrt": "racine carrée de", "cbrt": "racine cubique de", "abs": "valeur absolue de",
            "sin": "sinus de", "cos": "cosinus de", "tan": "tangente de",
            "asin": "arc sinus de", "acos": "arc cosinus de", "atan": "arc tangente de",
            "sinh": "sinus hyperbolique de", "cosh": "cosinus hyperbolique de", "tanh": "tangente hyperbolique de",
            "exp": "exponentielle de", "ln": "logarithme népérien de",
            "log": "logarithme décimal de", "log10": "logarithme décimal de",
            "floor": "partie entière de", "ceil": "plafond de", "round": "arrondi de"
        ]

        private static let ordinals: [Double: String] = [
            2: "deuxième", 3: "troisième", 4: "quatrième", 5: "cinquième",
            6: "sixième", 7: "septième", 8: "huitième", 9: "neuvième", 10: "dixième"
        ]

        private static func enumeration(_ items: [String]) -> String {
            items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " et " + items[items.count - 1]
        }

        /// Speaks an operand, between « parenthèse » and « fin de parenthèse » when
        /// the source's grouping would otherwise be lost.
        private func operand(_ expression: Expression, group: Bool, depth: Int) throws -> String {
            let text = try speak(expression, depth: depth + 1)
            return group ? "parenthèse " + text + " fin de parenthèse" : text
        }

        // MARK: Shapes

        private func isSum(_ e: Expression) -> Bool {
            switch e {
            case .binary(.add, _, _), .binary(.subtract, _, _): return true
            default: return false
            }
        }

        private func isUnary(_ e: Expression) -> Bool {
            if case .unary = e { return true }
            return false
        }

        private func isPower(_ e: Expression) -> Bool {
            if case .binary(.power, _, _) = e { return true }
            return false
        }

        /// A call with several arguments, which would swallow what follows it.
        private func isMultiple(_ e: Expression) -> Bool {
            if case .function(_, let arguments) = e { return arguments.count > 1 }
            return false
        }

        private func isQuantity(_ e: Expression) -> Bool {
            if case .binary(.multiply, let left, let right) = e {
                return left.isNumericExpression && MathNotation.isUnitExpression(right)
            }
            return false
        }

        /// A name, a number or a unit: nothing to group, in any position.
        private func isPlainAtom(_ e: Expression) -> Bool {
            switch e {
            case .number, .identifier, .unit, .compactUnits: return true
            default: return false
            }
        }

        /// Reads as one item after « de »: plain atoms, quantities and calls on one argument.
        private func isAtom(_ e: Expression) -> Bool {
            if case .function(_, let arguments) = e { return arguments.count == 1 }
            return isPlainAtom(e) || isQuantity(e)
        }

        /// Fits on either side of « sur » without a numerator and denominator announcement.
        private func isSimple(_ e: Expression) -> Bool {
            if isAtom(e) { return true }
            switch e {
            case .factorial(let argument): return isPlainAtom(argument)
            case .binary(.power, let base, let exponent): return isPlainAtom(base) && isPlainAtom(exponent)
            default: return false
            }
        }
    }
}

// MARK: - Results

extension Dimension {
    /// The dimension as base units read aloud, such as « kilogramme mètre carré par seconde carrée ».
    public var spokenDescription: String { spoken(plural: false) }

    func spoken(plural: Bool) -> String {
        let units: [(name: String, feminine: Bool, exponent: Double)] = [
            ("kilogramme", false, mass), ("mètre", false, length), ("seconde", true, time),
            ("ampère", false, electricCurrent), ("kelvin", false, temperature),
            ("mole", true, amount), ("candela", true, luminousIntensity)
        ]
        func words(_ unit: (name: String, feminine: Bool, exponent: Double), plural: Bool) -> String {
            let exponent = abs(unit.exponent)
            let name = unit.name + (plural ? "s" : "")
            guard abs(exponent - 1) > 1e-10 else { return name }
            let rounded = abs(exponent - exponent.rounded()) <= 1e-10 ? exponent.rounded() : exponent
            return name + " " + MathSpeech.powerWords(rounded, feminine: unit.feminine, plural: plural)
        }
        let numerator = units.filter { $0.exponent > 1e-10 }.map { words($0, plural: plural) }
        let denominator = units.filter { $0.exponent < -1e-10 }.map { words($0, plural: false) }
        if numerator.isEmpty && denominator.isEmpty { return "sans dimension" }
        let top = numerator.joined(separator: " ")
        return denominator.isEmpty ? top : (top.isEmpty ? "" : top + " ") + "par " + denominator.joined(separator: " ")
    }
}

extension QuantityFormatter {
    /// The result of `string(_:)` as words: « 3,01 fois 10 puissance 11 joules ».
    public static func spokenString(_ quantity: Quantity) -> String {
        let value = MathSpeech.number(quantity.value)
        guard !quantity.dimension.isDimensionless else { return value }
        let plural = MathSpeech.isPlural(quantity.value)
        if let symbol = UnitCatalog.preferredSymbol(for: quantity.dimension),
           let unit = try? MathSpeech.unitPhrase(symbol, plural: plural) {
            return value + " " + unit
        }
        return value + " " + quantity.dimension.spoken(plural: plural)
    }

    /// The result of `string(_:in:)` as words, in the requested display unit.
    public static func spokenString(_ quantity: Quantity, in unit: DisplayUnit?) -> String {
        guard let unit else { return spokenString(quantity) }
        let value = quantity.value / unit.scale
        let words = (try? MathSpeech.unitPhrase(unit.symbol, plural: MathSpeech.isPlural(value))) ?? unit.symbol
        return MathSpeech.number(value) + " " + words
    }
}

extension EvaluatedLine {
    /// The result read aloud, in the line's display unit.
    public var spokenResult: String? {
        if let solutions { return solutions.spoken(in: displayUnit) }
        return quantity.map { QuantityFormatter.spokenString($0, in: displayUnit) }
    }

    /// `dimensionMessage` read aloud: « Homogène : kilogramme mètre carré par seconde carrée ».
    public var spokenDimensionMessage: String? {
        guard dimensionMessage != nil, let quantity else { return nil }
        return (isHomogeneous ? "Homogène" : "Dimension") + " : " + quantity.dimension.spokenDescription
    }
}

extension ResultText {
    /// `line(source:value:)` read aloud: « E égale 3 joules », « m fois v égale 400 kilogrammes mètres par seconde ».
    /// `spokenValue` is the value in words, such as `EvaluatedLine.spokenResult`.
    public static func spokenLine(source: String, spokenValue: String) -> String {
        let content = LineSyntax(source).body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return spokenValue }
        let label = declaredName(in: source) ?? content
        let spokenLabel = MathSpeech.description(label) ?? label
        return "\(spokenLabel) \(content.contains("==") ? "donne" : "égale") \(spokenValue)"
    }
}
