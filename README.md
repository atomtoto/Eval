# Eval

Calculatrice iOS de physique en SwiftUI : des feuilles de formules littérales, des variables et des unités, avec calcul automatique, analyse dimensionnelle, conversion d’affichage et résolution numérique d’une inconnue. Fonctionne hors ligne sur iPhone et iPad (iOS 17 ou plus).

## Démarrer

Ouvrir `Eval.xcodeproj` dans Xcode, choisir le schéma **Eval** et lancer sur un simulateur iPhone ou iPad. Pour un appareil physique, sélectionner son équipe de signature dans **Signing & Capabilities**. Le moteur `EvalCore` est un package Swift local, sans dépendance externe. Les tests du moteur s’exécutent avec `swift test` (voir [Structure et validation](#structure-et-validation)).

Au premier lancement, **Nouvelle feuille** ouvre une feuille vide et **Nouvelle à partir d’un exemple** propose des feuilles prêtes à modifier. Une feuille créée par une version précédente d’Eval est reprise automatiquement.

## Utilisation

Une formule, une variable ou une comparaison par ligne. Les déclarations sont résolues à l’échelle de la feuille : leur ordre n’a pas d’importance, et une variable peut dépendre d’une autre variable déclarée plus bas.

```text
# Énergie cinétique
E = 0,5 * m * v²
m = 80 kg
v = 5 m/s
E
```

Résultat : **1000 J**. La virgule et le point décimaux sont acceptés, ainsi que la notation scientifique (`1,5e-3`). Les nombres s’affichent sans séparateur de milliers. Les résultats sont en unités SI, sauf si l’on demande une autre unité avec `→` (voir [Convertir l’affichage](#convertir-laffichage)).

```text
# Distance depuis le repos
d = 0,5 * a * t²
t = 3 s
a = 7,2 m/s²
d
```

Résultat : **32,4 m**.

Les constantes non déclarées sont reconnues et affichées avec leur valeur. Le catalogue couvre les constantes fondamentales, l’électromagnétisme, la physique quantique, la thermodynamique, la chimie, l’astronomie et les mathématiques. Par exemple : `c`, `g`, `G`, `h`, `hbar` / `ℏ`, `e`, `k_B`, `N_A`, `R`, `epsilon_0` / `ε₀`, `mu_0` / `μ₀`, `pi` / `π`, `m_e`, `m_p`, `alpha` / `α`. Une déclaration explicite remplace la constante dans toute la feuille. `g` représente la pesanteur standard ; sa valeur locale peut varier.

```text
# Énergie d’un photon
h * c / lambda
lambda = 550 nm
```

Résultat : **3,61172 × 10⁻¹⁹ J**. Les constantes utilisées sont listées dans la section **Constantes reconnues** de la feuille.

L’onglet **Références** permet de chercher les constantes et unités par nom, symbole ou domaine. Le sélecteur **Constantes / Unités** de la barre d’outils change de catalogue, et le menu **Domaine** filtre les constantes. Toucher une constante ouvre sa page : valeur SI, identifiant de **Saisie**, alias, **Nature** et lien vers la source. **Ajouter à la feuille** (bouton de la page, glissement vers la droite ou menu contextuel) insère son identifiant dans la feuille de la fenêtre courante ; le menu contextuel permet aussi de copier la valeur ou l’identifiant. Les valeurs sont incluses dans l’application et restent disponibles hors ligne.

La nature **Exacte** décrit une valeur définie ou dérivée d’une définition, **Mesurée** une valeur expérimentale, et **Conventionnelle** une référence adoptée, comme la pesanteur standard ou une grandeur astronomique nominale. L’affichage et le calcul conservent la précision finie de `Double`, y compris pour les constantes exactes. Les constantes mesurées utilisent leur valeur centrale ; les incertitudes ne sont pas propagées.

### Plusieurs feuilles

L’onglet **Calcul** ouvre la liste **Feuilles**, de la plus récente à la plus ancienne, avec le titre, la date relative et le premier résultat de chaque feuille. Le champ de recherche filtre par titre ou par contenu. Une feuille sans titre choisi prend le nom de sa première note `# …`.

- **Nouvelle feuille** (⌘N avec un clavier) crée une feuille vide.
- **Nouvelle à partir d’un exemple** propose 22 feuilles vérifiées, groupées en Mécanique, Électricité, Optique et ondes, Thermodynamique, Quantique, Astronomie et Méthode. Un exemple s’ouvre toujours dans une nouvelle feuille et ne remplace jamais un travail en cours.
- Un appui long sur une feuille propose **Renommer**, **Dupliquer**, **Partager** et **Supprimer**. La suppression, aussi disponible par glissement ou avec **Modifier**, demande toujours une confirmation.
- Chaque feuille est enregistrée dans un fichier JSON du dossier Application Support de l’appareil. Une feuille de plus de 500 lignes ou 100 000 caractères est refusée avec un message d’erreur. Si ce dossier est indisponible, Eval garde les feuilles en mémoire sans écrire ailleurs et affiche une alerte : elles seraient perdues à la fermeture.

### Résultats sous les formules

En mode **Formules**, le résultat d’une ligne choisie s’affiche sous sa formule. Un appui long sur une ligne propose **Afficher le résultat** ou **Masquer le résultat** ; l’éditeur d’une ligne offre le même choix avec **Afficher dans Résultats**. **Choisir les résultats**, dans le menu **Actions de la feuille**, permet de choisir plusieurs lignes à la fois (**Sélection** › **Tout afficher** / **Tout masquer**). Une ligne masquée reste disponible pour les calculs qui en dépendent.

Les nouvelles lignes affichent leur résultat par défaut, sauf les déclarations de nombres, que leur réglette montre déjà. Une ligne qui demande sa valeur, par une conversion (`v = d / t → km/h`) ou comme inconnue (`v = ? m/s`), est affichée par défaut, y compris à la création d’une feuille et au chargement d’un exemple. Pendant qu’une ligne est modifiée, son résultat précédent reste affiché en grisé jusqu’au nouveau calcul. Les choix sont sauvegardés avec des identités de ligne pour suivre les déplacements et les modifications.

Le mode **Texte** et la colonne **Résultats** de l’iPad regroupent les valeurs dans une section **Résultats** ; en mode Texte, une bande de résultats reste visible au-dessus du clavier. À la création d’une feuille et au chargement d’un exemple, les expressions, comparaisons, conversions et inconnues sont affichées et les autres déclarations masquées. Les erreurs restent visibles sur les lignes en mode Formules, ou dans **À corriger** en mode Texte, même lorsqu’un résultat est masqué.

Les symboles non déclarés qu’Eval a lus comme des unités (par exemple `T` comme tesla dans `F = 2 * T`) sont listés dans **Symboles lus comme des unités**. Si ce sont en réalité des variables, il suffit de les déclarer.

### Ajuster les valeurs avec un curseur

Les déclarations numériques comme `a = 7,2 m/s²`, `v = 72 km/h` ou `x = -3` proposent une **réglette graduée**, avec un repère central fixe et des graduations mobiles, inspirée du réglage des nombres dans Notes. Glisser horizontalement modifie le nombre dans la feuille et recalcule les résultats pendant le mouvement. En mode **Texte**, les réglettes sont regroupées dans **Ajuster les variables**.

Le **pas automatique** suit la précision du nombre saisi : `6` → `1`, `8,2` → `0,1`, `8,25` → `0,01`, `8,20` → `0,01` et `1,2e3` → `100`. Cette précision est conservée pendant le glissement, y compris lorsque `8,2` atteint `9,0`, et la réglette n’écrit pas de bruit binaire du type `0,9199999999999999`. Le bouton de réglage permet de définir **minimum et maximum** (clavier numérique), ou de désactiver le pas automatique pour choisir un **pas manuel**, sauvegardé avec l’identité de la ligne. Les unités, espaces et commentaires sont conservés. Les variables définies par des expressions restent éditables par l’éditeur de formules et se recalculent à partir des variables ajustées.

La réglette utilise une petite composition SwiftUI (Canvas et DragGesture), nécessaire au repère fixe et au réglage relatif, avec le matériau système ou Liquid Glass sur iOS 26 et plus. Le défilement vertical de la feuille reste disponible ; les variables se suppriment par leur menu contextuel ou avec **Réorganiser**. VoiceOver ajuste les valeurs avec le même pas.

### Tracer un résultat

Pour une ligne calculée (expression ou définition) et une variable à réglette, le menu contextuel de la ligne propose **Tracer en fonction de** puis le nom de la variable. La courbe couvre l’intervalle de la réglette, modifiable par ses réglages ; une ligne pointillée marque la valeur actuelle et toucher le graphique lit une valeur. Les points où le calcul échoue (racine d’un nombre négatif, division par zéro) laissent un trou dans la courbe. Si le résultat est affiché avec `→`, le tracé suit cette unité.

### Écriture mathématique

Le mode **Formules** affiche les divisions comme des fractions, les puissances en exposant et les racines carrées avec leur signe. Les notes `# …` s’affichent comme des titres, les notes `// …` comme du texte secondaire. Le bouton **+** (**Nouvelle ligne**) ajoute une ligne et ouvre l’éditeur avec le clavier ; toucher une ligne l’édite et **Retour** l’enregistre. L’éditeur fournit un aperçu en direct et des boutons **Fraction**, **Puissance** et **Racine carrée** : chacun ouvre une page de champs pour les opérandes (le bouton de retour annule). Une construction peut remplacer l’expression ou se combiner avec elle ; le membre gauche d’une déclaration ou d’une comparaison est conservé.

Par exemple, pour `E = h * c / lambda`, choisir Fraction, mettre `h * c` au numérateur et `lambda` au dénominateur. Le résultat est présenté avec une barre de fraction, tout en conservant la syntaxe de calcul existante. Le mode **Texte**, choisi dans le menu **Actions de la feuille**, permet de modifier la feuille entière et de la partager telle quelle.

Le rendu mathématique est composé en SwiftUI, s’adapte à Dynamic Type et défile horizontalement pour les expressions longues. Il ne nécessite pas de WebView, de bibliothèque de rendu ou de connexion réseau.

### Clavier et symboles

Au-dessus du clavier, une barre insère à l’emplacement du curseur `+`, `−`, `×`, `÷` et des parenthèses `( )`. Son menu **Insérer** ajoute `=`, `^`, `²`, `³`, `⁻¹`, `√( )`, `π` et `deg`, les variables de la feuille, ou ouvre **Constantes et unités…**, un sélecteur avec recherche qui insère le nom choisi. L’insertion à la position du curseur nécessite iOS 18 ; sous iOS 17, le symbole est ajouté en fin de texte. Le bouton **Terminé** ferme le clavier.

### Annuler et rétablir

En mode Formules, **Annuler** et **Rétablir** (menu **Actions de la feuille**), le geste de secousse et ⌘Z défont l’ajout, la suppression, la modification, le déplacement, le choix d’un résultat ou d’une unité d’affichage. Un geste de réglette, quelle que soit sa durée, compte pour une seule étape. Si la même feuille a été modifiée dans une autre fenêtre, l’annulation est refusée plutôt que d’effacer cette modification. En mode Texte, l’annulation du clavier ne concerne que la saisie.

**Réorganiser** (menu **Actions de la feuille**, puis **Terminé**) réordonne les lignes (poignée) et les supprime, variables comprises ; glisser une ligne vers la gauche la supprime aussi, sauf pour une variable à réglette, qui se supprime par son menu contextuel. L’ordre des lignes n’influe pas sur le calcul.

### Copier et partager

Le menu contextuel d’une ligne propose **Copier la valeur** (`1000 J`), **Copier la ligne** (`E = 1000 J` pour une déclaration, `m * v = 400 kg·m·s⁻¹` pour une expression), **Copier la formule**, **Partager le résultat**, **Modifier**, **Dupliquer** et **Supprimer**. La valeur copiée est celle affichée, en unités SI ou dans l’unité choisie avec `→`, et se colle comme une entrée valide (les nombres négatifs s’affichent avec le vrai signe moins `−`, que l’analyseur accepte). **Dupliquer** une déclaration ouvre l’éditeur pour lui donner un autre nom, car un nom ne se déclare qu’une fois.

**Partager la feuille** envoie son texte en ajoutant à chaque ligne affichée sa valeur en note, par exemple `E = 0,5 * m * v²  # = 1000 J`, de sorte que le texte se rouvre comme une feuille ; **Partager sans les résultats** envoie la source seule.

### iPad et clavier physique

Sur iPad, chaque fenêtre affiche sa propre feuille. Le bouton **Résultats** de la barre d’outils place les résultats dans une colonne à côté des formules, et **Ajouter à la feuille** dans Références complète la feuille de la fenêtre active. Raccourcis clavier, visibles en maintenant ⌘ et dans la barre des menus de l’iPad :

- ⌘N **Nouvelle feuille**, ⇧⌘N **Nouvelle ligne**, ⌘F **Rechercher** (iOS 18 ou plus) ;
- ⌘1 **Calcul**, ⌘2 **Références**, ⌘? **Aide** ;
- menu **Feuille** : ⇧⌘R **Choisir les résultats**, ⌥⌘R colonne **Résultats**, ⌥⌘1 mode **Formules**, ⌥⌘2 mode **Texte** ;
- ⌘Z et ⇧⌘Z annulent et rétablissent ; dans une fenêtre d’édition, Échap annule et ⌘↩ confirme.

### Accessibilité

L’interface est construite avec les composants système, ce qui donne accès à Dynamic Type et à VoiceOver. Les réglettes s’ajustent avec le geste d’ajustement de VoiceOver, au pas de la réglette, et les touches de la barre de symboles portent des noms parlés (« Au carré », « Diviser »…). VoiceOver lit les formules comme des expressions mathématiques en français (`E = 0,5 * m * v²` se dit « E égale 0,5 fois m fois v au carré ») et nomme les unités des résultats (« 1000 joules », « 5 mètres par seconde »).

## Syntaxe

- Opérateurs : `+`, `-`, `*`, `/`, `^`, ainsi que `−`, `×`, `÷`, `·` et les exposants Unicode (`²`, `³`, `⁻¹`…). Les puissances sont associatives à droite : `2^3^2 = 512` ; `-2^2 = -4`.
- Parenthèses et multiplication implicite : `2a`, `3(a+1)`, `2π√3`. `√2 m` se lit `(√2) · m`.
- Commentaires avec `#` ou `//`, en début ou en fin de ligne.
- Les symboles respectent la casse : `g` et `G` sont différents. Les noms de variables peuvent comporter des lettres, des chiffres et `_`, sans commencer par un chiffre. Un nom de fonction reste utilisable comme variable (`max = 10 m`) : c’est un appel seulement quand il est suivi de `(`, comme dans `max(a; b)`.
- Unités SI de base et dérivées, préfixes SI, `min`, `h`, `L`, `bar`, `eV`, `rad`, `deg`, et les unités ci-dessous. Utiliser `K` pour la température absolue : `°C` et `°F` sont refusés avec une explication. Les puissances d’unités s’écrivent `m²` ou `m^2` (`m2` est signalé).

### Fonctions

| Fonction | Rôle |
| --- | --- |
| `sqrt` (ou `√`), `cbrt`, `root(x; n)` | racines |
| `abs`, `exp`, `ln`, `log` / `log10`, `log(x; base)` | valeur absolue, exponentielle, logarithmes |
| `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2(y; x)` | trigonométrie ; les angles sont en radians |
| `sinh`, `cosh`, `tanh` | hyperboliques |
| `min`, `max` (2 à 50 arguments de même dimension) | extrema |
| `floor`, `ceil`, `round` | arrondis d’une valeur sans dimension |

Les fonctions à plusieurs arguments séparent ceux-ci par un **point-virgule**, car la virgule est le séparateur décimal : `max(2,5; 3)` vaut **3**. `min(2,3)` est une erreur expliquée (`2,3` est un nombre). Les fonctions trigonométriques et logarithmiques exigent un argument sans dimension ; `asin`, `acos`, `atan` et `atan2` renvoient des radians (`asin(0,5) → °` affiche **30°**). `sin(30)` fonctionne mais ajoute la note « Angle interprété en radians » ; écrire `sin(30 deg)` ou `sin(30°)` pour des degrés. Les angles remarquables sont exacts : `cos(90 deg)` et `sin(pi)` valent **0**. `min` seul reste la minute : `5 min` vaut **300 s**.

`root(27; 3)` vaut **3**, `log(8; 2)` vaut **3**, `atan2(1; 1) → °` affiche **45°**.

### Convertir l’affichage

`expr -> unité` ou `expr → unité`, à la fin d’une ligne et avant son commentaire, convertit **l’affichage** d’une expression, d’une déclaration ou d’une comparaison. Les variables restent en SI : seul le résultat de la ligne change.

```text
v = 20 m/s → km/h
```

Résultat : **72 km/h**.

```text
E = 3,6e6 J
E → kWh
```

Résultat de la seconde ligne : **1 kWh**. Les cibles acceptent les unités, puis les constantes (`c`, `au`), jamais les variables de la feuille : `m`, `h` et `g` désignent donc le mètre, l’heure et le gramme. Elles acceptent aussi `*`, `/`, `^n`, les produits implicites, les parenthèses et un `1/` initial : `m_e*c^2 -> MeV` donne **0,510999 MeV**, `3000 rpm -> rad/s` donne **314,159 rad/s** et `0,35 -> %` donne **35 %**.

Sans conversion, une grandeur en `s⁻¹` s’affiche `s⁻¹`, jamais `Hz` : `f = 50 s⁻¹ → Hz` affiche **50 Hz**, et `rad/s`, `Bq` ou `tr/min` se choisissent de même. Dans l’application, le menu contextuel d’une ligne (**Afficher en**) et le sélecteur du même nom de l’éditeur écrivent cette flèche à votre place ; **Unités SI** la retire. Écrire `E in kJ` renvoie un message qui suggère `→`. `rad` et `tr` sont sans dimension (un tour vaut 2π rad) : `Hz` et `tr/min` ne se convertissent donc pas comme des cycles par seconde, et `50 Hz → tr/min` affiche **477,465 tr/min** (et non 3000). Gardez `Hz` pour les fréquences, et `rad/s` ou `tr/min` pour les vitesses angulaires.

### Unités

En plus des unités SI et de leurs préfixes, Eval reconnaît :

- pression : `atm`, `Torr`, `mTorr`, `mmHg`, `mbar`, `kbar`, `hPa` ;
- énergie : `cal`, `kcal`, `Wh`, `mWh`, `kWh`, `MWh`, `GWh`, `TWh` ; charge : `Ah`, `mAh` ;
- longueur : `Å`, `ly`, `pc`, `kpc`, `Mpc`, `Gpc`, `ft`, `mi` ;
- masse : `Da`, `kDa`, `MDa`, `lb` ; force : `lbf` ;
- temps et rotation : `jour`, `an` (aussi `yr` et `year`, année julienne de 365,25 jours), `tr`, `rpm` ;
- rapports : `%`, `ppm` ; volumes : `ml`, `cl`, `dl`, `hl`, `kl`, `µl` ; résistance : `kohm`, `Mohm`.

`1 atm` vaut **101325 Pa**, `1 kWh` vaut **3600000 J**, `1 mi` vaut **1609,344 m**, `1 an → jour` affiche **365,25 jour**.

**Ne sont pas des unités** : `t`, `d`, `a`, `u`, `j`, `in`, `kn`, `psi` et `G` (constante de gravitation). Ces noms restent libres pour des variables (`t = 3 s`, `d = 2 m`, `u = 5 V`) ; `1 t` signale un symbole inconnu. L’onglet **Références › Unités** donne la liste complète.

Les chaînes d’unités compactes `72km/h` et `3g/cm³` sont lues comme des unités, sauf si l’un de leurs symboles est déclaré comme variable (avec `g = 2 m/s²`, `3g/cm³` redevient un calcul). Un `3g` isolé vaut 3 × `g`.

### Distinguer unités et variables

Un espace entre un nombre et un symbole connu d’unité force l’unité : `5 m` est une longueur même si `m = 80 kg` représente une masse ailleurs. Sans cet espace, `2m` utilise la variable déclarée ; à défaut, les constantes puis les unités sont recherchées.

Les opérateurs **sans espaces** prolongent le suffixe d’unités : `2 kg*m/s²` est une force. Les opérateurs **avec espaces** reviennent au calcul sur les variables : `2 m/s² * m`, avec `m = 3 kg`, donne **6 N**. Pour une formule, utiliser explicitement `*` entre les variables.

### Pourcentage et factorielle

`35 %` vaut **0,35** : le pourcentage est un nombre sans dimension, donc `P * 15 %` avec `P = 200 W` donne **30 W**. `0,35 -> %` affiche le contraire.

`n!` calcule la factorielle d’un entier sans dimension entre 0 et 170 : `5!` vaut **120**, et avec `n = 6`, `n!` vaut **720**. `2,5!` et `171!` sont des erreurs expliquées. `5 != 3` est refusé avec un message qui invite à utiliser `==` ; le signe `≠` n’existe pas.

### Exponentielle

Si `e` n’est pas déclaré, il désigne la charge élémentaire : `e^(0,5)` est donc refusé, avec le conseil d’écrire `exp(0,5)` (**1,64872**). Une puissance entière comme `e^2` reste acceptée ; pour l’exponentielle, utiliser `exp`.

### Résoudre une inconnue

Écrire `v = ? m/s` déclare une inconnue et son unité. Avec **exactement une relation** (`==`, ou `=` qui n’est pas une déclaration) qui contient `v`, directement ou par les déclarations dont elle dépend, Eval cherche **numériquement** la valeur qui vérifie la relation.

```text
E = 1000 J
m = 80 kg
v = ? m/s
E == 0,5 * m * v²
```

Résultat de `v` : **5 m/s**, avec la note « Autre solution : -5 m/s. ». La relation affiche ensuite « Égalité vérifiée. ». La recherche balaie les valeurs de 10⁻¹² à 10¹², aux deux signes, affiche la plus petite racine positive et signale une autre solution. Ce n’est pas une résolution symbolique : une seule inconnue par relation, aucune manipulation d’expression, et une erreur explicite lorsqu’aucune ou plusieurs relations contiennent l’inconnue.

Autre exemple : avec `T = 2 s`, `l = ? m` et `T == 2 * pi * sqrt(l / g)`, la longueur du pendule vaut **0,993621 m**.

## Homogénéité

Les quantités portent les sept dimensions de base du SI. La multiplication, la division et les puissances composent ces dimensions. Les additions et soustractions exigent des dimensions identiques : `2 m + 3 s` affiche une erreur.

Le signe `=` déclare une variable lorsque le membre gauche est un nom. Utiliser `==` pour vérifier une relation : les dimensions des deux membres sont comparées, puis leur égalité numérique avec une tolérance relative de `1e-10`, qui tient compte des erreurs d’annulation (`0,1 + 0,2 - 0,3 == 0` est vérifié).

```text
F == m * a
F = 14,4 N
m = 2 kg
a = 7,2 m/s²
```

La relation est homogène et l’égalité est vérifiée. Une dimension cohérente et une valeur numérique égale sont deux vérifications distinctes. Une simple multiplication affiche sa dimension, sans prétendre valider une loi physique.

Sans unité, une valeur est considérée comme sans dimension : renseigner les unités pour une vérification physique utile. Eval effectue l’évaluation numérique de variables définies et la résolution numérique d’une inconnue ; la résolution symbolique, les unités avec décalage (°C, °F) et la propagation des incertitudes ne sont pas implémentées. Les valeurs utilisent `Double`. Les résultats s’affichent avec six chiffres significatifs (les nombres entiers inférieurs à 10⁹ gardent tous leurs chiffres) ; les calculs, les valeurs saisies, les constantes de Références et les messages d’égalité non vérifiée en gardent dix.

Les erreurs de syntaxe, variables inconnues (avec un renvoi vers **Références › Unités**), doublons, dépendances circulaires, domaines de fonctions, divisions par zéro et dépassements numériques sont signalés par ligne. Si la déclaration dont dépend une ligne est en erreur, cette ligne l’indique (« La déclaration de « x » (ligne 1) contient une erreur. »). Des limites de taille et de profondeur protègent l’éditeur des expressions excessives.

## Structure et validation

- `EvalApp/` : interface native SwiftUI (`NavigationSplitView`, `TabView`, `NavigationStack`, `List`, `Form`, `TextEditor`, Swift Charts, menus et présentations système) : liste et fenêtres de feuilles, éditeur de lignes, réglettes, tracés, Références, aide, et chaînes localisables dans `Localizable.xcstrings`.
- `Sources/EvalCore/` : moteur indépendant de SwiftUI.
  - Analyse et calcul : `ExpressionParser`, `NotebookEngine` (graphe de dépendances), `RootSearch` (résolution numérique), `Quantity`, `Dimension`, `Catalogs` (constantes et unités), `LineSyntax` (corps, flèche `→` et commentaire d’une ligne).
  - Feuilles : `SheetRecord` (une feuille et ses choix de résultats et de réglettes), `SheetRepository` (un fichier JSON par feuille), `LegacyNotebookMigration` (reprise de l’ancienne feuille unique), `ExampleLibrary` (les 22 exemples), `SheetLineEditing` (copie et partage), `ResultSelection`.
  - Édition : `MathFormula` (fractions, puissances, racines), `FormulaInsertion` (insertion au curseur), `AdjustableVariable` (réglettes et pas).
  - Tracé et accessibilité : `VariableSweep` (échantillonnage d’un résultat en fonction d’une variable), `MathSpeech` (lecture parlée des formules).
- `Tests/EvalCoreTests/` : tests du moteur et des catalogues (calcul, conversions, fonctions, résolution, diagnostics, formats, exemples, feuilles, réglettes, lecture parlée, tracé).
- `Scripts/generate-app-icon.swift` : dessin de l’icône (parabole au-dessus d’une réglette) en tracés vectoriels, sans SF Symbol, avec ses variantes claire, sombre et teintée.

```sh
swift test
xcodebuild -project Eval.xcodeproj -scheme Eval \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/eval-derived CODE_SIGNING_ALLOWED=NO build
```

`swift test` exécute les tests de `EvalCore` ; la commande `xcodebuild` vérifie que l’application compile pour le simulateur. Les 22 exemples intégrés sont eux-mêmes testés : chacun doit s’évaluer sans erreur.

Les constantes physiques et chimiques embarquées proviennent des [valeurs CODATA 2022 du NIST](https://physics.nist.gov/cuu/pdf/all.pdf). Les constantes définissant le SI suivent la [Brochure sur le SI du BIPM](https://www.bipm.org/fr/publications/si-brochure), et la pesanteur standard les [valeurs conventionnelles adoptées](https://physics.nist.gov/cuu/pdf/adopted_2002.pdf). Les références astronomiques suivent les résolutions de l’Union astronomique internationale, qui fixent notamment des grandeurs nominales ; les références mathématiques proviennent du DLMF du NIST. Chaque entrée du catalogue conserve sa source. Les dimensions et préfixes suivent le [Système international d’unités](https://www.nist.gov/pml/special-publication-330).
