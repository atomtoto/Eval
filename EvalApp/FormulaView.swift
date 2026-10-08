import EvalCore
import SwiftUI

/// Mathematical notation is app content, composed from native SwiftUI text and layout.
struct FormulaView: View {
    let source: String
    @ScaledMetric(relativeTo: .title3) private var pointSize = 21.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let formula = MathNotation.formula(source) {
            VStack(alignment: .leading, spacing: 4) {
                // The formula scrolls only when it is wider than the row, so the
                // row’s swipe actions stay available for ordinary formulas. Only
                // then does its scroll indicator show, and flash once on appearing.
                ViewThatFits(in: .horizontal) {
                    content(formula)
                    VStack(alignment: .leading, spacing: 4) {
                        ScrollView(.horizontal) { content(formula) }
                            .scrollIndicatorsFlash(onAppear: true)
                        if dynamicTypeSize.isAccessibilitySize {
                            // The whole line stays readable where the notation is cut off.
                            Text(source)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let comment = trailingComment {
                    Text(comment)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MathSpeech.description(source) ?? source)
        } else {
            Text(source)
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func content(_ formula: MathFormula) -> some View {
        FormulaContent(formula: formula, pointSize: pointSize)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.vertical, 4)
    }

    private var trailingComment: String? {
        let markers = [source.firstIndex(of: "#"), source.range(of: "//")?.lowerBound].compactMap { $0 }
        guard let marker = markers.min() else { return nil }
        return String(source[marker...])
    }
}

extension VerticalAlignment {
    /// The line that the operators and fraction bars of a formula sit on, a
    /// little above the baseline of the text. Every node of a formula reports
    /// where its own axis is, and a row aligns them all on one line.
    private enum MathAxis: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    fileprivate static let mathAxis = VerticalAlignment(MathAxis.self)
}

private struct FormulaContent: View {
    let formula: MathFormula
    let pointSize: Double

    var body: some View {
        content
            .foregroundStyle(.primary)
    }

    /// Text whose math axis lies a quarter of its size above the baseline.
    private func text(_ value: String, size: Double? = nil) -> some View {
        let size = size ?? pointSize
        return Text(value)
            .font(.system(size: size, design: .serif))
            .alignmentGuide(.mathAxis) { $0[.firstTextBaseline] - size * 0.25 }
    }

    // Type erasure breaks the recursive view type while keeping the notation tree recursive.
    private var content: AnyView {
        switch formula {
        case .atom(let value):
            return AnyView(text(value))
        case .row(let items):
            return AnyView(HStack(alignment: .mathAxis, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    FormulaContent(formula: item, pointSize: pointSize)
                }
            })
        case .fraction(let numerator, let denominator):
            return AnyView(VStack(spacing: pointSize * 0.12) {
                FormulaContent(formula: numerator, pointSize: pointSize * 0.9)
                    .padding(.horizontal, pointSize * 0.22)
                // The bar is the axis of the fraction.
                Rectangle()
                    .frame(height: 1)
                    .alignmentGuide(.mathAxis) { $0[VerticalAlignment.center] }
                FormulaContent(formula: denominator, pointSize: pointSize * 0.9)
                    .padding(.horizontal, pointSize * 0.22)
            }
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, pointSize * 0.1))
        case .power(let base, let exponent):
            // The exponent is lifted by its own alignment, never by moving the base,
            // so the base stays on the line of its neighbours.
            return AnyView(HStack(alignment: .mathAxis, spacing: pointSize * 0.06) {
                FormulaContent(formula: base, pointSize: pointSize)
                FormulaContent(formula: exponent, pointSize: pointSize * 0.65)
                    .alignmentGuide(.mathAxis) { $0.height + pointSize * 0.15 }
            })
        case .radical(let radicand):
            return AnyView(radical(radicand))
        case .root(let index, let radicand):
            // The index sits above the hook of the sign, in the room the sign already leaves.
            return AnyView(radical(radicand)
                .overlay(alignment: .topLeading) {
                    FormulaContent(formula: index, pointSize: pointSize * 0.55)
                        .fixedSize()
                        .padding(.leading, pointSize * 0.04)
                })
        case .parentheses(let expression):
            return AnyView(HStack(alignment: .mathAxis, spacing: 0) {
                text("(")
                FormulaContent(formula: expression, pointSize: pointSize)
                text(")")
            })
        }
    }
}

extension FormulaContent {
    /// The sign is drawn behind the radicand, so it stretches with it.
    fileprivate func radical(_ radicand: MathFormula) -> some View {
        FormulaContent(formula: radicand, pointSize: pointSize)
            .padding(.leading, pointSize * 0.75)
            .padding(.trailing, pointSize * 0.1)
            .padding(.top, 3)
            .background { RadicalSign(hookWidth: pointSize * 0.7).stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)) }
    }
}

/// The radical sign: a short hook, a long downstroke, then the bar over the radicand.
private struct RadicalSign: Shape {
    let hookWidth: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.62))
        path.addLine(to: CGPoint(x: rect.minX + hookWidth * 0.25, y: rect.maxY * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + hookWidth * 0.55, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.minX + hookWidth, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
        return path
    }
}
