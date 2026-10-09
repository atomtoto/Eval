import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Une feuille, toutes vos formules") {
                    Text("Écrivez une formule ou une déclaration par ligne. Les résultats se mettent à jour pendant la saisie.")
                    example("d = 0,5 * a * t²\na = 7,2 m/s²\nt = 3 s\nd =", explanation: "La formule peut précéder ses variables. Terminez une ligne par = pour afficher sa valeur, comme dans Notes : ici, d = affiche 32,4 m.")
                    Text("Les variables peuvent dépendre d’autres variables. Chaque nom doit être défini une seule fois ; les dépendances circulaires sont signalées. Une note commence par # (titre) ou // (texte secondaire).")
                }

                Section("Vos feuilles") {
                    Text("Chaque feuille est sauvegardée sur cet appareil. La liste Feuilles présente la plus récente en premier ; cherchez-y un titre ou une formule. Sans titre choisi, une feuille porte le nom de sa première note.")
                    Text("Nouvelle feuille (⌘N avec un clavier) crée une feuille vide. Nouvelle à partir d’un exemple propose des feuilles de mécanique, d’électricité, d’optique, de thermodynamique, de physique quantique, d’astronomie et de méthode : un exemple s’ouvre toujours dans une nouvelle feuille, sans remplacer votre travail.")
                    Text("Maintenez une feuille dans la liste pour la renommer, la dupliquer, la partager ou la supprimer. La suppression demande toujours une confirmation.")
                }

                Section("Écrire une formule") {
                    Text("Touchez une ligne pour la modifier là où elle se trouve, ou Nouvelle ligne (ou +) pour en ajouter une. Retour valide la ligne et en crée une nouvelle en dessous. La valeur se met à jour pendant la saisie.")
                    Text("Au-dessus du clavier, la barre de symboles insère + − × et des parenthèses à l’endroit du curseur. Son menu Insérer propose les modèles Fraction, Puissance et Racine, qui entourent la sélection, ainsi que =, ÷, ^, ², ³, ⁻¹, π, deg, les variables de la feuille, ou ouvre Constantes et unités… (le curseur est suivi à partir d’iOS 18 ; avant, l’insertion se fait en fin de ligne). Terminé ferme le clavier.")
                    Text("Avec le réglage Écriture mathématique, la ligne se modifie telle qu’elle s’affiche. / fait du terme qui précède le numérateur d’une fraction, ^ ouvre un exposant. La barre propose xⁿ (exposant), √ (racine carrée), ◀ et ▶ pour déplacer le curseur, et son menu Insérer ajoute Fraction, Racine n-ième, ², ⁻¹, Monter, Descendre, =, ×, π, deg, les variables de la feuille et Constantes et unités…. Touchez la formule pour placer le curseur ; un cadre pointillé marque une case vide. L’effacement entre dans une fraction ou une racine, puis la défait quand elle est vide. Retour valide la ligne et en crée une nouvelle, comme en texte.")
                    Text("Modifier en texte, dans le menu Actions de la feuille, ouvre toute la feuille dans un seul champ. Les Réglages, dans le même menu, choisissent la saisie des formules, le nombre de chiffres significatifs, la couleur d’accent (orange industriel par défaut, ou bleu), le fond chaud des feuilles en mode clair et le style de l’icône de l’app (Lentille ou Point), qui suit la couleur d’accent. Pendant la saisie, une barre flotte juste au-dessus du clavier avec le menu Insérer, les touches courantes et Terminé.")
                }

                Section("Afficher un résultat") {
                    example("m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v²\nE =\nm * v =", explanation: "Une ligne terminée par = affiche sa valeur sur la même ligne : E = 1000 J, et m * v = 400 kg·m·s⁻¹. Écrire E = 0,5 * m * v² = définit E et affiche sa valeur d’un seul coup.")
                    Text("Une ligne avec une conversion (→ km/h) ou une inconnue (v = ? m/s) affiche toujours sa valeur. Une égalité (==) affiche son verdict. Les autres lignes sont calculées sans afficher de valeur ; leurs erreurs restent signalées sous la ligne.")
                    Text("Touchez une valeur affichée pour la copier, la partager, changer son unité ou la tracer.")
                }

                Section("Valeurs et unités") {
                    example("v = 72 km/h\nt = 2 s\nv * t =", explanation: "Les unités sont converties en SI : le résultat est 40 m.")
                    Text("La virgule et le point sont acceptés pour les décimales. La notation scientifique s’écrit 1,5e-3. Les nombres s’affichent sans séparateur de milliers : 1000 J. Les noms et symboles respectent les majuscules.")
                    Text("Séparez la valeur et son unité par un espace : 5 m désigne le mètre même si m est aussi une variable. Pour les unités composées, gardez les opérateurs sans espaces : 2 kg*m/s². Dans une formule, utilisez * entre les variables et espacez les opérateurs autour d’une quantité : 2 m/s² * m.")
                    Text("Une valeur sans unité est sans dimension. Pour vérifier une formule physique, attribuez les unités aux grandeurs concernées. Utilisez le kelvin : °C et °F ne sont pas pris en charge.")
                    Text("Eval connaît aussi atm, Torr, mmHg, mbar, hPa, cal, kcal, Wh, kWh, Ah, Å, ly, pc, ft, mi, Da, lb, jour, an, tr, rpm, %, ppm, ml, cl, kohm… La liste complète se trouve dans Références › Unités.")
                    Text("Les noms t, d, a, u, j, in, kn, psi et G ne sont pas des unités : vous pouvez les utiliser comme variables. Si Eval lit un symbole non déclaré comme une unité (par exemple T comme tesla), il le signale dans Symboles lus comme des unités ; déclarez-le pour en faire une variable.")
                }

                Section("Convertir l’affichage") {
                    example("v = 20 m/s → km/h", explanation: "Écrit à la fin de la ligne, → (ou ->) convertit le résultat : 72 km/h. Les variables restent en SI.")
                    example("m_e*c^2 -> MeV", explanation: "Le résultat s’affiche en 0,510999 MeV.")
                    Text("Maintenez une ligne, ou touchez sa valeur, et choisissez Afficher en : Eval écrit la flèche pour vous. Unités SI la retire. Le résultat et la valeur copiée suivent l’unité choisie.")
                    Text("Une fréquence en s⁻¹ s’affiche s⁻¹ ; choisissez → Hz, → rad/s ou → tr/min selon l’usage. Les cibles sont des unités ou des constantes, jamais des variables de la feuille : m, h et g désignent donc le mètre, l’heure et le gramme.")
                }

                Section("Fonctions et opérations") {
                    LabeledContent("Arithmétique", value: "+  −  *  /  ^")
                    LabeledContent("Écriture", value: "×  ÷  ²  ³  √  ( )")
                    LabeledContent("Racines, exponentielles", value: "sqrt, cbrt, root, exp, ln, log")
                    LabeledContent("Trigonométrie", value: "sin, cos, tan, asin, acos, atan, atan2")
                    LabeledContent("Autres", value: "sinh, cosh, tanh, abs, min, max, floor, ceil, round")
                    example("sqrt(9 m²) =\nsin(30 deg) =\n2 * pi =", explanation: "Les résultats sont 3 m, 0,5 et 6,28319. Les angles sont en radians par défaut ; deg ou ° permet de saisir des degrés. Les fonctions trigonométriques et logarithmiques exigent un argument sans dimension.")
                    example("max(2,5; 3) =", explanation: "Une fonction à plusieurs arguments les sépare par un point-virgule, car la virgule est décimale : le résultat est 3. min, max, root(x; n), log(x; base) et atan2(y; x) fonctionnent ainsi.")
                    example("asin(0,5) → °", explanation: "Les fonctions trigonométriques inverses renvoient des radians ; → ° affiche 30°.")
                    Text("min seul reste la minute : 5 min vaut 300 s. Un nom de fonction peut être une variable (max = 10 m) : c’est un appel seulement suivi de ( comme dans max(a; b).")
                }

                Section("Pourcentage et factorielle") {
                    example("P = 200 W\nP * 15 % =", explanation: "35 % vaut 0,35 : le résultat est 30 W. 0,35 -> % affiche 35 %.")
                    example("n = 6\nn! =", explanation: "La factorielle d’un entier de 0 à 170 : le résultat est 720.")
                }

                Section("Résoudre une inconnue") {
                    example("E = 1000 J\nm = 80 kg\nv = ? m/s\nE == 0,5 * m * v²", explanation: "v = ? m/s déclare une inconnue : Eval la cherche numériquement. Ici v vaut 5 m/s, avec la note « Autre solution : −5 m/s. », et la relation est vérifiée.")
                    Text("Gardez exactement une relation (==) qui contient l’inconnue, directement ou par vos déclarations. Eval affiche la plus petite solution positive entre 10⁻¹² et 10¹². Ce n’est pas un calcul symbolique : il ne transforme pas l’équation et ne résout qu’une inconnue par relation.")
                }

                Section("Ajuster une variable en glissant") {
                    Text("La valeur d’une déclaration numérique, comme 7,2 m/s² dans a = 7,2 m/s², est teintée. Maintenez-la : sa réglette apparaît dans une bulle ancrée à la valeur, comme un menu d’appui long, avec la valeur en toutes lettres ; touchez en dehors de la bulle pour la fermer. Comme la molette de Photos, les graduations suivent le doigt : glissez vers la gauche pour augmenter la valeur, vers la droite pour la diminuer. La réglette n’a pas de bornes : elle passe par zéro, dans les valeurs négatives, et va aussi loin que vous glissez. Le bouton de réglage de la bulle règle le pas et l’intervalle du graphique.")
                    Text("Le pas suit automatiquement la précision saisie : 6 avance de 1, 8,2 de 0,1 et 8,25 de 0,01. Cette précision est conservée en glissant, même lorsque la valeur atteint un entier.")
                    Text("Le bouton de réglage permet de choisir un minimum, un maximum ou un pas manuel en désactivant Pas automatique. Les réglages sont sauvegardés avec la feuille. Les unités et les commentaires sont conservés ; une valeur en km/h reste saisie en km/h.")
                    Text("Les variables calculées, comme E = 0,5 * m * v², se modifient en touchant leur ligne. Leurs valeurs suivent automatiquement celles des variables ajustées.")
                }

                Section("Tracer un résultat") {
                    Text("Maintenez une ligne calculée et choisissez Tracer en fonction de, puis une des variables à réglette dont elle dépend. Le graphique couvre l’intervalle du graphique de la variable (autour de sa valeur, par défaut) ; modifiez-le avec les réglages de la variable pour tracer une autre plage. Touchez le graphique pour lire une valeur. Les points où le calcul est impossible laissent un trou.")
                }

                Section("Constantes reconnues") {
                    example("h * c / lambda =\nlambda = 550 nm", explanation: "h et c sont reconnus et leurs valeurs apparaissent dans « Constantes reconnues ». Le résultat est 3,61172 × 10⁻¹⁹ J.")
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
                    Text("Annuler et Rétablir, dans le menu Actions de la feuille, défont une suppression, un ajout, une modification, un déplacement ou un réglage de réglette (un geste entier est une seule étape). Si la même feuille a été modifiée dans une autre fenêtre, l’annulation est refusée plutôt que d’effacer cette modification. Toute la saisie d’une ligne, du toucher à la sortie de la ligne, est une seule étape. Pendant la saisie, ⌘Z et le geste d’annulation ne concernent que le texte de la ligne.")
                    Text("Choisissez Réorganiser dans le menu Actions de la feuille pour déplacer des lignes avec leur poignée ou les supprimer ; les réglettes sont alors indisponibles. Touchez Terminé pour finir. Glissez une ligne vers la gauche pour la supprimer. L’ordre des lignes n’influe pas sur le calcul.")
                    Text("Maintenez une ligne pour Copier la valeur (1000 J), Copier la ligne (E = 1000 J), Copier la formule, Partager le résultat, Dupliquer, Modifier ou Supprimer. La valeur copiée suit l’unité affichée. La copie d’une ligne s’ouvre en modification : une déclaration copiée doit recevoir un autre nom.")
                    Text("Partager la feuille ajoute les valeurs affichées en notes # valeur ; Partager sans les résultats envoie la source seule.")
                }

                Section("iPad et accessibilité") {
                    Text("Sur iPad, chaque fenêtre affiche sa propre feuille. Ajouter à la feuille, dans Références, complète la feuille de la fenêtre avec une ligne qui affiche la valeur, comme c =. Raccourcis : ⌘N nouvelle feuille, ⇧⌘N nouvelle ligne, ⌘F rechercher, ⌘1 et ⌘2 pour changer d’onglet, ⌘, pour les Réglages, ⌘Z pour annuler. Maintenez ⌘ pour afficher la liste.")
                    Text("Eval suit la taille de texte choisie dans les réglages de l’appareil. VoiceOver lit les formules comme des expressions mathématiques en français (« E égale 0,5 fois m fois v au carré ») et annonce les résultats avec leurs unités (« 1000 joules »). Sur une déclaration numérique, le geste d’ajustement de VoiceOver change la valeur au pas de la réglette, et l’action Afficher la réglette ouvre la bulle de la réglette.")
                }
            }
            .warmPage()
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
