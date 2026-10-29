import EvalCore
import Foundation

/// A formula in mathematical notation (`MathFormula`), as plain nodes for Kotlin.
public struct MathNode: Hashable, Sendable {
    /// `atom`, `row`, `fraction`, `power`, `radical`, `root`, `parentheses` or `value`.
    public let kind: String
    /// The text of an atom; empty for the other kinds.
    public let text: String
    /// A row's items; a fraction's numerator and denominator; a power's base and
    /// exponent; a root's index and radicand; the content of the other kinds.
    public let children: [MathNode]

    public init(kind: String, text: String = "", children: [MathNode] = []) {
        self.kind = kind
        self.text = text
        self.children = children
    }

    /// The notation of a line as iOS draws it, nil when the line has none (a
    /// note, or a formula that does not parse), which then shows as plain text.
    /// Pure: any thread.
    public static func formula(_ source: String) -> MathNode? {
        MathNotation.formula(source).map(MathNode.init(_:))
    }

    init(_ formula: MathFormula) {
        switch formula {
        case .atom(let text): self.init(kind: "atom", text: text)
        case .row(let items): self.init(kind: "row", children: items.map(MathNode.init(_:)))
        case .fraction(let numerator, let denominator):
            self.init(kind: "fraction", children: [MathNode(numerator), MathNode(denominator)])
        case .power(let base, let exponent): self.init(kind: "power", children: [MathNode(base), MathNode(exponent)])
        case .radical(let radicand): self.init(kind: "radical", children: [MathNode(radicand)])
        case .root(let index, let radicand): self.init(kind: "root", children: [MathNode(index), MathNode(radicand)])
        case .parentheses(let content): self.init(kind: "parentheses", children: [MathNode(content)])
        case .value(let content): self.init(kind: "value", children: [MathNode(content)])
        }
    }
}
