import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Une feuille, toutes vos formules") {
                    Text("Écrivez une formule ou une déclaration par ligne. Les résultats se mettent à jour pendant la saisie.")
                    example("d = 0,5 * a * t²\na = 7,2 m/s²\nt = 3 s\nd", explanation: "La formule peut précéder ses variables. Ici, d vaut 32,4 m.")
                    Text("Les variables peuvent dépendre d’autres variables. Chaque nom doit être défini une seule fois ; les dépendances circulaires sont signalées. Une note commence par # (titre) ou // (texte secondaire).")
                }

                Section("Vos feuilles") {
                    Text("Chaque feuille est sauvegardée sur cet appareil. La liste Feuilles présente la plus récente en premier ; cherchez-y un titre ou une formule. Sans titre choisi, une feuille porte le nom de sa première note.")
                    Text("Nouvelle feuille (⌘N avec un clavier) crée une feuille vide. Nouvelle à partir d’un exemple propose des feuilles de mécanique, d’électricité, d’optique, de thermodynamique, de physique quantique, d’astronomie et de méthode : un exemple s’ouvre toujours dans une nouvelle feuille, sans remplacer votre travail.")
                    Text("Maintenez une feuille dans la liste pour la renommer, la dupliquer, la partager ou la supprimer. La suppression demande toujours une confirmation.")
                }

                Section("Écrire une formule") {
                    Text("Touchez + pour ajouter une ligne, ou une ligne existante pour l’éditer. Retour enregistre la ligne. L’aperçu se met à jour pendant la saisie.")
                    Text("Les boutons Fraction, Puissance et Racine carrée ouvrent des champs dédiés : saisissez le numérateur et le dénominateur, puis insérez. La construction peut remplacer l’expression ou se combiner avec elle ; le nom déclaré, comme E =, est conservé.")
                    Text("Au-dessus du clavier, la barre de symboles insère + − × ÷ et des parenthèses à l’endroit du curseur. Son menu Insérer ajoute =, ^, ², ³, ⁻¹, √, π, deg, les variables de la feuille, ou ouvre Constantes et unités… (le curseur est suivi à partir d’iOS 18 ; avant, l’insertion se fait en fin de ligne). Terminé ferme le clavier.")
                    Text("Le mode Texte permet de modifier toute la feuille d’un seul tenant. Choisissez le mode dans le menu Actions de la feuille.")
                }

                Section("Choisir les résultats") {
                    Text("En mode Formules, la valeur d’une ligne choisie apparaît sous sa formule. Maintenez une ligne et choisissez Afficher le résultat, ou activez Afficher dans Résultats dans son éditeur. Les nouvelles lignes affichent leur valeur, sauf les déclarations de nombres, que la réglette montre déjà. Une ligne avec une conversion (→ km/h) ou une inconnue (v = ? m/s) affiche toujours sa valeur par défaut.")
                    Text("Choisir les résultats, dans le menu Actions de la feuille, permet de choisir plusieurs lignes à la fois. En mode Texte et dans la colonne Résultats de l’iPad, les valeurs sont regroupées dans la section Résultats ; en mode Texte, elles restent aussi visibles au-dessus du clavier.")
                    Text("Les lignes masquées sont toujours calculées pour les autres formules. Les erreurs restent signalées sur les lignes en mode Formules, et dans À corriger en mode Texte, même si leur résultat est masqué.")
                }

                Section("Valeurs et unités") {
                    example("v = 72 km/h\nt = 2 s\nv * t", explanation: "Les unités sont converties en SI : le résultat est 40 m.")
                    Text("La virgule et le point sont acceptés pour les décimales. La notation scientifique s’écrit 1,5e-3. Les nombres s’affichent sans séparateur de milliers : 1000 J. Les noms et symboles respectent les majuscules.")
                    Text("Séparez la valeur et son unité par un espace : 5 m désigne le mètre même si m est aussi une variable. Pour les unités composées, gardez les opérateurs sans espaces : 2 kg*m/s². Dans une formule, utilisez * entre les variables et espacez les opérateurs autour d’une quantité : 2 m/s² * m.")
                    Text("Une valeur sans unité est sans dimension. Pour vérifier une formule physique, attribuez les unités aux grandeurs concernées. Utilisez le kelvin : °C et °F ne sont pas pris en charge.")
                    Text("Eval connaît aussi atm, Torr, mmHg, mbar, hPa, cal, kcal, Wh, kWh, Ah, Å, ly, pc, ft, mi, Da, lb, jour, an, tr, rpm, %, ppm, ml, cl, kohm… La liste complète se trouve dans Références › Unités.")
                    Text("Les noms t, d, a, u, j, in, kn, psi et G ne sont pas des unités : vous pouvez les utiliser comme variables. Si Eval lit un symbole non déclaré comme une unité (par exemple T comme tesla), il le signale dans Symboles lus comme des unités ; déclarez-le pour en faire une variable.")
                }

                Section("Convertir l’affichage") {
                    example("v = 20 m/s → km/h", explanation: "Écrit à la fin de la ligne, → (ou ->) convertit le résultat : 72 km/h. Les variables restent en SI.")
                    example("m_e*c^2 -> MeV", explanation: "Le résultat s’affiche en 0,510999 MeV.")
                    Text("Maintenez une ligne et choisissez Afficher en, ou utilisez le même sélecteur dans l’éditeur : Eval écrit la flèche pour vous. Unités SI la retire. Le résultat et la valeur copiée suivent l’unité choisie.")
                    Text("Une fréquence en s⁻¹ s’affiche s⁻¹ ; choisissez → Hz, → rad/s ou → tr/min selon l’usage. Les cibles sont des unités ou des constantes, jamais des variables de la feuille : m, h et g désignent donc le mètre, l’heure et le gramme.")
                }

                Section("Fonctions et opérations") {
                    LabeledContent("Arithmétique", value: "+  −  *  /  ^")
                    LabeledContent("Écriture", value: "×  ÷  ²  ³  √  ( )")
                    LabeledContent("Racines, exponentielles", value: "sqrt, cbrt, root, exp, ln, log")
                    LabeledContent("Trigonométrie", value: "sin, cos, tan, asin, acos, atan, atan2")
                    LabeledContent("Autres", value: "sinh, cosh, tanh, abs, min, max, floor, ceil, round")
                    example("sqrt(9 m²)\nsin(30 deg)\n2 * pi", explanation: "Les angles sont en radians par défaut ; deg ou ° permet de saisir des degrés. Les fonctions trigonométriques et logarithmiques exigent un argument sans dimension.")
                    example("max(2,5; 3)", explanation: "Une fonction à plusieurs arguments les sépare par un point-virgule, car la virgule est décimale : le résultat est 3. min, max, root(x; n), log(x; base) et atan2(y; x) fonctionnent ainsi.")
                    example("asin(0,5) → °", explanation: "Les fonctions trigonométriques inverses renvoient des radians ; → ° affiche 30°.")
                    Text("min seul reste la minute : 5 min vaut 300 s. Un nom de fonction peut être une variable (max = 10 m) : c’est un appel seulement suivi de ( comme dans max(a; b).")
                }

                Section("Pourcentage et factorielle") {
                    example("P = 200 W\nP * 15 %", explanation: "35 % vaut 0,35 : le résultat est 30 W. 0,35 -> % affiche 35 %.")
                    example("n = 6\nn!", explanation: "La factorielle d’un entier de 0 à 170 : le résultat est 720.")
                }

                Section("Résoudre une inconnue") {
                    example("E = 1000 J\nm = 80 kg\nv = ? m/s\nE == 0,5 * m * v²", explanation: "v = ? m/s déclare une inconnue : Eval la cherche numériquement. Ici v vaut 5 m/s, avec la note « Autre solution : -5 m/s. », et la relation est vérifiée.")
                    Text("Gardez exactement une relation (==) qui contient l’inconnue, directement ou par vos déclarations. Eval affiche la plus petite solution positive entre 10⁻¹² et 10¹². Ce n’est pas un calcul symbolique : il ne transforme pas l’équation et ne résout qu’une inconnue par relation.")
                }

                Section("Ajuster une variable en glissant") {
                    Text("Une réglette graduée à repère fixe apparaît sous les déclarations numériques, comme a = 7,2 m/s². Glissez vers la gauche ou la droite pour changer la valeur et recalculer les résultats. Le bouton de réglage se trouve à côté de la réglette. En mode Texte, les réglettes se trouvent dans Ajuster les variables.")
                    Text("Le pas suit automatiquement la précision saisie : 6 avance de 1, 8,2 de 0,1 et 8,25 de 0,01. Cette précision est conservée en glissant, même lorsque la valeur atteint un entier.")
                    Text("Le bouton de réglage permet de choisir un minimum, un maximum ou un pas manuel en désactivant Pas automatique. Les réglages sont sauvegardés avec la feuille. Les unités et les commentaires sont conservés ; une valeur en km/h reste saisie en km/h.")
                    Text("Les variables calculées, comme E = 0,5 * m * v², se modifient dans l’éditeur de formules. Leurs valeurs suivent automatiquement celles des variables ajustées.")
                }

                Section("Tracer un résultat") {
                    Text("Maintenez une ligne calculée et choisissez Tracer en fonction de, puis une variable à réglette. Le graphique couvre l’intervalle de la réglette ; modifiez-le avec les réglages de la variable pour tracer une autre plage. Touchez le graphique pour lire une valeur. Les points où le calcul est impossible laissent un trou.")
                }

                Section("Constantes reconnues") {
                    example("h * c / lambda\nlambda = 550 nm", explanation: "h et c sont reconnus et leurs valeurs apparaissent dans « Constantes reconnues ». Le résultat est 3,61172 × 10⁻¹⁹ J.")
                    Text("L’onglet Références contient les constantes de physique, de chimie, d’astronomie et de mathématiques, ainsi que les unités. Basculez entre Constantes et Unités, filtrez par Domaine ou cherchez un nom, un symbole ou un identifiant de saisie.")
                    Text("Touchez une constante pour consulter sa valeur, sa nature et sa source. Glissez une ligne vers la droite, ou maintenez-la, pour Ajouter à la feuille ou copier sa valeur. Le champ Saisie indique le nom à utiliser dans une formule, par exemple N_A pour la constante d’Avogadro.")
                    Text("Exacte indique une valeur définie ou dérivée d’une définition ; Mesurée indique une valeur expérimentale ; Conventionnelle indique une valeur de référence adoptée, qui peut différer d’une valeur locale ou observée. Les valeurs sont disponibles hors ligne.")
                    Text("Vous pouvez remplacer une constante en déclarant vous-même son identifiant dans la feuille. Les symboles respectent la casse : g est la pesanteur standard, G est la constante gravitationnelle. Si e n’est pas déclaré, il désigne la charge élémentaire : pour l’exponentielle, écrivez exp(x).")
                }

                Section("Homogénéité physique") {
                    example("2 m + 3 s", explanation: "Une longueur et une durée ne peuvent pas être additionnées : Eval signale des dimensions incompatibles.")
                    example("F == m * a\nF = 14,4 N\nm = 2 kg\na = 7,2 m/s²", explanation: "== compare les dimensions et les valeurs des deux membres. Cette relation est homogène et ses valeurs sont égales.")
                    Text("Le signe = déclare une variable lorsque le membre de gauche est un nom. Utilisez == pour vérifier une égalité (≠ n’existe pas).")
                }

                Section("Annuler, réorganiser, copier") {
                    Text("Annuler et Rétablir, dans le menu Actions de la feuille, défont une suppression, un ajout, une modification, un déplacement ou un réglage de réglette (un geste entier est une seule étape). Si la même feuille a été modifiée dans une autre fenêtre, l’annulation est refusée plutôt que d’effacer cette modification. Secouez l’appareil ou utilisez ⌘Z pour annuler. En mode Texte, l’annulation du clavier ne concerne que la saisie.")
                    Text("En mode Formules, choisissez Réorganiser dans le menu Actions de la feuille pour déplacer des lignes avec leur poignée ou les supprimer, variables comprises ; les réglettes sont alors masquées. Touchez Terminé pour finir. Glissez une ligne vers la gauche pour la supprimer ; une variable à réglette se supprime par son menu. L’ordre des lignes n’influe pas sur le calcul.")
                    Text("Maintenez une ligne pour Copier la valeur (1000 J), Copier la ligne (E = 1000 J), Copier la formule, Partager le résultat, Dupliquer, Modifier ou Supprimer. La valeur copiée suit l’unité affichée. Dupliquer une déclaration ouvre l’éditeur pour lui donner un autre nom.")
                    Text("Partager la feuille ajoute les résultats affichés en notes # = valeur ; Partager sans les résultats envoie la source seule.")
                }

                Section("iPad et accessibilité") {
                    Text("Sur iPad, chaque fenêtre affiche sa propre feuille, et le bouton Résultats place les résultats dans une colonne à côté des formules. Ajouter à la feuille, dans Références, complète la feuille de la fenêtre. Raccourcis : ⌘N nouvelle feuille, ⇧⌘N nouvelle ligne, ⌘F rechercher, ⌘1 et ⌘2 pour changer d’onglet, ⇧⌘R choisir les résultats, ⌥⌘R colonne Résultats, ⌥⌘1 et ⌥⌘2 pour les modes Formules et Texte, ⌘Z pour annuler. Maintenez ⌘ pour afficher la liste.")
                    Text("Eval suit la taille de texte choisie dans Réglages. VoiceOver lit les formules comme des expressions mathématiques en français (« E égale 0,5 fois m fois v au carré ») et annonce les résultats avec leurs unités (« 1000 joules »). Ajustez une réglette avec le geste d’ajustement de VoiceOver : la valeur change au pas de la réglette.")
                }
            }
            .navigationTitle("Utiliser Eval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .keyboardShortcut(.cancelAction)
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
