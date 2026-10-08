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
    @GestureState private var translation = 0.0
    @GestureState private var isDragging = false
    @State private var origin: Double?
    @State private var gestureRange: VariableAdjustmentRange?
    @State private var isHorizontal = false
    @State private var lastSentValue: Double?
    @State private var feedback = 0

    /// A graduation is a distance to drag, not a piece of text: its spacing
    /// stays comfortable at large text sizes instead of doubling the drag per step.
    private var tickSpacing: Double { min(scaledTickSpacing, 24) }

    var body: some View {
        let increased = contrast == .increased
        Canvas { context, size in
            let count = Int(ceil(size.width / tickSpacing / 2)) + 1
            let phase = translation.truncatingRemainder(dividingBy: tickSpacing)
            for index in -count...count {
                let x = size.width / 2 + Double(index) * tickSpacing - phase
                let distance = abs(x - size.width / 2) / max(size.width / 2, 1)
                let opacity = increased ? max(0.45, 1 - distance) : max(0.12, 0.65 * (1 - distance))
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
                           style: StrokeStyle(lineWidth: increased ? 4 : 3, lineCap: .round))
            let dot = CGRect(x: size.width / 2 - 2, y: size.height * 0.08, width: 4, height: 4)
            context.fill(Path(ellipseIn: dot), with: .color(.primary))
        }
        .frame(maxWidth: maxWidth)
        .frame(height: max(44, height))
        .clipShape(Capsule())
        .rulerMaterial()
        .contentShape(Capsule())
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .updating($isDragging) { _, active, _ in active = true }
            .updating($translation) { drag, offset, _ in
                if abs(drag.translation.width) > abs(drag.translation.height) {
                    offset = drag.translation.width
                }
            }
            .onChanged { drag in
                if origin == nil {
                    origin = value
                    gestureRange = range
                    lastSentValue = value
                    isHorizontal = abs(drag.translation.width) > abs(drag.translation.height)
                    onEditingChanged(true)
                }
                guard isHorizontal, let origin, let activeRange = gestureRange else { return }
                let ticks = Int((drag.translation.width / tickSpacing).rounded())
                send(activeRange.adjustedValue(from: origin, steps: ticks))
            }
            .onEnded { _ in resetGesture() })
        .onChange(of: isDragging) { _, active in
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
