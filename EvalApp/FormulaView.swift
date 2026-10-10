import EvalCore
import SwiftUI

/// Mathematical notation is app content, composed from native SwiftUI text and layout.
/// An accessory, such as the value of the line, follows the formula on its line
/// and moves under it when the row is too narrow.
struct FormulaView<Accessory: View>: View {
    let source: String
    @ViewBuilder let accessory: Accessory
    @ScaledMetric(relativeTo: .title3) private var pointSize = 21.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(source: String, @ViewBuilder accessory: () -> Accessory) {
        self.source = source
        self.accessory = accessory()
    }

    var body: some View {
        if let formula = MathNotation.formula(source) {
            VStack(alignment: .leading, spacing: 4) {
                // The formula scrolls only when it is wider than the row, so the
                // row’s swipe actions stay available for ordinary formulas. Only
                // then does its scroll indicator show, and flash once on appearing.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .mathAxis, spacing: pointSize * 0.3) {
                        content(formula)
                        styledAccessory
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        content(formula)
                        styledAccessory
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ScrollView(.horizontal) { content(formula) }
                            .scrollIndicatorsFlash(onAppear: true)
                        if dynamicTypeSize.isAccessibilitySize {
                            // The whole line stays readable where the notation is cut off.
                            Text(source)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        styledAccessory
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
            VStack(alignment: .leading, spacing: 4) {
                Text(source)
                    .font(.body.monospaced())
                styledAccessory
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func content(_ formula: MathFormula) -> some View {
        FormulaContent(formula: formula, pointSize: pointSize)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.vertical, 4)
    }

    /// The accessory in the size of the formula, its baseline on the formula’s.
    private var styledAccessory: some View {
        let size = pointSize
        return accessory
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .fixedSize(horizontal: false, vertical: true)
            .alignmentGuide(.mathAxis) { $0[.firstTextBaseline] - size * 0.25 }
    }

    private var trailingComment: String? {
        let markers = [source.firstIndex(of: "#"), source.range(of: "//")?.lowerBound].compactMap { $0 }
        guard let marker = markers.min() else { return nil }
        return String(source[marker...])
    }
}

extension FormulaView where Accessory == EmptyView {
    init(source: String) {
        self.init(source: source) { EmptyView() }
    }
}

/// What the value of an adjustable declaration (`80 kg` in `m = 80 kg`) does in
/// a formula: a long press shows its ruler in a popover anchored to the value; a
/// tap edits the line, like anywhere on the row.
struct FormulaValueInteraction {
    /// True while the ruler of the value is open; the value is then highlighted.
    var isPresented: Binding<Bool>
    var longPress: @MainActor () -> Void
    /// The content of the popover: the ruler.
    var popover: AnyView
}

extension EnvironmentValues {
    @Entry var formulaValueInteraction: FormulaValueInteraction?
    /// Set on the value of a declaration: its digits keep the same width while they change,
    /// so the popover of its ruler, anchored to the value, does not move with each step.
    @Entry var formulaMonospacedDigits = false
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

    static let mathAxis = VerticalAlignment(MathAxis.self)
}

private struct FormulaContent: View {
    let formula: MathFormula
    let pointSize: Double

    @Environment(\.formulaValueInteraction) private var valueInteraction
    @Environment(\.formulaMonospacedDigits) private var monospacedDigits
    @State private var longPresses = 0

    var body: some View {
        content
    }

    /// Text whose math axis lies a quarter of its size above the baseline.
    private func text(_ value: String, size: Double? = nil) -> some View {
        let size = size ?? pointSize
        let font = Font.system(size: size, design: .serif)
        return Text(value)
            .font(monospacedDigits ? font.monospacedDigit() : font)
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
        case .value(let inner):
            return AnyView(value(inner))
        }
    }
}

extension FormulaContent {
    /// The value of an adjustable declaration is tinted and underlined, like the
    /// variables of Notes. Without an interaction it draws like plain text.
    @ViewBuilder
    fileprivate func value(_ inner: MathFormula) -> some View {
        let formula = FormulaContent(formula: inner, pointSize: pointSize)
            .environment(\.formulaMonospacedDigits, true)
        if let interaction = valueInteraction {
            formula
                .foregroundStyle(.tint)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(.tint.opacity(0.5))
                        .frame(height: 1.5)
                        .offset(y: 1)
                }
                .padding(.horizontal, 3)
                .background {
                    if interaction.isPresented.wrappedValue {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.tint.opacity(0.15))
                    }
                }
                .contentShape(.rect)
                // Ahead of the row’s context menu, which a long press elsewhere on the row opens.
                // On iPad the menu wins over a press of 0.35 s, so this one is shorter. A press
                // released early is left to the row, whose tap edits the line.
                .highPriorityGesture(LongPressGesture(minimumDuration: 0.2)
                    .onEnded { _ in
                        longPresses += 1
                        interaction.longPress()
                    })
                .sensoryFeedback(.impact, trigger: longPresses)
                // A bubble on iPhone too, like the menu of a long press.
                .popover(isPresented: interaction.isPresented) {
                    interaction.popover
                        .presentationCompactAdaptation(.popover)
                }
        } else {
            formula
        }
    }

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
struct RadicalSign: Shape {
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
