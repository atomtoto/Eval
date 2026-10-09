import SwiftUI

/// The number of a line of the sheet. Beside its formula it is a small figure,
/// aligned on its last digit in a column wide enough for three;
/// at accessibility sizes it grows to the size of the formula’s digits and
/// would merge with them, so it becomes « Ligne 2 » above the formula.
struct LineNumberLabel: View {
    let number: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text("Ligne \(number)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // Three hidden digits give every row the same width, which scales with the type size.
            Text("000")
                .hidden()
                .overlay(alignment: .trailing) {
                    Text("\(number)")
                        .accessibilityLabel("Ligne \(number)")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
    }
}
