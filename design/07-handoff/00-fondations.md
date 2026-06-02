# Handoff — Fondations

> Socle de référence pour le dev **Flutter (Material 3 + Bloc)**. Valeurs **exactes**, en tokens. Source des tokens : `../03-design-system/01-tokens.md` ; thème Dart : `../03-design-system/03-flutter-theme.md`.
> Règle d'or handoff : **si ce n'est pas spécifié, le dev devine** — donc on spécifie tout (mesures, états, edge cases, a11y).

## 1. Grille & breakpoints

### Mobile (app patient — cible principale)
- Largeur de référence design : **390 pt** (iPhone 14/15). S'adapte 320 → 480.
- **Marge écran (safe gutter)** : `space/4` = **16 pt** gauche/droite.
- **Colonne unique**, contenu pleine largeur moins marges.
- Zone de contenu max : 100% ; cartes pleine largeur (largeur − 2×16).
- **Bottom nav** : hauteur **56 pt** + safe-area bottom. **App bar** : 56 pt + safe-area top.
- Espace vertical entre sections : `space/6` = 24 pt ; entre items d'une liste : `space/3` = 12 pt.

### Back-office (web/desktop & tablette)
| Breakpoint | Largeur | Layout |
|---|---|---|
| Desktop | ≥ 1024 px | Sidebar 240 px fixe + contenu fluide, max contenu 1200 px, gouttière 24 px |
| Tablette | 768–1023 px | Sidebar repliable (rail 72 px) + contenu |
| Mobile pro | < 768 px | Sidebar → drawer ; tables → cartes empilées |

Grille desktop : 12 colonnes, gouttière 24 px, marge 24 px.

## 2. Échelle d'espacement (4 pt)
| Token | pt/px | Usage type |
|---|---|---|
| `space/1` | 4 | icône↔texte, padding interne serré |
| `space/2` | 8 | gap entre éléments liés |
| `space/3` | 12 | padding vertical de ligne, gap liste |
| `space/4` | 16 | **marge écran**, padding carte (mobile) |
| `space/5` | 20 | — |
| `space/6` | 24 | padding carte (desktop), marge de section |
| `space/8` | 32 | séparation de blocs |
| `space/10` | 40 | grands espaces |
| `space/12` | 48 | héros |
| `space/16` | 64 | — |

## 3. Typographie (valeurs exactes)
Police UI **Inter**, display **Fraunces** (titres premium). Poids 400/500/600.
| Token | Police | Taille / interligne | Poids | Letter-spacing | Usage |
|---|---|---|---|---|---|
| `display` | Fraunces | 32 / 40 | 600 | -0.5 | héros, écrans vides premium |
| `h1` | Inter | 28 / 36 | 600 | -0.2 | titre d'écran |
| `h2` | Inter | 24 / 32 | 600 | -0.2 | section |
| `h3` | Inter | 20 / 28 | 600 | 0 | sous-section |
| `title` | Inter | 18 / 26 | 500 | 0 | titre de carte |
| `body-lg` | Inter | 16 / 26 | 400 | 0 | corps mobile |
| `body` | Inter | 14 / 22 | 400 | 0 | corps / back-office |
| `label` | Inter | 14 / 20 | 500 | 0 | libellés, **boutons** |
| `caption` | Inter | 13 / 18 | 400 | 0 | aides, métadonnées |
| `micro` | Inter | 12 / 16 | 500 | 0.2 | badges, tags |
- **Montants** : chiffres **tabulaires** (`fontFeatures: [FontFeature.tabularFigures()]`), token `h2`/`display` selon contexte.
- Troncature : titres 1 ligne `ellipsis` ; descriptions 2 lignes max (`maxLines:2, overflow: ellipsis`).

## 4. Couleurs (rappel rôles — détail `03-design-system/01`)
`primary` #047857 (clair) / #34D399 (sombre) · `text/on-primary` #FFFFFF / #052E22 · `bg/page` #FAFAF9 / #1C1917 · `bg/surface` #FFFFFF / #292524 · `text/primary` #1C1917 / #FAFAF9 · `text/secondary` #57534E / #D6D3D1 · `border/subtle` #E7E5E4 / #44403C. Sémantiques success/warning/danger/info : voir tokens. **Contrastes AA garantis.**

