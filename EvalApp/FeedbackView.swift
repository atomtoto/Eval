import SwiftUI

/// Le formulaire de commentaires, poussé depuis les réglages : un message, une adresse
/// e-mail facultative pour la réponse, envoyé à Formspree — ou une issue GitHub, ou un e-mail.
struct FeedbackView: View {
    @Environment(\.openURL) private var openURL
    @State private var model = FeedbackModel()
    @State private var showingLinkError = false

    var body: some View {
        Form {
            Section {
                TextField("Votre commentaire", text: $model.message, axis: .vertical)
                    .lineLimit(5...10)
                    .accessibilityLabel("Message du commentaire")
                TextField("Adresse e-mail (facultative)", text: $model.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Commentaires")
            } footer: {
                Text("Votre message et votre adresse e-mail facultative sont envoyés à Formspree. Indiquez une adresse e-mail si vous souhaitez recevoir une réponse.")
            }
            .disabled(model.isSending)

            Section {
                Button {
                    Task { await model.send() }
                } label: {
                    if model.isSending {
                        ProgressView("Envoi…")
                    } else {
                        Label("Envoyer", systemImage: "paperplane")
                    }
                }
                .disabled(!model.canSend)

                if !model.isConfigured {
                    Text("L’envoi de commentaires n’est pas encore configuré.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                switch model.submissionState {
                case .idle:
                    EmptyView()
                case .success:
                    Label("Votre commentaire a bien été accepté. Merci !", systemImage: "checkmark.circle")
                case .failure:
                    Label("Le commentaire n’a pas pu être envoyé. Veuillez réessayer.", systemImage: "exclamationmark.circle")
                }
            }

            Section {
                Button {
                    open(FeedbackLinks.githubIssue(message: model.message))
                } label: {
                    Label("Ouvrir une issue GitHub", systemImage: "arrow.up.right.square")
                }
                .disabled(FeedbackLinks.githubIssue(message: model.message) == nil || model.isSending)

                if FeedbackLinks.githubIssue(message: model.message) == nil {
                    Text("Le lien GitHub n’a pas pu être préparé pour ce message.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    if let address = FeedbackConfiguration.supportEmail {
                        open(FeedbackLinks.email(message: model.message, address: address))
                    }
                } label: {
                    Label("Envoyer un e-mail", systemImage: "envelope")
                }
                .disabled(emailURL == nil || model.isSending)

                if emailURL == nil {
                    Text(FeedbackConfiguration.supportEmail == nil
                         ? "L’adresse e-mail de contact n’est pas encore configurée."
                         : "Le lien e-mail n’a pas pu être préparé pour ce message.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Autres moyens d’envoyer un commentaire")
            } footer: {
                Text("Vous pouvez aussi ouvrir une issue dans le dépôt GitHub public de l’app.")
            }
        }
        .warmPage()
        .navigationTitle("Commentaires")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isSending)
        .alert("Impossible d’ouvrir le lien", isPresented: $showingLinkError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Vérifiez qu’une app peut ouvrir ce lien, puis réessayez.")
        }
    }

    private var emailURL: URL? {
        guard let address = FeedbackConfiguration.supportEmail else { return nil }
        return FeedbackLinks.email(message: model.message, address: address)
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        openURL(url) { accepted in
            if !accepted { showingLinkError = true }
        }
    }
}
