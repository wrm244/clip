<div align="center">
  <img src="docs/icon.png" width="96" alt="Icône Clip">
  <h1>Clip</h1>
  <p><b>Gestionnaire d'historique du presse-papiers pour macOS</b><br>Un raccourci, et votre historique est là.</p>
</div>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <a href="README_en.md">English</a> ·
  <a href="README_ja.md">日本語</a> ·
  <b>Français</b>
</p>

<div align="center">
  <img src="docs/img/剪切板1.png" width="820" alt="Panneau Clip avec aperçu déroulé">
</div>

---

## Le problème

Vous copiez un bout de code, vous allez consulter la documentation, puis vous en avez besoin — et le presse-papiers contient déjà autre chose.

Clip retient discrètement tout ce que vous copiez, en arrière-plan. <kbd>⇧⌘V</kbd> pour l'appeler, les flèches pour choisir, <kbd>↵</kbd> pour coller exactement là où se trouve votre curseur.

<p align="center">
  <img src="docs/img/剪切板2.png" width="480" alt="Panneau Clip compact">
</p>

Aucune fenêtre attenante, aucun onglet, pas besoin de se souvenir où l'on a rangé un truc. L'historique est là, devant vous — faites défiler et choisissez.

## Fonctionnalités

### Tout retient

Du texte, des liens, des valeurs de couleur, du code, des chemins de fichiers, des images — tout ce que vous copiez est conservé, avec l'application d'origine en étiquette.

<p align="center">
  <img src="docs/img/剪切板1.png" width="820" alt="Détection du type et aperçu">
</p>

La rangée de pastilles en haut filtre par type, avec un décompte en direct. Captures d'écran, maquettes, valeurs de couleur copiées — chacun trouve sa place au lieu de tout mélanger dans une même liste.

### Prêt dès l'appel

- **Apparaît à votre curseur** — là où se trouve votre pointeur ; bascule de l'autre côté quand il n'y a pas la place
- **Hauteur fixe** — quel que soit le nombre d'entrées, seule la liste défile : la fenêtre ne saute jamais à l'ouverture
- **Entrée colle immédiatement** — directement à la position du curseur, sans avoir à revenir à l'application précédente

### Voir avant de décider

Sélectionnez une entrée et appuyez sur <kbd>→</kbd> pour dérouler l'aperçu vers la droite. Le **coin supérieur gauche reste fixe**, donc la liste que vous lisez ne glisse pas latéralement. Cliquez sur une image pour l'afficher à la taille de l'écran ; cliquez n'importe où ou appuyez sur `esc` pour refermer.

### Au clavier, et c'est bien

| Touche | Action |
| --- | --- |
| <kbd>⇧⌘V</kbd> | Afficher / masquer le panneau (raccourci modifiable) |
| <kbd>↑</kbd> <kbd>↓</kbd> | Naviguer |
| <kbd>↵</kbd> | Coller au curseur |
| <kbd>⌥↵</kbd> | Coller en texte brut (sans mise en forme) |
| <kbd>→</kbd> <kbd>←</kbd> | Dérouler / replier l'aperçu |
| <kbd>⌘1</kbd>–<kbd>⌘9</kbd> | Coller directement la Nᵉ entrée |
| <kbd>⌘P</kbd> | Épingler / détacher |
| <kbd>⌘⌫</kbd> | Supprimer l'entrée sélectionnée |
| <kbd>esc</kbd> | Refermer le panneau |

### Également dans la barre des menus

Si vous préférez éviter le clavier, cliquez sur l'icône de la barre des menus. Activer l'enregistrement, consulter les entrées récentes, coller directement depuis le menu.

<p align="center">
  <img src="docs/img/任务栏弹窗.png" width="520" alt="Panneau de la barre des menus">
</p>

### Aussi sur le Bureau

Un widget pour le Centre de notifications / le Bureau affiche vos entrées récentes. Cliquez pour copier, cliquez sur le vide pour appeler le panneau complet.

### Trouver la bonne entrée

Le champ de recherche en haut filtre au fur et à mesure de la frappe. Les entrées épinglées (<kbd>⌘P</kbd>) ne sont jamais nettoyées automatiquement : paramètres, URLs et extraits d'usage courant restent à portée de main.

## Installation

Nécessite **macOS 27 (Golden Gate) ou ultérieur**.

