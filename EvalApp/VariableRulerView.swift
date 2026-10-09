import EvalCore
import SwiftUI

/// A relative ruler keeps its indicator fixed while the graduations move.
/// Public Slider styles move their thumb; this interaction needs a small
/// SwiftUI drawing and gesture, with system materials and accessibility.
struct VariableRulerView: View {
    let value: Double
    let range: VariableAdjustmentRange
    let label: String
    let valueLabel: String
    /// The value and the step as words, with their unit named.
    let spokenValue: String
    let spokenStep: String
    let usesAutomaticStep: Bool
    /// The flag is true for a change made with VoiceOver’s adjustable action,
    /// whose results the sheet then announces.
    let onChangeValue: (Double, Bool) -> Void
    /// Like Slider’s onEditingChanged: true when a gesture or adjustment starts, false when it ends.
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ScaledMetric(relativeTo: .body) private var scaledTickSpacing = 16.0
    @ScaledMetric(relativeTo: .body) private var height = 52.0
    /// The ruler widens with the text so that it keeps about as many graduations in view.
    @ScaledMetric(relativeTo: .body) private var maxWidth = 300.0
    @Environment(\.colorSchemeContrast) private var contrast
    /// The horizontal translation of the drag, locked to the direction of its
    /// first movement. Released, it returns to the nearest graduation with an animation.
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var drag = RulerDrag()
    @State private var origin: Double?
    @State private var gestureRange: VariableAdjustmentRange?
    @State private var isHorizontal = false
    @State private var lastSentValue: Double?
    @State private var feedback = 0

    /// A graduation is a distance to drag, not a piece of text: its spacing
    /// stays comfortable at large text sizes instead of doubling the drag per step.
    private var tickSpacing: Double { min(scaledTickSpacing, 24) }

    /// The drag as the graduations show it: they follow the finger, and stop
    /// where the value reaches a bound. Dragging left increases the value, as on
    /// the dial of Photos.
    private var visibleTranslation: Double {
        let start = origin ?? value
        let activeRange = gestureRange ?? range
        let bounded = min(activeRange.upperBound, max(activeRange.lowerBound, start))
        let towardUpper = (activeRange.upperBound - bounded) / activeRange.step * tickSpacing
        let towardLower = (bounded - activeRange.lowerBound) / activeRange.step * tickSpacing
        return min(towardLower, max(-towardUpper, drag.translation))
    }

    var body: some View {
        let increased = contrast == .increased
        // Only the distance to the nearest graduation is drawn, so the release
        // animates the ruler onto that graduation rather than back to the start.
        let translation = visibleTranslation
        RulerGraduations(phase: translation - (translation / tickSpacing).rounded() * tickSpacing,
                         tickSpacing: tickSpacing, increasedContrast: increased)
            .frame(maxWidth: maxWidth)
            .frame(height: max(44, height))
            .clipShape(Capsule())
            .rulerMaterial()
            .contentShape(Capsule())
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .updating($drag) { gesture, state, _ in
                    if !state.isActive {
                        state.isActive = true
                        state.isHorizontal = abs(gesture.translation.width) > abs(gesture.translation.height)
                    }
                    state.translation = state.isHorizontal ? gesture.translation.width : 0
                }
                .onChanged { gesture in
                    if origin == nil {
                        origin = value
                        gestureRange = range
                        lastSentValue = value
                        isHorizontal = abs(gesture.translation.width) > abs(gesture.translation.height)
                        onEditingChanged(true)
                    }
                    guard isHorizontal, let origin, let activeRange = gestureRange else { return }
                    let steps = Int((-gesture.translation.width / tickSpacing).rounded())
                    send(activeRange.adjustedValue(from: origin, steps: steps))
                }
                .onEnded { _ in resetGesture() })
            .onChange(of: drag.isActive) { _, active in
                if !active { resetGesture() }
            }
            .sensoryFeedback(.selection, trigger: feedback)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(spokenValue)
            // The adjustable trait already tells VoiceOver users to swipe up or down.
            .accessibilityHint(usesAutomaticStep ? "Chaque cran modifie la valeur de \(spokenStep). Pas automatique."
                                                 : "Chaque cran modifie la valeur de \(spokenStep).")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjustOnce(range.adjustedValue(from: value, steps: 1))
                case .decrement: adjustOnce(range.adjustedValue(from: value, steps: -1))
                @unknown default: break
                }
            }
    }

    private func send(_ updated: Double, announcesResults: Bool = false) {
        guard updated != (origin == nil ? value : (lastSentValue ?? value)) else { return }
        lastSentValue = updated
        feedback &+= 1
        onChangeValue(updated, announcesResults)
    }

    /// One accessibility increment is one editing session.
    private func adjustOnce(_ updated: Double) {
        onEditingChanged(true)
        send(updated, announcesResults: true)
        onEditingChanged(false)
    }

    private func resetGesture() {
        if origin != nil { onEditingChanged(false) }
        origin = nil
        gestureRange = nil
        lastSentValue = nil
        isHorizontal = false
    }
}

/// The state of a drag on the ruler, from its first movement.
private struct RulerDrag {
    var isActive = false
    var isHorizontal = false
    var translation = 0.0
}

/// The graduations around the fixed indicator. `phase` shifts them, in points;
/// it is animatable so that a released ruler settles on a graduation.
private struct RulerGraduations: View, Animatable {
    var phase: Double
    let tickSpacing: Double
    let increasedContrast: Bool

    nonisolated var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let count = Int(ceil(size.width / tickSpacing / 2)) + 1
            for index in -count...count {
                let x = size.width / 2 + Double(index) * tickSpacing + phase
                let distance = abs(x - size.width / 2) / max(size.width / 2, 1)
                let opacity = increasedContrast ? max(0.45, 1 - distance) : max(0.12, 0.65 * (1 - distance))
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: size.height * 0.28))
                tick.addLine(to: CGPoint(x: x, y: size.height * 0.72))
                context.stroke(tick, with: .color(.primary.opacity(opacity)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            var indicator = Path()
            indicator.move(to: CGPoint(x: size.width / 2, y: size.height * 0.2))
            indicator.addLine(to: CGPoint(x: size.width / 2, y: size.height * 0.85))
            context.stroke(indicator, with: .color(.primary),
                           style: StrokeStyle(lineWidth: increasedContrast ? 4 : 3, lineCap: .round))
            let dot = CGRect(x: size.width / 2 - 2, y: size.height * 0.08, width: 4, height: 4)
            context.fill(Path(ellipseIn: dot), with: .color(.primary))
        }
    }
}

private extension View {
    @ViewBuilder
    func rulerMaterial() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }
}
