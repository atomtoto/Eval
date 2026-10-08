import EvalCore
import SwiftUI

extension View {
    /// Presents a rename alert while `record` is set.
    func sheetRenameAlert(_ record: Binding<SheetRecord?>) -> some View {
        modifier(SheetRenameAlert(record: record))
    }

    /// Asks before deleting `record`; `onDelete` runs after the deletion.
    func sheetDeletionConfirmation(_ record: Binding<SheetRecord?>,
                                   onDelete: @escaping (UUID) -> Void = { _ in }) -> some View {
        modifier(SheetDeletionConfirmation(record: record, onDelete: onDelete))
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

private struct SheetDeletionConfirmation: ViewModifier {
    @Environment(SheetLibrary.self) private var library
    @Binding var record: SheetRecord?
    let onDelete: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(Text("Supprimer « \(record?.displayTitle ?? "") » ?"),
                                isPresented: isPresented, titleVisibility: .visible, presenting: record) { record in
                Button("Supprimer", role: .destructive) {
                    library.deleteSheet(id: record.id)
                    onDelete(record.id)
                }
            } message: { _ in
                Text("Cette feuille sera supprimée de cet appareil.")
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { record != nil }, set: { if !$0 { record = nil } })
    }
}
