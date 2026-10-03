import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Une feuille, toutes vos formules") {
                    Text("Écrivez une formule ou une déclaration par ligne. Les résultats se mettent à jour pendant la saisie.")
                    example("d = 0,5 * a * t²\na = 7,2 m/s²\nt = 3 s\nd", explanation: "La formule peut précéder ses variables. Ici, d vaut 32,4 m.")
                    Text("Les variables peuvent dépendre d’autres variables. Chaque nom doit être défini une seule fois ; les dépendances circulaires sont signalées.")
                }

                Section("Écrire avec des fractions") {
                    Text("Le mode Formules présente les lignes en notation mathématique. Touchez une ligne pour l’éditer, ou utilisez Ajouter une formule.")
                    Text("Les boutons Fraction, Puissance et Racine carrée ouvrent des champs dédiés. Pour une fraction, saisissez le numérateur et le dénominateur ; l’aperçu est mis à jour pendant la saisie.")
                    Text("La construction peut remplacer l’expression ou se combiner avec elle par une addition, une multiplication ou une autre opération. Le nom déclaré, comme E =, est conservé.")
                    Text("Le mode Texte permet de modifier toute la feuille. Une division écrite avec / apparaît comme une fraction dans le mode Formules et dans les résultats.")
                }

                Section("Choisir les résultats") {
                    Text("Dans la section Résultats, touchez Choisir et activez les lignes à afficher. Vous pouvez aussi activer Afficher dans Résultats dans l’éditeur d’une formule.")
                    Text("Les lignes masquées sont toujours calculées pour les autres formules. Le choix est sauvegardé et suit les lignes lorsqu’elles sont déplacées ou modifiées. Les nouvelles lignes ajoutées en mode Texte commencent masquées.")
                    Text("Les erreurs restent signalées sur les lignes en mode Formules, et dans À corriger en mode Texte, même si leur résultat est masqué.")
                }

                Section("Valeurs et unités") {
                    example("v = 72 km/h\nt = 2 s\nv * t", explanation: "Les unités sont converties en SI : le résultat est 40 m.")
                    Text("La virgule et le point sont acceptés pour les décimales. La notation scientifique s’écrit 1,5e-3. Les noms et symboles respectent les majuscules.")
                    Text("Séparez la valeur et son unité par un espace : 5 m désigne le mètre même si m est aussi une variable. Pour les unités composées, gardez les opérateurs sans espaces : 2 kg*m/s². Dans une formule, utilisez * entre les variables et espacez les opérateurs autour d’une quantité : 2 m/s² * m.")
                    Text("Une valeur sans unité est sans dimension. Pour vérifier une formule physique, attribuez les unités aux grandeurs concernées.")
                }

                Section("Ajuster une variable en glissant") {
                    Text("Un curseur apparaît sous les déclarations numériques, comme a = 7,2 m/s². Glissez vers la gauche ou la droite pour changer la valeur et recalculer les résultats. En mode Texte, ces curseurs se trouvent dans Ajuster les variables.")
                    Text("Le bouton de réglage du curseur permet de choisir le minimum, le maximum et le pas. Les réglages sont sauvegardés avec la feuille. Les unités et les commentaires sont conservés ; une valeur en km/h reste saisie en km/h.")
                    Text("Les variables calculées, comme E = 0,5 * m * v², se modifient dans l’éditeur de formules. Leurs valeurs suivent automatiquement celles des variables ajustées.")
                }

                Section("Constantes reconnues") {
                    example("h * c / lambda\nlambda = 550 nm", explanation: "h et c sont reconnus et leurs valeurs apparaissent dans « Constantes reconnues ».")
                    Text("Le catalogue Références contient les constantes de physique, de chimie, d’astronomie et de mathématiques. Filtrez par domaine ou cherchez un nom, un symbole ou un identifiant de saisie.")
                    Text("Dépliez une constante pour consulter sa valeur, sa nature et sa source, puis touchez Ajouter à la feuille. Le champ Saisie indique le nom à utiliser dans une formule, par exemple N_A pour la constante d’Avogadro.")
                    Text("Les valeurs sont disponibles hors ligne. Exacte indique une valeur définie ou dérivée d’une définition ; Mesurée indique une valeur expérimentale ; Conventionnelle indique une valeur de référence adoptée, qui peut différer d’une valeur locale ou observée.")
                    Text("Vous pouvez remplacer une constante en déclarant vous-même son identifiant dans la feuille. Les symboles respectent la casse : g est la pesanteur standard, G est la constante gravitationnelle.")
                }

                Section("Homogénéité physique") {
                    example("2 m + 3 s", explanation: "Une longueur et une durée ne peuvent pas être additionnées : Eval signale des dimensions incompatibles.")
                    example("F == m * a\nF = 14,4 N\nm = 2 kg\na = 7,2 m/s²", explanation: "== compare les dimensions et les valeurs des deux membres. Cette relation est homogène et ses valeurs sont égales.")
                    Text("Le signe = déclare une variable lorsque le membre de gauche est un nom. Utilisez == pour vérifier une égalité. Eval évalue les variables définies ; il ne résout pas une équation pour une inconnue.")
                }

                Section("Opérations disponibles") {
                    LabeledContent("Arithmétique", value: "+  −  *  /  ^")
                    LabeledContent("Écriture", value: "×  ÷  ²  ³  ( )")
                    LabeledContent("Fonctions", value: "sqrt, abs, sin, cos, tan, exp, ln, log")
                    example("sqrt(9 m²)\nsin(30 deg)\n2 * pi", explanation: "Les angles sont en radians par défaut ; deg permet de saisir des degrés. Les fonctions trigonométriques et logarithmiques exigent un argument sans dimension.")
                    Text("Ajoutez une note avec # ou // en début de ligne.")
                }

                Section("Votre feuille") {
                    Text("La feuille est sauvegardée sur cet appareil. Le menu d’actions permet de la partager, de charger un exemple ou de l’effacer.")
                }
            }
            .navigationTitle("Utiliser Eval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    private func example(_ source: String, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(source).font(.body.monospaced()).textSelection(.enabled)
            Text(explanation).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