Téléchargez le `.dmg` depuis [Releases](https://github.com/wrm244/clip/releases) et glissez-le dans Applications.

Au premier lancement, une icône apparaît dans la barre des menus. Pour que Clip appuie sur <kbd>⌘V</kbd> à votre place, allez dans **Réglages Système → Confidentialité et sécurité → Accessibilité** et activez Clip. Sans cette autorisation, l'app fonctionne quand même : elle se contente de copier et vous invite à coller manuellement.

## Confidentialité

Un gestionnaire de presse-papiers peut voir tout ce que vous copiez. Voici donc les faits :

- **Les contenus secrets sont ignorés par défaut.** Les contenus que les gestionnaires de mots de passe (1Password, TypeIt4me, etc.) marquent comme confidentiels ne sont jamais enregistrés
- **Il n'enregistre pas ses propres écritures** — votre historique n'est jamais recopié dans lui-même
- **Pause possible à tout moment** avec un simple interrupteur
- **Vos données restent sur votre Mac.** L'historique vit dans `~/Library/Application Support/Clip`. Rien n'est envoyé, rien n'est synchronisé, aucun compte
- **Des limites réglables.** Nombre d'entrées (300 par défaut) et durée de conservation sont configurables, et tout peut être effacé en un clic

## Licence

Publié sous licence [MIT](LICENSE). Utilisez-le, modifiez-le, redistribuez-le.

## Tous les réglages

**Général** — langue, activation de l'enregistrement, exclusion des contenus confidentiels, limites de conservation, collage automatique.

<p align="center">
  <img src="docs/img/设置通用.png" width="620" alt="Réglages · Général">
</p>

**Apparence** — clair / sombre, densité de la liste, affichage des applications d'origine, taille du panneau, et apparition au curseur ou centrée en haut de l'écran.

<p align="center">
  <img src="docs/img/设置外观.png" width="620" alt="Réglages · Apparence">
</p>

**Raccourcis** — modifier le raccourci global, et un rappel de tous les raccourcis du panneau.

Chaque changement **prend effet immédiatement**. Pas de bouton Appliquer, pas besoin de redémarrer.

## Prise en charge

- Interface en chinois et en anglais, commutable dans les réglages, suivant la langue du système par défaut
- Apparence claire et sombre, suivant le système ou définie manuellement
- Lancement à la connexion
- Respecte les fonctions d'accessibilité : Réduire la transparence, Augmenter le contraste, Réduire les animations

---

<details>
<summary><b>Notes pour les développeurs (build · architecture · implémentation)</b></summary>

### Stack technique

SwiftUI + AppKit natifs, **aucune dépendance tierce**. Fonctionne en agent de barre des menus (`LSUIElement`), sans occuper le Dock. SwiftData pour la persistance incrémentale, les données binaires telles que les images étant stockées dans des fichiers externes.

- Cible : macOS 27.0+, Swift 6 (concurrence stricte)
- L'interface suit les [Human Interface Guidelines d'Apple](https://developer.apple.com/design/human-interface-guidelines/) et utilise le Liquid Glass natif
- Signature : certificat auto-signé `Clip Self Signed`, qui préserve l'autorisation d'accessibilité d'une version à l'autre (voir ci-dessous pourquoi)

### Build

Nécessite [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate                       # génère Clip.xcodeproj depuis project.yml
open Clip.xcodeproj                     # puis Run depuis Xcode
```

Build en ligne de commande :

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Clip.xcodeproj -scheme Clip \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build build
```

Résultat : `build/Build/Products/Release/Clip.app`

> Relancez `xcodegen generate` après avoir ajouté ou supprimé des fichiers sources (le projet collecte les sources par répertoire).
> Ne laissez pas plusieurs copies de Clip.app sur le disque (par ex. Debug et Release côte à côte) : elles partagent le
> même répertoire de données, et au lancement l'app détecte l'autre copie et lui cède la place.

### Empaquetage et publication

```bash
Scripts/make-dmg.sh build/Build/Products/Release/Clip.app dist v1.0.6
```

`.github/workflows/release.yml` compile, empaquette et publie automatiquement à chaque push d'un tag `v*`.
La signature en CI nécessite deux secrets : `P12_BASE64` (base64 sur une seule ligne du p12) et `P12_PASSWORD`.

### Pourquoi pas une signature ad-hoc

La signature ad-hoc n'a pas d'identité stable : l'exigence désignée que macOS enregistre pour les autorisations de confidentialité (TCC, par ex. l'accessibilité) ne peut être que `cdhash H"…"` — une empreinte du binaire entier. Chaque reconstruction change le cdhash, ce qui invalide aussitôt l'autorisation et oblige l'utilisateur à réautoriser après chaque mise à jour.

Avec un certificat auto-signé, l'exigence désignée devient `identifier "com.river.Clip" and certificate leaf = H"…"`, liée uniquement à l'identifiant de bundle et au certificat : l'autorisation survit donc à toute modification du binaire.

Création du certificat, une seule fois : Trousseau d'accès → Assistant Certificat → Créer un certificat…, nom `Clip Self Signed`, type d'identité Racine auto-signée, type de certificat Signature de code, puis le définir sur Toujours approuver.

> **Le p12 doit contenir à la fois le certificat et la clé privée.** Exporter uniquement la clé privée s'importe sans
> erreur mais ne permet pas de reconstituer une identité. Exportez l'identité entière avec
> `security export -t identities` pour éviter ce problème.

### Points d'architecture

**Pipeline de capture** : `NSPasteboard.general.changeCount` est interrogé toutes les 0,4 s (`Timer` avec `tolerance` 0,2 — coût CPU négligeable) → en cas de changement, analyse en `ClipDraft` → déduplication / transcodage / stockage → écriture incrémentale dans SwiftData. Lorsque le panneau est ouvert, l'application au premier plan est Clip lui-même ; ce cas est mis en attente plutôt que ignoré, pour ne rien perdre.

**Modèle de concurrence** : `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor` + `SWIFT_STRICT_CONCURRENCY=complete`. L'interface et l'état vivent sur l'acteur principal ; l'accès base de données / fichiers et le transcodage d'images sont isolés dans deux acteurs, `ClipStorage` et `ImageTranscoder`, de sorte que le fil principal ne touche jamais aux E/S.

Choix SwiftData : classes `@Model` explicitement `nonisolated` ; `ModelContext` créé paresseusement dans les méthodes d'acteur (pour que le premier accès ne tombe pas sur la file principale) ; les instances `@Model` ne franchissent jamais la frontière d'un acteur — seul le DTO `ClipItem` (Sendable) est exposé ; autosave désactivé, chaque écriture appelle `save()` explicitement (l'autosave n'est pas fiable en cas d'arrêt forcé) ; le schéma démarre sur `VersionedSchema` + `SchemaMigrationPlan`.

**Fenêtre** : `NSPanel(.borderless, .fullSizeContentView, .nonactivatingPanel)`, avec `canBecomeKey = true` pour pouvoir saisir dans la recherche, à `level = .floating`. Le déploiement de l'aperçu élargit seulement la fenêtre vers la droite en gardant le coin supérieur gauche fixe, sans jamais recalculer la position.

**Raccourci global** : `RegisterEventHotKey` de Carbon, avec retour sur l'acteur principal via `MainActor.assumeIsolated` dans le callback C. Contrairement à `CGEventTap`, aucune autorisation d'accessibilité n'est requise.

**Boucle de rappel** : les écritures dans le presse-papiers portent un type `com.river.clip.marker`, que la scrutation ignore.

**Panneau de barre des menus** : utilise la session « interface déployée » de `NSStatusItem` (macOS 27, `NSStatusItemExpandedInterfaceDelegate`) plutôt que `NSPopover` — la session système fournit la navigation au clavier et le suivi des menus. Trois contraintes fermes : ne pas définir de `menu`, ne pas basculer manuellement via target/action, et fermer avec `expandedInterfaceSession?.cancel()`.

**Emplacement des données** :

```
~/Library/Application Support/Clip/
├── Clip.store      base de données SwiftData (SQLite en dessous)
├── Blobs/          originaux PNG, vignettes JPG, texte enrichi RTF
└── Widget/         instantané en lecture seule pour le widget (feed.json + Thumbs/)
```

Les réglages se trouvent dans `~/Library/Preferences/com.river.Clip.plist`.

### Organisation du projet

```
project.yml                 définition du projet XcodeGen
Support/Info.plist          LSUIElement, schéma d'URL clip://
Sources/
  App/                      point d'entrée, cycle de vie, coordination applicative
  Models/                   modèle d'entrée, réglages, raccourcis
  Services/                 capture, analyse, transcodage, stockage, raccourci global, collage
  UI/                       panneau, aperçu, panneau de barre des menus, fenêtre de réglages
  Support/                  localisation, journalisation, flux du widget
Widget/                     widget de Bureau (approche par instantané en lecture seule)
Scripts/                    make-dmg.sh, seed-clipboard.swift
```

`Scripts/seed-clipboard.swift` est un outil de développement : il écrit une série d'entrées dans le presse-papiers système à partir d'un manifeste JSON, ce qui permet de générer rapidement des données de test de tous types.

```bash
swiftc -O Scripts/seed-clipboard.swift -o /tmp/clipseed
/tmp/clipseed run Scripts/seed-content.sample.json 1100
```

### Limites connues

- « Lancer à la connexion » utilise `SMAppService.mainApp`, qui peut échouer si l'app n'est pas dans `/Applications` (les réglages affichent une erreur le cas échéant)
- Les images sont plafonnées à 8 Mo par défaut (au-delà, ré-échantillonnage) ; l'historique est plafonné à 300 entrées ; les entrées épinglées ne sont jamais purgées
- Le widget de Bureau lit le répertoire d'instantanés de l'app principale via `temporary-exception.files.home-relative-path.read-only` — le seul canal de partage possible sans App Group. Une publication sur le Mac App Store exigerait un App Group et une signature officielle
- L'instantané du widget contient les titres de vos 12 entrées les plus récentes (ceci n'est pas désactivable pour l'instant)
- Signé avec un certificat auto-signé ; une distribution sur le Mac App Store ou une notarisation exigent un certificat Developer ID

</details>

<p align="center">
  <sub>SwiftUI + AppKit natifs · Aucune dépendance tierce · Vos données restent sur votre Mac</sub>
</p>