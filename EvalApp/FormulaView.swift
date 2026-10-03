import EvalCore
import SwiftUI

/// Mathematical notation is app content, composed from native SwiftUI text and layout.
struct FormulaView: View {
    let source: String
    @ScaledMetric(relativeTo: .title3) private var pointSize = 21.0

    var body: some View {
        if let formula = MathNotation.formula(source) {
            VStack(alignment: .leading, spacing: 4) {
                ScrollView(.horizontal) {
                    FormulaContent(formula: formula, pointSize: pointSize)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                if let comment = trailingComment {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(source)
        } else {
            Text(source)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trailingComment: String? {
        let markers = [source.firstIndex(of: "#"), source.range(of: "//")?.lowerBound].compactMap { $0 }
        guard let marker = markers.min() else { return nil }
        return String(source[marker...])
    }
}

private struct FormulaContent: View {
    let formula: MathFormula
    let pointSize: Double

    var body: some View {
        content
            .foregroundStyle(.primary)
    }

    // Type erasure breaks the recursive view type while keeping the notation tree recursive.
    private var content: AnyView {
        switch formula {
        case .atom(let value):
            return AnyView(Text(value).font(.system(size: pointSize, design: .serif)))
        case .row(let items):
            return AnyView(HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    FormulaContent(formula: item, pointSize: pointSize)
                }
            })
        case .fraction(let numerator, let denominator):
            return AnyView(VStack(spacing: pointSize * 0.12) {
                FormulaContent(formula: numerator, pointSize: pointSize * 0.9)
                    .padding(.horizontal, pointSize * 0.22)
                Rectangle()
                    .frame(height: 1)
                FormulaContent(formula: denominator, pointSize: pointSize * 0.9)
                    .padding(.horizontal, pointSize * 0.22)
            }
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, pointSize * 0.1))
        case .power(let base, let exponent):
            return AnyView(HStack(alignment: .top, spacing: pointSize * 0.06) {
                FormulaContent(formula: base, pointSize: pointSize)
                    .padding(.top, pointSize * 0.3)
                FormulaContent(formula: exponent, pointSize: pointSize * 0.65)
            })
        case .radical(let radicand):
            return AnyView(HStack(alignment: .center, spacing: 0) {
                Text("√")
                    .font(.system(size: pointSize * 1.3, design: .serif))
                VStack(spacing: pointSize * 0.05) {
                    Rectangle().frame(height: 1)
                    FormulaContent(formula: radicand, pointSize: pointSize)
                        .padding(.horizontal, pointSize * 0.1)
                }
                .fixedSize(horizontal: true, vertical: true)
            })
        case .parentheses(let expression):
            return AnyView(HStack(spacing: 0) {
                Text("(").font(.system(size: pointSize, design: .serif))
                FormulaContent(formula: expression, pointSize: pointSize)
                Text(")").font(.system(size: pointSize, design: .serif))
            })
        }
    }
}
