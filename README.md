# Eval

Calculatrice iOS de physique en SwiftUI : une feuille de formules littérales, des variables et des unités, avec calcul automatique et analyse dimensionnelle. Fonctionne hors ligne sur iPhone et iPad (iOS 17 ou plus).

## Démarrer

Ouvrir `Eval.xcodeproj` dans Xcode, choisir le schéma **Eval** et lancer sur un simulateur iPhone ou iPad. Pour un appareil physique, sélectionner son équipe de signature dans **Signing & Capabilities**. Le moteur `EvalCore` est un package Swift local, sans dépendance externe.

## Utilisation

Une formule, une variable ou une comparaison par ligne. Les déclarations sont résolues à l’échelle de la feuille : leur ordre n’a pas d’importance, et une variable peut dépendre d’une autre variable déclarée plus bas.

```text
# Énergie cinétique
E = 0,5 * m * v²
m = 80 kg
v = 5 m/s
E
```

Résultat : **1 000 J**. La virgule et le point décimaux sont acceptés, ainsi que la notation scientifique (`1,5e-3`). Les résultats sont convertis en unités SI.

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

L’onglet **Références** permet de chercher les constantes et unités par nom ou symbole, et de filtrer les constantes par domaine. Déplier une constante affiche son identifiant de **Saisie**, sa valeur SI, sa nature et un lien vers sa source. **Ajouter à la feuille** insère son identifiant de calcul. Les valeurs sont incluses dans l’application et restent disponibles hors ligne.

La nature **Exacte** décrit une valeur définie ou dérivée d’une définition, **Mesurée** une valeur expérimentale, et **Conventionnelle** une référence adoptée, comme la pesanteur standard ou une grandeur astronomique nominale. L’affichage et le calcul conservent la précision finie de `Double`, y compris pour les constantes exactes. Les constantes mesurées utilisent leur valeur centrale ; les incertitudes ne sont pas propagées.

Le menu propose des exemples, le partage et l’effacement avec confirmation. La feuille est sauvegardée automatiquement sur l’appareil.

### Choisir les résultats à afficher

Dans **Résultats → Choisir**, activer uniquement les lignes souhaitées. Le choix est aussi disponible avec **Afficher dans Résultats** dans l’éditeur d’une ligne et dans son menu contextuel. Une ligne masquée reste disponible pour les calculs qui en dépendent. Les choix sont sauvegardés avec des identités de ligne pour suivre les déplacements et les modifications ; les nouvelles lignes saisies en mode Texte commencent masquées.

À la première ouverture et lors du chargement d’un exemple, les expressions et comparaisons sont affichées ; les déclarations de variables sont masquées. Les erreurs restent visibles sur les lignes en mode Formules ou dans **À corriger** en mode Texte, même lorsqu’un résultat est masqué.

### Ajuster les valeurs avec un curseur

Les déclarations numériques comme `a = 7,2 m/s²`, `v = 72 km/h` ou `x = -3` proposent une **réglette graduée**, avec un repère central fixe et des graduations mobiles, inspirée du réglage des nombres dans Notes. Glisser horizontalement modifie le nombre dans la feuille et recalcule les résultats pendant le mouvement. En mode **Texte**, les réglettes sont regroupées dans **Ajuster les variables**.

Le **pas automatique** suit la précision du nombre saisi : `6` → `1`, `8,2` → `0,1`, `8,25` → `0,01`, `8,20` → `0,01` et `1,2e3` → `100`. Cette précision est conservée pendant le glissement, y compris lorsque `8,2` atteint `9,0`. Le bouton de réglage permet de définir **minimum et maximum**, ou de désactiver le pas automatique pour choisir un **pas manuel**, sauvegardé avec l’identité de la ligne. Les unités, espaces et commentaires sont conservés. Les variables définies par des expressions restent éditables par l’éditeur de formules et se recalculent à partir des variables ajustées.

La réglette utilise une petite composition SwiftUI (Canvas et DragGesture), nécessaire au repère fixe et au réglage relatif, avec le matériau système ou Liquid Glass sur iOS 26 et plus. Le défilement vertical de la feuille reste disponible ; les variables se suppriment par leur menu contextuel. VoiceOver ajuste les valeurs avec le même pas.

### Écriture mathématique

Le mode **Formules** affiche les divisions comme des fractions, les puissances en exposant et les racines carrées avec leur signe. Toucher une ligne pour l’éditer ou **Ajouter une formule** pour en créer une. L’éditeur fournit un aperçu en direct et des boutons **Fraction**, **Puissance** et **Racine carrée**, avec des champs pour les opérandes. Une construction peut remplacer l’expression ou se combiner avec elle ; le membre gauche d’une déclaration ou d’une comparaison est conservé.

Par exemple, pour `E = h * c / lambda`, choisir Fraction, mettre `h * c` au numérateur et `lambda` au dénominateur. Le résultat est présenté avec une barre de fraction, tout en conservant la syntaxe de calcul existante. Le mode **Texte** reste disponible pour modifier la feuille entière et pour le partage.

