package com.atom.eval.help

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.atom.eval.R

/** « Utiliser Eval », as a full-screen dialog (iOS HelpView), written for Android. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpDialog(onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.help_title)) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) { Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.close)) }
                    },
                )
            },
        ) { padding ->
            LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                for (section in HelpSections) {
                    item {
                        Text(
                            section.title,
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 8.dp).semantics { heading() },
                        )
                    }
                    items(section.blocks) { block -> Block(block) }
                }
            }
        }
    }
}

@Composable
private fun Block(block: HelpBlock) {
    val modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp)
    when (block) {
        is HelpBlock.Paragraph -> Text(block.text, modifier = modifier)
        is HelpBlock.Example -> Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            SelectionContainer { Text(block.source, fontFamily = FontFamily.Monospace) }
            Text(block.explanation, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        is HelpBlock.Entry -> ListItem(
            headlineContent = { Text(block.label) },
            supportingContent = { Text(block.value, fontFamily = FontFamily.Monospace) },
            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        )
    }
}

private sealed interface HelpBlock {
    data class Paragraph(val text: String) : HelpBlock
    data class Example(val source: String, val explanation: String) : HelpBlock
    data class Entry(val label: String, val value: String) : HelpBlock
}

private class HelpSection(val title: String, vararg val blocks: HelpBlock)

private fun p(text: String) = HelpBlock.Paragraph(text)
private fun example(source: String, explanation: String) = HelpBlock.Example(source, explanation)

/** The help of iOS, with the gestures and places of the Android app. */
private val HelpSections = listOf(
    HelpSection(
        "Une feuille, toutes vos formules",
        p("Écrivez une formule ou une déclaration par ligne. Les résultats se mettent à jour pendant la saisie."),
        example("d = 0,5 * a * t²\na = 7,2 m/s²\nt = 3 s\nd =", "La formule peut précéder ses variables. Terminez une ligne par = pour afficher sa valeur : ici, d = affiche 32,4 m."),
        p("Les variables peuvent dépendre d’autres variables. Chaque nom doit être défini une seule fois ; les dépendances circulaires sont signalées. Une note commence par # (titre) ou // (texte secondaire)."),
    ),
    HelpSection(
        "Vos feuilles",
        p("Chaque feuille est sauvegardée sur cet appareil. La liste Feuilles présente la plus récente en premier ; cherchez-y un titre ou une formule. Sans titre choisi, une feuille porte le nom de sa première note."),
        p("Nouvelle feuille crée une feuille vide. Le bouton des exemples propose des feuilles de mécanique, d’électricité, d’optique, de thermodynamique, de physique quantique, d’astronomie et de méthode : un exemple s’ouvre toujours dans une nouvelle feuille, sans remplacer votre travail."),
        p("Maintenez une feuille dans la liste pour la renommer, la dupliquer, la partager ou la supprimer. Glissez-la vers la gauche pour la supprimer ; Annuler, en bas de l’écran, la rétablit pendant quelques secondes."),
        p("Pour renommer la feuille ouverte, touchez son titre en haut de l’écran."),
    ),
    HelpSection(
        "Écrire une formule",
        p("Touchez une ligne pour la modifier là où elle se trouve, ou Nouvelle ligne (ou +) pour en ajouter une. Retour valide la ligne et en crée une nouvelle en dessous. La valeur se met à jour pendant la saisie. Touchez en dehors des lignes, ou Terminé, pour finir."),
        p("Au-dessus du clavier, la barre insère + − × et des parenthèses à l’endroit du curseur. Son menu Insérer propose les modèles Fraction, Puissance et Racine, qui entourent la sélection, ainsi que =, ÷, ^, ², ³, ⁻¹, π, deg, les variables de la feuille, ou ouvre Constantes et unités…. Terminé ferme le clavier."),
        p("Avec le réglage Écriture mathématique, la ligne se modifie telle qu’elle s’affiche. / fait du terme qui précède le numérateur d’une fraction, ^ ouvre un exposant. La barre propose xⁿ (exposant), √ (racine carrée), ◀ et ▶ pour déplacer le curseur, et son menu Insérer ajoute Fraction, Racine n-ième, ², ⁻¹, Monter, Descendre, =, ×, π, deg, les variables de la feuille et Constantes et unités…. Touchez la formule pour placer le curseur ; un cadre pointillé marque une case vide. L’effacement entre dans une fraction ou une racine, puis la défait quand elle est vide. Les flèches d’un clavier physique déplacent aussi le curseur."),
        p("Les Réglages, dans le menu de la feuille ou avec le bouton engrenage de la liste des feuilles, choisissent la saisie des formules, le nombre de chiffres significatifs, les numéros de ligne, la couleur d’accent (orange industriel par défaut, ou bleu) et le fond chaud des feuilles en mode clair."),
    ),
    HelpSection(
        "Afficher un résultat",
        example("m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v²\nE =\nm * v =", "Une ligne terminée par = affiche sa valeur sur la même ligne : E = 1000 J, et m * v = 400 kg·m·s⁻¹. Écrire E = 0,5 * m * v² = définit E et affiche sa valeur d’un seul coup."),
        p("Une ligne avec une conversion (→ km/h) ou une inconnue (v = ? m/s) affiche toujours sa valeur. Une égalité (==) affiche son verdict. Les autres lignes sont calculées sans afficher de valeur ; leurs erreurs restent signalées sous la ligne."),
        p("Maintenez une ligne pour copier sa valeur, la partager, changer son unité ou la tracer."),
    ),
    HelpSection(
        "Valeurs et unités",
        example("v = 72 km/h\nt = 2 s\nv * t =", "Les unités sont converties en SI : le résultat est 40 m."),
        p("La virgule et le point sont acceptés pour les décimales. La notation scientifique s’écrit 1,5e-3. Les nombres s’affichent sans séparateur de milliers : 1000 J. Les noms et symboles respectent les majuscules."),
        p("Séparez la valeur et son unité par un espace : 5 m désigne le mètre même si m est aussi une variable. Pour les unités composées, gardez les opérateurs sans espaces : 2 kg*m/s². Dans une formule, utilisez * entre les variables et espacez les opérateurs autour d’une quantité : 2 m/s² * m."),
        p("Une valeur sans unité est sans dimension. Pour vérifier une formule physique, attribuez les unités aux grandeurs concernées. Utilisez le kelvin : °C et °F ne sont pas pris en charge."),
        p("Eval connaît aussi atm, Torr, mmHg, mbar, hPa, cal, kcal, Wh, kWh, Ah, Å, ly, pc, ft, mi, Da, lb, jour, an, tr, rpm, %, ppm, ml, cl, kohm… La liste complète se trouve dans Références › Unités."),
        p("Les noms t, d, a, u, j, in, kn, psi et G ne sont pas des unités : vous pouvez les utiliser comme variables. Si Eval lit un symbole non déclaré comme une unité (par exemple T comme tesla), il le signale dans Symboles lus comme des unités ; déclarez-le pour en faire une variable."),
    ),
    HelpSection(
        "Convertir l’affichage",
        example("v = 20 m/s → km/h", "Écrit à la fin de la ligne, → (ou ->) convertit le résultat : 72 km/h. Les variables restent en SI."),
        example("m_e*c^2 -> MeV", "Le résultat s’affiche en 0,510999 MeV."),
        p("Maintenez une ligne et choisissez Afficher en : Eval écrit la flèche pour vous. Unités SI la retire. Le résultat et la valeur copiée suivent l’unité choisie."),
        p("Une fréquence en s⁻¹ s’affiche s⁻¹ ; choisissez → Hz, → rad/s ou → tr/min selon l’usage. Les cibles sont des unités ou des constantes, jamais des variables de la feuille : m, h et g désignent donc le mètre, l’heure et le gramme."),
    ),
    HelpSection(
        "Fonctions et opérations",
        HelpBlock.Entry("Arithmétique", "+  −  *  /  ^"),
        HelpBlock.Entry("Écriture", "×  ÷  ²  ³  √  ( )"),
        HelpBlock.Entry("Racines, exponentielles", "sqrt, cbrt, root, exp, ln, log"),
        HelpBlock.Entry("Trigonométrie", "sin, cos, tan, asin, acos, atan, atan2"),
        HelpBlock.Entry("Autres", "sinh, cosh, tanh, abs, min, max, floor, ceil, round"),
        example("sqrt(9 m²) =\nsin(30 deg) =\n2 * pi =", "Les résultats sont 3 m, 0,5 et 6,28319. Les angles sont en radians par défaut ; deg ou ° permet de saisir des degrés. Les fonctions trigonométriques et logarithmiques exigent un argument sans dimension."),
        example("max(2,5; 3) =", "Une fonction à plusieurs arguments les sépare par un point-virgule, car la virgule est décimale : le résultat est 3. min, max, root(x; n), log(x; base) et atan2(y; x) fonctionnent ainsi."),
        example("asin(0,5) → °", "Les fonctions trigonométriques inverses renvoient des radians ; → ° affiche 30°."),
        p("min seul reste la minute : 5 min vaut 300 s. Un nom de fonction peut être une variable (max = 10 m) : c’est un appel seulement suivi de ( comme dans max(a; b)."),
    ),
    HelpSection(
        "Pourcentage et factorielle",
        example("P = 200 W\nP * 15 % =", "35 % vaut 0,35 : le résultat est 30 W. 0,35 -> % affiche 35 %."),
        example("n = 6\nn! =", "La factorielle d’un entier de 0 à 170 : le résultat est 720."),
    ),
    HelpSection(
        "Résoudre une équation",
        example("3x^2 + 2x - 3 = 0\nx =", "Écrivez l’équation, puis le nom cherché suivi de = : x = affiche (−1 ± √10)/3 ≈ 0,720759 ; −1,38743."),
        p("Jusqu’au degré 2, les solutions d’un polynôme s’affichent sous forme exacte, puis en décimales ; au-delà, et pour les autres équations (exp, sin, racines…), elles sont cherchées numériquement. Les unités sont respectées : avec m = 80 kg et 1000 J = 0,5 * m * v^2, v = affiche −5 m·s⁻¹ ; 5 m·s⁻¹. Le nom cherché ne doit être ni déclaré, ni une constante, ni une unité, et une seule équation doit le contenir. Les autres lignes utilisent la plus petite solution positive."),
        example("E = 1000 J\nm = 80 kg\nv = ? m/s\nE == 0,5 * m * v²", "v = ? m/s déclare une inconnue avec son unité : Eval la cherche numériquement. Ici v vaut 5 m/s, avec la note « Autre solution : −5 m/s. », et la relation est vérifiée."),
    ),
    HelpSection(
        "Simplifier une formule",
        example("E = 0,5 * m * v^2 * 2 / m", "Maintenez la ligne : Simplifier, en tête du menu, montre sa forme simplifiée, E = v², et réécrit la ligne ; Annuler la rétablit."),
        p("Eval calcule les nombres exactement, regroupe les termes semblables (2x + 3x → 5x), simplifie les facteurs communs, fusionne les puissances, réduit les racines (√12 → 2√3) et les fractions (x² − 1)/(x − 1) → x + 1, et développe quand le résultat est plus court. Une formule déjà simple n’affiche pas de proposition."),
    ),
    HelpSection(
        "Scanner une formule",
        p("Dans le menu de la feuille, choisissez Scanner une formule ; pendant la saisie d’une ligne, le bouton scanner de la barre au-dessus du clavier l’ouvre aussi. Cadrez la formule, pincez pour zoomer, puis touchez le déclencheur. Le bouton photothèque lit une photo avec le même cadre, et la lampe éclaire la page."),
        p("Seul le contenu du cadre est lu, sur l’appareil : l’image n’est ni conservée ni envoyée. Les lignes reconnues s’ajoutent à la fin de la feuille, ou sous la ligne en cours si le scanner a été ouvert depuis la barre du clavier ; Annuler les retire. Les exposants et les fractions sont reconnus d’après leur position, souvent mal : vérifiez les lignes ajoutées."),
    ),
    HelpSection(
        "Ajuster une variable en glissant",
        p("La valeur d’une déclaration numérique, comme 7,2 m/s² dans a = 7,2 m/s², est teintée. Maintenez-la : sa réglette apparaît en bas de l’écran, avec la valeur en toutes lettres. Comme la molette de Photos, les graduations suivent le doigt : glissez vers la gauche pour augmenter la valeur, vers la droite pour la diminuer. La réglette n’a pas de bornes : elle passe par zéro, dans les valeurs négatives, et va aussi loin que vous glissez."),
        p("Le pas suit automatiquement la précision saisie : 6 avance de 1, 8,2 de 0,1 et 8,25 de 0,01. Cette précision est conservée en glissant, même lorsque la valeur atteint un entier."),
        p("Le bouton de réglage de la réglette permet de choisir un pas manuel en désactivant Pas automatique, et l’intervalle du graphique. Les réglages sont sauvegardés avec la feuille. Les unités et les commentaires sont conservés ; une valeur en km/h reste saisie en km/h."),
        p("Les variables calculées, comme E = 0,5 * m * v², se modifient en touchant leur ligne. Leurs valeurs suivent automatiquement celles des variables ajustées."),
    ),
    HelpSection(
        "Tracer un résultat",
        p("Maintenez une ligne calculée et choisissez Tracer en fonction de, puis une des variables à réglette dont elle dépend. Le graphique couvre l’intervalle du graphique de la variable ; modifiez-le avec les réglages de sa réglette. Touchez le graphique pour lire une valeur. Les points où le calcul est impossible laissent un trou. Une ligne comme y = 2·x, où x n’est pas déclaré, se trace aussi : choisissez Tracer en fonction de x, puis réglez l’intervalle de x, de −10 à 10 au départ. Rien n’est ajouté à la feuille."),
    ),
    HelpSection(
        "Constantes reconnues",
        example("h * c / lambda =\nlambda = 550 nm", "h et c sont reconnus et leurs valeurs apparaissent dans « Constantes reconnues ». Le résultat est 3,61172 × 10⁻¹⁹ J."),
        p("L’onglet Références contient les constantes de physique, de chimie, d’astronomie et de mathématiques, ainsi que les unités. Basculez entre Constantes et Unités, filtrez par domaine ou cherchez un nom, un symbole ou un identifiant de saisie."),
        p("Touchez une constante pour consulter sa valeur, sa nature et sa source ; maintenez-la pour copier sa valeur ou son identifiant. Le champ Saisie indique le nom à utiliser dans une formule, par exemple N_A pour la constante d’Avogadro."),
        p("Exacte indique une valeur définie ou dérivée d’une définition ; Mesurée indique une valeur expérimentale ; Conventionnelle indique une valeur de référence adoptée, qui peut différer d’une valeur locale ou observée. Les valeurs sont disponibles hors ligne."),
        p("Vous pouvez remplacer une constante en déclarant vous-même son identifiant dans la feuille. Les symboles respectent la casse : g est la pesanteur standard, G est la constante gravitationnelle. Si e n’est pas déclaré, il désigne la charge élémentaire : pour l’exponentielle, écrivez exp(x)."),
    ),
    HelpSection(
        "Homogénéité physique",
        example("2 m + 3 s", "Une longueur et une durée ne peuvent pas être additionnées : Eval signale des dimensions incompatibles."),
        example("F == m * a\nF = 14,4 N\nm = 2 kg\na = 7,2 m/s²", "== compare les dimensions et les valeurs des deux membres. Cette relation est homogène et ses valeurs sont égales."),
        p("Le signe = déclare une variable lorsque le membre de gauche est un nom. Utilisez == pour vérifier une égalité (≠ n’existe pas)."),
    ),
    HelpSection(
        "Annuler, réorganiser, copier",
        p("Annuler et Rétablir, en haut de la feuille, défont une suppression, un ajout, une modification, un déplacement ou un réglage de réglette (un geste entier est une seule étape). Toute la saisie d’une ligne, du toucher à la sortie de la ligne, est une seule étape."),
        p("Choisissez Réorganiser dans le menu de la feuille pour monter ou descendre des lignes ; touchez Terminé pour finir. Glissez une ligne vers la gauche pour la supprimer. L’ordre des lignes n’influe pas sur le calcul."),
        p("Maintenez une ligne pour Copier la valeur (1000 J), Copier la ligne (E = 1000 J), Copier la formule, Partager le résultat, Dupliquer, Modifier ou Supprimer. La valeur copiée suit l’unité affichée."),
        p("Partager la feuille ajoute les valeurs affichées en notes # valeur ; Partager sans les résultats envoie la source seule."),
    ),
    HelpSection(
        "Tablette et accessibilité",
        p("Sur un grand écran, la liste des feuilles et la feuille s’affichent côte à côte, et les onglets passent sur le côté."),
        p("Eval suit la taille de texte choisie dans les réglages de l’appareil. TalkBack lit les formules comme des expressions mathématiques en français (« E égale 0,5 fois m fois v au carré ») et annonce les résultats avec leurs unités (« 1000 joules »). Sur une déclaration numérique, l’action Afficher la réglette ouvre la réglette, dont les actions Augmenter et Diminuer changent la valeur d’un pas."),
    ),
)
