import EvalCore
import SwiftUI

extension View {
    /// Presents a rename alert while `record` is set.
    func sheetRenameAlert(_ record: Binding<SheetRecord?>) -> some View {
        modifier(SheetRenameAlert(record: record))
    }
}

private struct SheetRenameAlert: ViewModifier {
    @Environment(SheetLibrary.self) private var library
    @Binding var record: SheetRecord?
    @State private var title = ""

    func body(content: Content) -> some View {
        content
            .alert("Renommer la feuille", isPresented: isPresented, presenting: record) { record in
                TextField("Titre", text: $title)
                Button("Annuler", role: .cancel) {}
                Button("Renommer") { library.renameSheet(id: record.id, to: title) }
            } message: { _ in
                Text("Laissez le titre vide pour nommer la feuille d’après sa première note.")
            }
            .onChange(of: record?.id) {
                title = record?.displayTitle ?? ""
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { record != nil }, set: { if !$0 { record = nil } })
    }
}