Le rendu mathématique est composé en SwiftUI, s’adapte à Dynamic Type et défile horizontalement pour les expressions longues. Il ne nécessite pas de WebView, de bibliothèque de rendu ou de connexion réseau.

## Syntaxe

- Opérateurs : `+`, `-`, `*`, `/`, `^`, ainsi que `−`, `×`, `÷`, `·` et les exposants Unicode (`²`, `³`, `⁻¹`…). Les puissances sont associatives à droite : `2^3^2 = 512` ; `-2^2 = -4`.
- Parenthèses et multiplication implicite : `2a`, `3(a+1)`.
- Fonctions à un argument : `sqrt`, `abs`, `sin`, `cos`, `tan`, `exp`, `ln` (logarithme naturel), `log` / `log10` (base 10). Les angles sont en radians ; `sin(30 deg)` accepte les degrés.
- Unités SI de base et dérivées, préfixes SI, `min`, `h`, `L`, `bar`, `eV`, `rad`, `deg`. Utiliser `K` pour la température absolue.
- Commentaires avec `#` ou `//`, en début ou en fin de ligne.
- Les symboles respectent la casse : `g` et `G` sont différents. Les noms de variables peuvent comporter des lettres, des chiffres et `_`, sans commencer par un chiffre.

### Distinguer unités et variables

Un espace entre un nombre et un symbole connu d’unité force l’unité : `5 m` est une longueur même si `m = 80 kg` représente une masse ailleurs. Sans cet espace, `2m` utilise la variable déclarée ; à défaut, les constantes puis les unités sont recherchées.

Les opérateurs **sans espaces** prolongent le suffixe d’unités : `2 kg*m/s²` est une force. Les opérateurs **avec espaces** reviennent au calcul sur les variables : `2 m/s² * m`, avec `m = 3 kg`, donne **6 N**. Pour une formule, utiliser explicitement `*` entre les variables.

## Homogénéité

Les quantités portent les sept dimensions de base du SI. La multiplication, la division et les puissances composent ces dimensions. Les additions et soustractions exigent des dimensions identiques : `2 m + 3 s` affiche une erreur.

Le signe `=` déclare une variable lorsque le membre gauche est un nom. Utiliser `==` pour vérifier une relation : les dimensions des deux membres sont comparées, puis leur égalité numérique avec une tolérance relative de `1e-10`.

```text
F == m * a
F = 14,4 N
m = 2 kg
a = 7,2 m/s²
```

La relation est homogène et l’égalité est vérifiée. Une dimension cohérente et une valeur numérique égale sont deux vérifications distinctes. Une simple multiplication affiche sa dimension, sans prétendre valider une loi physique.

Sans unité, une valeur est considérée comme sans dimension : renseigner les unités pour une vérification physique utile. Eval effectue l’évaluation numérique de variables définies ; la résolution symbolique d’une inconnue, les unités avec décalage (°C, °F) et la propagation des incertitudes ne sont pas implémentées. Les valeurs utilisent `Double`, avec dix chiffres significatifs à l’affichage.

Les erreurs de syntaxe, variables inconnues, doublons, dépendances circulaires, domaines de fonctions, divisions par zéro et dépassements numériques sont signalés par ligne. Des limites de taille et de profondeur protègent l’éditeur des expressions excessives.

## Structure et validation

- `EvalApp/` : interface native SwiftUI (`TabView`, `NavigationStack`, `List`, `TextEditor`, menus et présentations système), sauvegarde et exemples.
- `Sources/EvalCore/` : analyseur syntaxique, résolution des dépendances, quantités, dimensions et catalogues, indépendants de SwiftUI.
- `Tests/EvalCoreTests/` : tests du moteur et des catalogues.
- `Scripts/generate-app-icon.swift` : reproduction de l’icône avec le SF Symbol système `function` sur macOS.

```sh
swift test
xcodebuild -project Eval.xcodeproj -scheme Eval \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/eval-derived CODE_SIGNING_ALLOWED=NO build
```

Les constantes physiques et chimiques embarquées proviennent des [valeurs CODATA 2022 du NIST](https://physics.nist.gov/cuu/pdf/all.pdf). Les constantes définissant le SI suivent la [Brochure sur le SI du BIPM](https://www.bipm.org/fr/publications/si-brochure), et la pesanteur standard les [valeurs conventionnelles adoptées](https://physics.nist.gov/cuu/pdf/adopted_2002.pdf). Les références astronomiques suivent les résolutions de l’Union astronomique internationale, qui fixent notamment des grandeurs nominales ; les références mathématiques proviennent du DLMF du NIST. Chaque entrée du catalogue conserve sa source. Les dimensions et préfixes suivent le [Système international d’unités](https://www.nist.gov/pml/special-publication-330).
