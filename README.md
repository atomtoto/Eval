# Eval

Calculatrice iOS de physique en SwiftUI : des feuilles de formules littérales, des variables et des unités, avec calcul automatique, analyse dimensionnelle, conversion d’affichage, simplification des formules, résolution des équations (exacte pour les polynômes jusqu’au degré 2, numérique au-delà) et lecture des formules écrites à la main ou photographiées. Fonctionne hors ligne sur iPhone et iPad (iOS 17 ou plus ; écriture manuscrite à partir d’iOS 18).

## Démarrer

Ouvrir `Eval.xcodeproj` dans Xcode, choisir le schéma **Eval** et lancer sur un simulateur iPhone ou iPad. Pour un appareil physique, sélectionner son équipe de signature dans **Signing & Capabilities**. Le moteur `EvalCore` est un package Swift local, sans dépendance externe. Les tests du moteur s’exécutent avec `swift test` (voir [Structure et validation](#structure-et-validation)).

Au premier lancement, **Nouvelle feuille** ouvre une feuille vide et **Nouvelle à partir d’un exemple** propose des feuilles prêtes à modifier. Une feuille créée par une version précédente d’Eval est reprise automatiquement.

## Utilisation

Une formule, une variable ou une comparaison par ligne, sur une seule page. Une ligne terminée par `=` affiche sa valeur, comme dans Notes (voir [Résultats sur la ligne](#résultats-sur-la-ligne)). Les déclarations sont résolues à l’échelle de la feuille : leur ordre n’a pas d’importance, et une variable peut dépendre d’une autre variable déclarée plus bas.

```text
# Énergie cinétique
E = 0,5 * m * v²
m = 80 kg
v = 5 m/s
E =
```

La dernière ligne affiche **E = 1000 J**. La virgule et le point décimaux sont acceptés, ainsi que la notation scientifique (`1,5e-3`). Les nombres s’affichent sans séparateur de milliers. Les résultats sont en unités SI, sauf si l’on demande une autre unité avec `→` (voir [Convertir l’affichage](#convertir-laffichage)).

```text
# Distance depuis le repos
d = 0,5 * a * t²
t = 3 s
a = 7,2 m/s²
d =
```

Résultat : **32,4 m**.

Les constantes non déclarées sont reconnues, et leur valeur est listée sous la feuille. Le catalogue couvre les constantes fondamentales, l’électromagnétisme, la physique quantique, la thermodynamique, la chimie, l’astronomie et les mathématiques. Par exemple : `c`, `g`, `G`, `h`, `hbar` / `ℏ`, `e`, `k_B`, `N_A`, `R`, `epsilon_0` / `ε₀`, `mu_0` / `μ₀`, `pi` / `π`, `m_e`, `m_p`, `alpha` / `α`. Une déclaration explicite remplace la constante dans toute la feuille. `g` représente la pesanteur standard ; sa valeur locale peut varier.

```text
# Énergie d’un photon
h * c / lambda =
lambda = 550 nm
```

Résultat : **3,61172 × 10⁻¹⁹ J**. Les constantes utilisées sont listées dans la section **Constantes reconnues** de la feuille.

L’onglet **Références** permet de chercher les constantes et unités par nom, symbole ou domaine. Le sélecteur **Constantes / Unités** de la barre d’outils change de catalogue, et le menu **Domaine** filtre les constantes. Toucher une constante ouvre sa page : valeur SI, identifiant de **Saisie**, alias, **Nature** et lien vers la source. **Ajouter à la feuille** (bouton de la page, glissement vers la droite ou menu contextuel) insère son identifiant dans la feuille de la fenêtre courante ; le menu contextuel permet aussi de copier la valeur ou l’identifiant. Les valeurs sont incluses dans l’application et restent disponibles hors ligne.

La nature **Exacte** décrit une valeur définie ou dérivée d’une définition, **Mesurée** une valeur expérimentale, et **Conventionnelle** une référence adoptée, comme la pesanteur standard ou une grandeur astronomique nominale. L’affichage et le calcul conservent la précision finie de `Double`, y compris pour les constantes exactes. Les constantes mesurées utilisent leur valeur centrale ; les incertitudes ne sont pas propagées.

### Plusieurs feuilles

L’onglet **Calcul** ouvre la liste **Feuilles**, de la plus récente à la plus ancienne, avec le titre, la date relative et le premier résultat de chaque feuille. Le champ de recherche filtre par titre ou par contenu. Une feuille sans titre choisi prend le nom de sa première note `# …`.

- **Nouvelle feuille** (⌘N avec un clavier) crée une feuille vide.
- **Nouvelle à partir d’un exemple** propose 23 feuilles vérifiées, groupées en Mécanique, Électricité, Optique et ondes, Thermodynamique, Quantique, Astronomie et Méthode. Un exemple s’ouvre toujours dans une nouvelle feuille et ne remplace jamais un travail en cours.
- Un appui long sur une feuille propose **Renommer**, **Dupliquer**, **Partager** et **Supprimer**. La suppression, aussi disponible par glissement ou avec **Modifier**, demande toujours une confirmation.
- Dans une feuille ouverte, toucher le **titre** en haut ouvre le menu de titre du système : **Renommer** ouvre l’alerte de renommage, **Dupliquer** ouvre une copie et **Partager la feuille** envoie son texte. **Renommer** est aussi dans le menu **Actions de la feuille** ; un titre vide rend à la feuille son nom automatique.
- **Nom automatique** (iOS 26 ou plus, avec Apple Intelligence) : la première fois qu’on quitte une feuille encore nommée « Nouvelle feuille » (ni titre choisi ni note `#`) et assez remplie, retour à la liste, autre feuille ou passage en arrière-plan, le modèle sur l’appareil (Foundation Models, génération guidée) propose un titre de 2 à 5 mots, comme « Chute libre ». Le titre apparaît dans la liste un instant plus tard, sauf si la feuille a été renommée entre-temps. Une feuille n’est nommée qu’une fois, et une feuille renommée par l’utilisateur ne l’est jamais. Les échecs sont silencieux. Le contenu de la feuille ne quitte pas l’appareil. Le réglage **Nommer les feuilles automatiquement** (activé par défaut) le désactive ; sans Apple Intelligence, il est grisé et indique pourquoi.
- Chaque feuille est enregistrée dans un fichier JSON du dossier Application Support de l’appareil. Une feuille de plus de 500 lignes ou 100 000 caractères est refusée avec un message d’erreur. Si ce dossier est indisponible, Eval garde les feuilles en mémoire sans écrire ailleurs et affiche une alerte : elles seraient perdues à la fermeture.

### Résultats sur la ligne

Comme dans Notes, une ligne terminée par `=` affiche sa valeur sur la même ligne, en couleur : `E =` affiche `E = 1000 J`, `E = 0,5 * m * v² =` définit `E` et affiche sa valeur, `m * v =` affiche la valeur de l’expression. Une ligne avec une conversion (`v → km/h`) ou une inconnue (`v = ? m/s`) affiche toujours sa valeur ; une égalité `==` affiche son verdict. Les autres lignes sont calculées sans afficher de valeur, et leurs erreurs restent signalées sous la ligne. Après une équation, `x =` affiche toutes ses solutions (voir [Résoudre une équation](#résoudre-une-équation)). Si la place manque, la valeur passe sous la formule. Pendant qu’une ligne est modifiée, sa valeur se met à jour en direct ; une valeur calculée pour un texte précédent est grisée. Toucher une valeur ouvre le menu de la ligne.

Les feuilles enregistrées avant cette version, où les résultats affichés étaient choisis un par un, sont converties à l’ouverture : chaque ligne qui affichait son résultat reçoit un `=` final.

Les symboles non déclarés qu’Eval a lus comme des unités (par exemple `T` comme tesla dans `F = 2 * T`) sont listés dans **Symboles lus comme des unités**. Si ce sont en réalité des variables, il suffit de les déclarer.

### Ajuster les valeurs avec un curseur

La valeur des déclarations numériques comme `a = 7,2 m/s²`, `v = 72 km/h` ou `x = -3` est teintée et soulignée. Un **appui long** sur cette valeur fait apparaître une **réglette graduée**, avec un repère central fixe et des graduations mobiles, dans une **bulle** (`popover`) ancrée à la valeur, comme un menu d’appui long ; la bulle montre aussi la valeur en toutes lettres (`m = 80 kg`) et le bouton de réglage. Toucher en dehors la ferme, l’édition d’une ligne ou **Réorganiser** aussi, et une seule réglette est ouverte à la fois. Comme la molette de Photos, les graduations suivent le doigt et glisser vers la **gauche augmente** la valeur. La réglette est **infinie** : elle n’a pas de bornes, passe par zéro vers les valeurs négatives et peut dépasser n’importe quel multiple de la valeur d’origine. Le nombre est modifié dans la feuille et les résultats sont recalculés pendant le mouvement. Un simple toucher sur la valeur modifie la ligne.

Le **pas automatique** suit la précision du nombre saisi : `6` → `1`, `8,2` → `0,1`, `8,25` → `0,01`, `8,20` → `0,01` et `1,2e3` → `100`. Cette précision est conservée pendant le glissement, y compris lorsque `8,2` atteint `9,0`, et la réglette n’écrit pas de bruit binaire du type `0,9199999999999999`. Le bouton de réglage permet de désactiver le pas automatique pour choisir un **pas manuel**, et de définir l’**intervalle du graphique** (minimum et maximum, clavier numérique) ; les deux sont sauvegardés avec l’identité de la ligne. Les bornes de l’intervalle ne limitent pas la réglette. Les unités, espaces et commentaires sont conservés. Les variables définies par des expressions se modifient en touchant leur ligne et se recalculent à partir des variables ajustées.

La réglette utilise une petite composition SwiftUI (Canvas et DragGesture), nécessaire au repère fixe et au réglage relatif, avec le matériau système ou Liquid Glass sur iOS 26 et plus. Le défilement vertical de la feuille reste disponible. Avec VoiceOver, la valeur elle-même est ajustable, au même pas et sans bornes, et l’action **Afficher la réglette** ouvre la bulle.

### Tracer un résultat

Pour une ligne calculée (expression ou définition), le menu de la ligne propose **Tracer en fonction de** puis le nom d’une variable à réglette dont le résultat dépend. La courbe couvre l’**intervalle du graphique** de la variable (par défaut de 0 à deux fois sa valeur, ou de −10 à 10 pour zéro), modifiable par ses réglages ; une ligne pointillée marque la valeur actuelle et toucher le graphique lit une valeur. Les points où le calcul échoue (racine d’un nombre négatif, division par zéro) laissent un trou dans la courbe. Si le résultat est affiché avec `→`, le tracé suit cette unité.

### Simplifier une formule

Un appui long sur une formule qui peut s’écrire plus simplement montre, au-dessus de son menu, sa **forme simplifiée** en écriture mathématique ; l’action **Simplifier**, en tête du menu, réécrit la ligne (une étape d’annulation). Sinon le menu reste le même. La simplification est symbolique et exacte : les nombres sont calculés en fractions (`0,1 + 0,2` → `0,3`, `x / 3 + x / 6` → `x / 2`), les termes semblables regroupés (`2x + 3x` → `5x`), les facteurs communs simplifiés (`E = 0,5 * m * v^2 * 2 / m` → `E = v²`), les puissances fusionnées (`x * x * x` → `x³`), les racines réduites (`sqrt(12)` → `2√3`), les sommes développées quand le résultat est plus court (`x(x + 1) - x^2` → `x`), les fractions rationnelles d’une seule variable réduites (`(x^2 - 1) / (x - 1)` → `x + 1`), et les valeurs évidentes appliquées (`sin(x)^2 + cos(x)^2` → `1`, `ln(exp(t))` → `t`). Une forme n’est proposée que si elle est plus courte, ou de même longueur avec des nombres plus petits ; `(a + b)^2` reste factorisé. Le nom déclaré, la flèche `→`, le `=` final et le commentaire sont conservés, et les deux membres d’une égalité sont simplifiés séparément. Les unités restent des unités (`2 m + 3 m` → `5 m`). La forme proposée est relue par l’analyseur et doit redonner la même expression, sinon rien n’est proposé. Comme dans tout système de calcul formel, `x / x` devient `1` sans réserver le cas `x = 0`.

### Écriture mathématique

La feuille affiche les divisions comme des fractions, les puissances en exposant et les racines carrées avec leur signe. Les notes `# …` s’affichent comme des titres, les notes `// …` comme du texte secondaire. Toucher une ligne la transforme sur place en champ de texte ; elle reprend sa notation mathématique dès qu’on la quitte. **Retour** valide la ligne et crée une nouvelle ligne en dessous, avec le clavier. La dernière ligne **Nouvelle ligne**, comme le bouton **+**, ajoute une ligne à la fin. Toute la saisie d’une ligne forme une seule étape d’annulation.

Avec le réglage **Écriture mathématique**, la ligne touchée se modifie telle qu’elle s’affiche, sans passer par le texte. `/` fait du terme qui précède le numérateur d’une fraction et place le curseur au dénominateur, `^` ouvre un exposant. La barre du clavier propose **xⁿ**, **√**, **◀** et **▶** ; son menu **Insérer** ajoute **Fraction**, **Racine n-ième**, `²`, `⁻¹`, **Monter** / **Descendre** (du dénominateur au numérateur, dans ou hors d’un exposant), `=`, `×`, `π`, `deg`, les variables de la feuille et **Constantes et unités…**. Toucher la formule place le curseur du côté le plus proche du symbole touché ; une case vide est marquée d’un cadre pointillé. L’effacement entre dans une fraction ou une racine, puis la défait quand elle est vide. Les flèches d’un clavier matériel déplacent le curseur. **Retour** valide la ligne et en crée une nouvelle en dessous, toujours en écriture mathématique, et la valeur se met à jour pendant la saisie. Un commentaire `#` de fin de ligne est conservé et affiché sous la formule ; pour le modifier, passer par la saisie texte ou **Modifier en texte**. Avec VoiceOver, la ligne est lue comme une expression, la position du curseur (« Au dénominateur », « Fin de ligne »…) est donnée comme valeur, et les touches de structure sont des actions.

**Modifier en texte**, dans le menu **Actions de la feuille**, ouvre la feuille entière dans un champ multiligne (**Annuler** / **Terminé**) ; la modification s’applique en une seule étape d’annulation. **Réglages** (même menu, bouton engrenage de la liste des feuilles, ou ⌘,) choisit la **Saisie des formules** (dans la ligne en texte, ou en écriture mathématique) et le nombre de **chiffres significatifs** des résultats (3 à 12, 6 par défaut), la **couleur d’accent** (**Orange industriel** `#DD5500` en clair et `#F7701F` en sombre, par défaut, ou **Bleu**, le bleu système), le **Fond chaud** (activé par défaut), **Nommer les feuilles automatiquement** (iOS 26 ou plus, activé par défaut) et le style de l’**icône de l’app** (**Lentille** ou **Point**), qui suit la couleur d’accent. La couleur d’accent est la teinte (`.tint`) de toute l’app : valeurs, boutons, réglette, tracés, onglets et alertes ; l’orange est aussi le `AccentColor` du catalogue d’assets. Le fond chaud, en mode clair seulement, donne aux feuilles (page, constantes, tracés, aide, réglages, Références) un fond crème `WarmBackground` (`#F5F3EE`) sous des lignes d’un blanc chaud `WarmRow` (`#FBFAF7`), avec les listes, sections et séparateurs natifs ; le mode sombre et la liste des feuilles ne changent pas. Pendant la saisie d’une ligne, une barre en verre (Liquid Glass dès iOS 26, matériau système avant) flotte à environ 10 pt au-dessus du clavier avec le menu **Insérer**, les touches courantes et **Terminé**, toujours visible, en saisie texte comme en écriture mathématique.

Le rendu mathématique est composé en SwiftUI, s’adapte à Dynamic Type et défile horizontalement pour les expressions longues. Il ne nécessite pas de WebView, de bibliothèque de rendu ou de connexion réseau.

### Clavier et symboles

Au-dessus du clavier, une barre insère à l’emplacement du curseur `+`, `−`, `×` et des parenthèses `( )`. Son menu **Insérer** propose les modèles **Fraction**, **Puissance** et **Racine**, qui entourent la sélection (`(a + b)/()`), et ajoute `=`, `÷`, `^`, `²`, `³`, `⁻¹`, `π` et `deg`, les variables de la feuille, ou ouvre **Constantes et unités…**, un sélecteur avec recherche qui insère le nom choisi. L’insertion à la position du curseur nécessite iOS 18 ; sous iOS 17, le symbole est ajouté en fin de texte. Le bouton **Terminé** ferme le clavier.

### Écrire à la main ou photographier

**Écrire à la main** (appui long sur **+**, menu **Actions de la feuille** ou feuille vide ; iOS 18 ou plus) ouvre une page où écrire avec l’Apple Pencil ou le doigt, une formule par ligne, avec la palette d’outils PencilKit (stylo, gomme, lasso, annulation). Le menu caméra propose aussi **Scanner une page** (scanner de documents VisionKit, qui détecte et redresse la page) et **Choisir une photo** (sélecteur Photos du système, sans accès à la photothèque entière). **Lire** reconnaît les formules, puis l’écran **Vérifier les lignes** montre chaque ligne lue, modifiable, avec son aperçu mathématique ou l’indication « À corriger » ; un glissement vers la gauche supprime une ligne. **Ajouter** les place à la fin de la feuille, en une étape d’annulation.

La lecture se fait sur l’appareil, sans réseau :

- la reconnaissance de texte de Vision lit les caractères ; Eval reconstruit les **exposants** d’après la position et la taille des chiffres (un 2 écrit petit et en haut après `x` devient `x²`), et les **fractions** d’après les barres horizontales avec du texte au-dessus et au-dessous (y compris un trait de fraction tracé d’un seul geste) ;
- avec **Apple Intelligence** (iOS 27 ou plus, modèle avec vision), le modèle sur l’appareil lit aussi l’image et écrit directement la syntaxe d’Eval (fractions, exposants, racines). Sa lecture n’est retenue que si elle concorde avec celle de Vision, car un modèle qui lit mal une image peut inventer des formules plausibles ; sinon la lecture de Vision est gardée. Une ligne coupée après un opérateur (`2x =` puis `4`) est recollée.

Les caractères sont ensuite écrits pour la feuille : tirets et signes moins, `**`, LaTeX éventuel (`\frac{1}{2} m v^{2}` → `1/2 * m v^2`), `O` entre deux chiffres. Comme `0,5 m` désigne un demi-mètre dans la feuille, un nombre suivi d’un nom déclaré (dans la feuille ou dans les lignes lues) reçoit un `*` : `m = 80 kg` puis `1000 J = 0,5 m v²` devient `1000 J = 0,5 * m v^2`. La permission de la caméra n’est demandée qu’à l’ouverture du scanner ; l’image n’est ni conservée ni envoyée.

Sur iPad, l’Apple Pencil peut aussi écrire directement dans le champ d’une ligne en cours de saisie, grâce à Griffonner (Scribble) du système.

### Annuler et rétablir

**Annuler** et **Rétablir** (menu **Actions de la feuille**), le geste de secousse et ⌘Z défont l’ajout, la suppression, la modification, le déplacement d’une ligne ou le choix d’une unité d’affichage. La saisie d’une ligne, du toucher à sa sortie, et un geste de réglette, quelle que soit sa durée, comptent chacun pour une seule étape ; pendant la saisie, ⌘Z ne concerne que le texte de la ligne. Si la même feuille a été modifiée dans une autre fenêtre, l’annulation est refusée plutôt que d’effacer cette modification.

**Réorganiser** (menu **Actions de la feuille**, puis **Terminé**) réordonne les lignes (poignée) et les supprime ; glisser une ligne vers la gauche la supprime aussi. L’ordre des lignes n’influe pas sur le calcul.

### Copier et partager

Le menu contextuel d’une ligne propose **Copier la valeur** (`1000 J`), **Copier la ligne** (`E = 1000 J` pour une déclaration, `m * v = 400 kg·m·s⁻¹` pour une expression), **Copier la formule**, **Partager le résultat**, **Modifier**, **Dupliquer** et **Supprimer**. **Copier la valeur**, **Copier la ligne** et **Partager le résultat** n’apparaissent que pour une ligne qui affiche une valeur. La valeur copiée est celle affichée, en unités SI ou dans l’unité choisie avec `→`, et se colle comme une entrée valide (les nombres négatifs s’affichent avec le vrai signe moins `−`, que l’analyseur accepte). Pour une ligne `x =` qui a plusieurs solutions, c’est la liste affichée qui est copiée. La copie créée par **Dupliquer** s’ouvre en modification : une déclaration copiée doit recevoir un autre nom, car un nom ne se déclare qu’une fois.

**Partager la feuille** envoie son texte en ajoutant à chaque ligne qui affiche une valeur cette valeur en note, par exemple `E = 0,5 * m * v² =  # 1000 J`, de sorte que le texte se rouvre comme une feuille ; **Partager sans les résultats** envoie la source seule.

### iPad et clavier physique

Sur iPad, chaque fenêtre affiche sa propre feuille, et **Ajouter à la feuille** dans Références complète la feuille de la fenêtre active avec une ligne qui affiche la valeur (`c =`). Raccourcis clavier, visibles en maintenant ⌘ et dans la barre des menus de l’iPad :

- ⌘N **Nouvelle feuille**, ⇧⌘N **Nouvelle ligne**, ⌘F **Rechercher** (iOS 18 ou plus) ;
- ⌘1 **Calcul**, ⌘2 **Références**, ⌘, **Réglages**, ⌘? **Aide** ;
- menu **Feuille** : **Modifier en texte…**, **Effacer la feuille…** ;
- ⌘Z et ⇧⌘Z annulent et rétablissent ; dans une fenêtre d’édition, Échap annule et ⌘↩ confirme.

### Accessibilité

L’interface est construite avec les composants système, ce qui donne accès à Dynamic Type et à VoiceOver. La valeur d’une déclaration numérique s’ajuste avec le geste d’ajustement de VoiceOver, au pas de sa réglette, et les touches de la barre de symboles portent des noms parlés (« Au carré », « Diviser »…). VoiceOver lit les formules comme des expressions mathématiques en français (`E = 0,5 * m * v²` se dit « E égale 0,5 fois m fois v au carré ») et nomme les unités des résultats (« 1000 joules », « 5 mètres par seconde »).

## Syntaxe

- Opérateurs : `+`, `-`, `*`, `/`, `^`, ainsi que `−`, `×`, `÷`, `·` et les exposants Unicode (`²`, `³`, `⁻¹`…). Les puissances sont associatives à droite : `2^3^2` vaut 512 ; `-2^2` vaut −4.
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

`expr -> unité` ou `expr → unité`, à la fin d’une ligne, avant son éventuel `=` final et son commentaire (`v → km/h =`), convertit **l’affichage** d’une expression, d’une déclaration ou d’une comparaison. Une telle ligne affiche toujours sa valeur, avec ou sans `=`. Les variables restent en SI : seul le résultat de la ligne change.

```text
v = 20 m/s → km/h
```

Résultat : **72 km/h**.

```text
E = 3,6e6 J
E → kWh
```

La seconde ligne affiche **1 kWh**. Les cibles acceptent les unités, puis les constantes (`c`, `au`), jamais les variables de la feuille : `m`, `h` et `g` désignent donc le mètre, l’heure et le gramme. Elles acceptent aussi `*`, `/`, `^n`, les produits implicites, les parenthèses et un `1/` initial : `m_e*c^2 -> MeV` donne **0,510999 MeV**, `3000 rpm -> rad/s` donne **314,159 rad/s** et `0,35 -> %` donne **35 %**.

Sans conversion, une grandeur en `s⁻¹` s’affiche `s⁻¹`, jamais `Hz` : `f = 50 s⁻¹ → Hz` affiche **50 Hz**, et `rad/s`, `Bq` ou `tr/min` se choisissent de même. Dans l’application, **Afficher en**, dans le menu d’une ligne ou de sa valeur, écrit cette flèche à votre place ; **Unités SI** la retire. Écrire `E in kJ` renvoie un message qui suggère `→`. `rad` et `tr` sont sans dimension (un tour vaut 2π rad) : `Hz` et `tr/min` ne se convertissent donc pas comme des cycles par seconde, et `50 Hz → tr/min` affiche **477,465 tr/min** (et non 3000). Gardez `Hz` pour les fréquences, et `rad/s` ou `tr/min` pour les vitesses angulaires.

### Unités

En plus des unités SI et de leurs préfixes, Eval reconnaît :

- pression : `atm`, `Torr`, `mTorr`, `mmHg`, `mbar`, `kbar`, `hPa` ;
- énergie : `cal`, `kcal`, `Wh`, `mWh`, `kWh`, `MWh`, `GWh`, `TWh` ; charge : `Ah`, `mAh` ;
- longueur : `Å`, `ly`, `pc`, `kpc`, `Mpc`, `Gpc`, `ft`, `mi` ;
- masse : `Da`, `kDa`, `MDa`, `lb` ; force : `lbf` ;
- temps et rotation : `jour`, `an` (aussi `yr` et `year`, année julienne de 365,25 jours), `tr`, `rpm` ;
- rapports : `%`, `ppm` ; volumes : `ml`, `cl`, `dl`, `hl`, `kl`, `µl` ; résistance : `kohm`, `Mohm`.

`1 atm` vaut **101325 Pa**, `1 kWh` vaut **3600000 J**, `1 mi` vaut **1609,34 m**, `1 an → jour` affiche **365,25 jour**.

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

### Résoudre une équation

Écrire une équation qui contient un nom non déclaré, puis ce nom suivi de `=`, affiche ses solutions :

```text
3x^2 + 2x - 3 = 0
x =
```

La ligne `x =` affiche **(−1 ± √10)/3 ≈ 0,720759 ; −1,38743**. L’équation est une ligne avec `=` (dont le membre gauche n’est pas un simple nom) ou `==`. Le nom demandé ne doit être ni déclaré, ni une constante, ni une unité (`l` est le litre, `h` la constante de Planck) ; seule une ligne `x =` (ou `x → unité`) en fait une inconnue, de sorte qu’une faute de frappe dans une relation reste signalée, avec le conseil d’ajouter `x =`.

- **Polynômes** : l’équation est développée et réduite (les déclarations qui lisent l’inconnue sont remplacées par leur formule). Jusqu’au degré 2, les solutions s’affichent sous forme exacte, puis en décimales : `x^2 - 5x + 6 = 0` donne **2 ; 3**, `3x = 2` donne **2/3 ≈ 0,666667**, `x^3 = 2x` donne **0 ; ±√2 ≈ 0 ; 1,41421 ; −1,41421**. Au-delà, les racines rationnelles sont trouvées exactement et le reste numériquement. Une racine double est signalée (« Solution double. ») ; sans solution réelle, les solutions complexes sont données (`3x^2 + 2x + 1 = 0` : « x = (−1 ± i√2)/3 »). La forme exacte suppose des coefficients sans dimension et de petites fractions ; sinon les solutions sont numériques.
- **Unités** : la dimension de l’inconnue se déduit de l’équation. Avec `m = 80 kg` et `1000 J = 0,5 * m * v^2`, `v =` affiche **−5 m·s⁻¹ ; 5 m·s⁻¹**, et `v → km/h =` les montre en km/h.
- **Autres équations** : `exp(x) = 2` ou `2 s = 2 * pi * sqrt(d / g)` sont résolues numériquement (balayage de 10⁻¹² à 10¹² aux deux signes, puis méthode de Brent), et toutes les solutions trouvées sont listées, six au plus.
- Les autres lignes qui utilisent l’inconnue prennent la plus petite solution positive (sinon la plus proche de zéro), ce qu’une note rappelle. Une seule équation doit contenir l’inconnue, et une seule inconnue par équation ; sinon un message l’explique. Une équation vraie pour toute valeur, ou qui ne dépend plus de l’inconnue une fois simplifiée, est signalée.

### Résoudre une inconnue déclarée

Écrire `v = ? m/s` déclare une inconnue et son unité. Avec **exactement une relation** (`==`, ou `=` qui n’est pas une déclaration) qui contient `v`, directement ou par les déclarations dont elle dépend, Eval cherche **numériquement** la valeur qui vérifie la relation.

```text
E = 1000 J
m = 80 kg
v = ? m/s
E == 0,5 * m * v²
```

Résultat de `v` : **5 m/s**, avec la note « Autre solution : −5 m/s. ». La relation affiche ensuite « Égalité vérifiée. ». La recherche balaie les valeurs de 10⁻¹² à 10¹², aux deux signes, affiche la plus petite racine positive et signale une autre solution. Ce n’est pas une résolution symbolique : une seule inconnue par relation, aucune manipulation d’expression, et une erreur explicite lorsqu’aucune ou plusieurs relations contiennent l’inconnue.

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

La relation est homogène et l’égalité est vérifiée. Une dimension cohérente et une valeur numérique égale sont deux vérifications distinctes. Une simple multiplication donne la dimension de son résultat (`m * v =` affiche **400 kg·m·s⁻¹**) sans prétendre valider une loi physique : seules les sommes, les comparaisons et les égalités vérifient l’homogénéité.

Sans unité, une valeur est considérée comme sans dimension : renseigner les unités pour une vérification physique utile. Eval évalue numériquement les variables définies, résout exactement les équations polynomiales jusqu’au degré 2 et numériquement les autres, et simplifie les formules sur demande ; les systèmes de plusieurs équations, les unités avec décalage (°C, °F) et la propagation des incertitudes ne sont pas implémentés. Les valeurs utilisent `Double`. Les résultats s’affichent avec six chiffres significatifs par défaut, de 3 à 12 dans les **Réglages** (les nombres entiers inférieurs à 10⁹ gardent tous leurs chiffres) ; les calculs, les valeurs saisies, les constantes de Références et les messages d’égalité non vérifiée en gardent dix.

Les erreurs de syntaxe, variables inconnues (avec un renvoi vers **Références › Unités**), doublons, dépendances circulaires, domaines de fonctions, divisions par zéro et dépassements numériques sont signalés par ligne. Si la déclaration dont dépend une ligne est en erreur, cette ligne l’indique (« La déclaration de « x » (ligne 1) contient une erreur. »). Des limites de taille et de profondeur protègent l’éditeur des expressions excessives.

## Structure et validation

- `EvalApp/` : interface native SwiftUI (`NavigationSplitView`, `TabView`, `NavigationStack`, `List`, `Form`, `TextEditor`, Swift Charts, menus et présentations système) : liste et fenêtres de feuilles, saisie sur place des lignes (texte ou écriture mathématique), aperçu de simplification dans le menu contextuel d’une ligne, réglettes, tracés, Références, Réglages, aide, nom automatique des feuilles avec Foundation Models sur l’appareil (`SheetTitleGenerator`, iOS 26 ou plus, derrière `#if canImport(FoundationModels)` et `if #available`), écriture manuscrite (`HandwritingView`, `HandwritingRecognizer` avec Vision et Foundation Models en iOS 27 ; `HandwritingCanvas` réunit les deux seuls ponts UIKit, `PKCanvasView` et `VNDocumentCameraViewController`, faute d’équivalents SwiftUI), et chaînes localisables dans `Localizable.xcstrings`.
- `Sources/EvalCore/` : moteur indépendant de SwiftUI.
  - Analyse et calcul : `ExpressionParser`, `NotebookEngine` (graphe de dépendances, inconnues demandées par `x =`), `RootSearch` (résolution numérique), `Quantity`, `Dimension`, `Catalogs` (constantes et unités), `LineSyntax` (corps, flèche `→`, `=` final et commentaire d’une ligne).
  - Algèbre : `Algebra` (fractions exactes, termes symboliques, simplification, développement, réduction au même dénominateur, écriture en syntaxe Eval, `FormulaSimplifier`), `EquationSolving` (racines réelles des polynômes, formes exactes, `EquationSolutions`).
  - Écriture manuscrite : `RecognizedMath` (exposants et fractions d’après la géométrie, lignes, nettoyage du texte reconnu, accord entre deux lectures).
  - Feuilles : `SheetRecord` (une feuille, l’identité de ses lignes et ses réglettes), `SheetRepository` (un fichier JSON par feuille), `LegacyNotebookMigration` (reprise de l’ancienne feuille unique), `ExampleLibrary` (les 23 exemples), `SheetLineEditing` (copie et partage), `AutomaticSheetTitle` (feuilles à nommer automatiquement, nettoyage du titre proposé), `ResultSelection` (identité des lignes d’une feuille, d’une modification à l’autre).
  - Édition : `MathFormula` (fractions, puissances, racines), `MathEditing` (modèle de l’éditeur en écriture mathématique), `FormulaInsertion` (insertion au curseur), `AdjustableVariable` (réglettes et pas).
  - Tracé et accessibilité : `VariableSweep` (échantillonnage d’un résultat en fonction d’une variable), `MathSpeech` (lecture parlée des formules).
- `Tests/EvalCoreTests/` : tests du moteur et des catalogues (calcul, conversions, fonctions, résolution, équations, simplification, texte reconnu, diagnostics, formats, exemples, feuilles, réglettes, lecture parlée, tracé).
- `Scripts/generate-app-icon.swift` : génère les quatre documents Icon Composer `EvalApp/AppIcon.icon` (icône principale : un point teinté sous une grande lentille Liquid Glass, en orange), `EvalApp/AppIconPoint.icon` (un seul point en Liquid Glass, orange), `EvalApp/AppIconBlue.icon` (lentille, bleu) et `EvalApp/AppIconPointBlue.icon` (point, bleu), ainsi que leurs aperçus pour les Réglages. Le dessin (parabole au-dessus d’une réglette) est fait de tracés vectoriels, sans SF Symbol ; le système en dérive les apparences sombre, teintée et transparente, et Xcode les icônes des versions antérieures d’iOS. L’icône suit la couleur d’accent : le style se choisit dans **Réglages › Icône de l’app**, et les trois icônes alternatives sont déclarées dans `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.

```sh
swift test
xcodebuild -project Eval.xcodeproj -scheme Eval \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/eval-derived CODE_SIGNING_ALLOWED=NO build
```

`swift test` exécute les tests de `EvalCore` ; la commande `xcodebuild` vérifie que l’application compile pour le simulateur. Les 23 exemples intégrés sont eux-mêmes testés : chacun doit s’évaluer sans erreur.

Les constantes physiques et chimiques embarquées proviennent des [valeurs CODATA 2022 du NIST](https://physics.nist.gov/cuu/pdf/all.pdf). Les constantes définissant le SI suivent la [Brochure sur le SI du BIPM](https://www.bipm.org/fr/publications/si-brochure), et la pesanteur standard les [valeurs conventionnelles adoptées](https://physics.nist.gov/cuu/pdf/adopted_2002.pdf). Les références astronomiques suivent les résolutions de l’Union astronomique internationale, qui fixent notamment des grandeurs nominales ; les références mathématiques proviennent du DLMF du NIST. Chaque entrée du catalogue conserve sa source. Les dimensions et préfixes suivent le [Système international d’unités](https://www.nist.gov/pml/special-publication-330).
