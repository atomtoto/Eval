import SwiftUI

extension Color {
    /// The page behind the rows of a sheet: a warm cream in light mode.
    static let warmBackground = Color(.warmBackground)
    /// The rows and cards on that page: a slightly lighter warm white.
    static let warmRow = Color(.warmRow)
}

/// The warm page of the sheets: cream behind lighter rows, with the native lists,
/// sections and separators. Only in light mode, and only with the setting « Fond chaud »;
/// the dark appearance stays the system's, and so does everything else.
private struct WarmPage: ViewModifier {
    @AppStorage(WarmBackgroundSetting.storageKey) private var isEnabled = true
    @Environment(\.colorScheme) private var colorScheme

    private var isWarm: Bool { isEnabled && colorScheme == .light }

    func body(content: Content) -> some View {
        // The same modifiers either way, so that the setting does not rebuild the list.
        content
            .scrollContentBackground(isWarm ? .hidden : .automatic)
            .listRowBackground(isWarm ? Color.warmRow : nil)
            // The page runs under the keyboard and every safe area, so that no white shows around them.
            .background { (isWarm ? Color.warmBackground : Color.clear).ignoresSafeArea(.all) }
    }
}

extension View {
    /// Gives a list or form the warm page, when the setting asks for it.
    func warmPage() -> some View {
        modifier(WarmPage())
    }
}
