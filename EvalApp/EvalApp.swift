import SwiftUI

@main
struct EvalApp: App {
    @StateObject private var notebook = NotebookStore()

    var body: some Scene {
        WindowGroup {
            EvalRootView(notebook: notebook)
        }
    }
}

private struct EvalRootView: View {
    @ObservedObject var notebook: NotebookStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NotebookView(notebook: notebook)
                .tabItem { Label("Calcul", systemImage: "function") }
                .tag(0)

            ReferenceView { symbol in
                notebook.append(symbol)
                selection = 0
            }
            .tabItem { Label("Références", systemImage: "books.vertical") }
            .tag(1)
        }
    }
}