## 5. Rayons & élévation
- Rayons : `xs` 4 · `sm` 6 · `md` 8 (défaut boutons/inputs) · `lg` 12 (**cartes**, sheets) · `xl` 16 · `full` 999 (pills/avatars).
- Élévation (douce) : `shadow/sm` `0 1px 2px rgba(28,25,23,.05)` (carte) · `shadow/md` `0 2px 8px rgba(28,25,23,.07)` (menu, sheet) · `shadow/lg` `0 8px 24px rgba(28,25,23,.10)` (modale).
- **Sombre** : pas d'ombre portée → élévation par `bg/elevated` + `border/subtle`.
- **Focus ring** : `0 0 0 3px rgba(5,150,105,.35)` (clair) / `rgba(52,211,153,.45)` (sombre). 2 px d'épaisseur effective.

## 6. Iconographie
- Set : **Tabler outline** (cohérent avec les maquettes) ou équivalent Material outline.
- Tailles : 16 (inline dense), **20** (défaut), 24 (nav/écran), 28-32 (illustratif).
- Couleur : hérite du texte ; actions primaires en `primary`. `aria-hidden` si décoratif ; label si porteur de sens.

## 7. Motion
| Token | Durée | Easing | Usage |
|---|---|---|---|
| `motion/fast` | 120 ms | `easing/standard` cubic-bezier(.2,0,0,1) | hover, petits feedbacks, ripple |
| `motion/base` | 200 ms | standard | transitions d'état, sheets, nav |
| `motion/slow` | 320 ms | `easing/entrance` cubic-bezier(0,0,0,1) | entrées d'écran, modales |
- Transitions d'écran : slide horizontal (push) 280 ms ; sheets : slide-up 240 ms.
- **Respecter `MediaQuery.disableAnimations`** (≈ `prefers-reduced-motion`) : couper/raccourcir.
- Skeletons : shimmer 1200 ms loop.

## 8. États standard (s'appliquent à tout composant interactif)
`default` · `hover` (desktop) · `focus` (anneau, clavier) · `pressed` (scale .98 / overlay 8%) · `disabled` (opacité 38% + non interactif) · `loading` (spinner, non interactif) · `selected` · `error`.

## 9. Accessibilité (baseline obligatoire — US-X01)
- **Contraste** : AA (≥ 4.5:1 texte, ≥ 3:1 grand texte/UI). Vérifié sur clair **et** sombre.
- **Cibles tactiles** : ≥ 44×44 pt (mobile).
- **Focus** visible partout, ordre logique (haut→bas, gauche→droite).
- **Lecteur d'écran** : chaque élément porteur de sens a un label ; rôles corrects (bouton, lien, en-tête) ; live-region pour les changements (file d'attente, erreurs).
- **Couleur jamais seule** : statut/urgence = icône + texte + couleur.
- **Langue** déclarée `fr` ; formats date/montant FR (« 1 250 € », « mar. 16 juin »).
- **Taille de police système** respectée (text scaling jusqu'à 200% sans casse — éviter hauteurs fixes sur le texte).

## 10. Contenu & i18n
- **Langue** : français. Ton : clair, rassurant, professionnel (voir `../05-ux-copy/`).
- **Troncature** : noms 1 ligne ; adresses 1 ligne + `…` ; messages 2 lignes en liste.
- **Longueur variable** : prévoir +30% (chaînes longues), montants jusqu'à 7 chiffres, noms composés.
- **Vides** : chaque liste a un **empty state** (icône + titre + sous-texte + CTA si pertinent).
- **Nombres** : arrondis, séparateur de milliers FR (espace fine), devise suffixe « € ».

## 11. Conventions de nommage (dev)
- Composants Flutter : `Nubia<Composant>` (ex. `NubiaButton`, `NubiaTextField`, `NubiaProviderCard`).
- Écrans : `<Domaine>Page` (ex. `SearchPage`, `QuoteDetailPage`, `WaitingRoomPage`).
- Bloc : `<Domaine>Bloc` + `Event`/`State` (ex. `SearchBloc`, `SearchEvent`, `SearchState`).
- Tokens : exposés via `Theme.of(context)` + `NubiaTokens` (cf. `03-design-system/03`).

> Détail composant par composant : `01-composants.md`. Specs écran par écran : `02-ecrans.md`.
