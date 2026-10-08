import SwiftUI

extension View {
    /// Focuses the search field of `.searchable` each time `request` changes,
    /// for a keyboard command. Before iOS 18 the field cannot be focused from code.
    func focusesSearch(on request: Int) -> some View {
        modifier(SearchFocus(request: request))
    }
}

private struct SearchFocus: ViewModifier {
    let request: Int
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .searchFocused($isFocused)
                .onChange(of: request) { isFocused = true }
        } else {
            content
        }
    }
}
