# Design tokens — Nubia

> Direction de marque retenue : **premium / esthétique**, primaire **vert santé (émeraude)**, **thème clair + sombre**, **angles arrondis doux**.
> Les tokens sont la couche atomique : ils alimentent les composants (`02-composants.md`) et le thème Flutter (`03-flutter-theme.md`). Tout contraste texte/fond vise **WCAG AA** (≥ 4.5:1 texte courant, ≥ 3:1 grand texte / UI).

## 1. Couleurs

### 1.1 Ramp de marque — Émeraude (« vert santé »)
| Token | Hex | Usage |
|---|---|---|
| `brand/50` | `#ECFDF5` | fonds très clairs, surfaces de sélection |
| `brand/100` | `#D1FAE5` | fond `primary-subtle` |
| `brand/200` | `#A7F3D0` | bordures douces |
| `brand/300` | `#6EE7B7` | accents clairs |
| `brand/400` | `#34D399` | **primaire en thème sombre** |
| `brand/500` | `#10B981` | hover sombre / accents |
| `brand/600` | `#059669` | **couleur d'identité** (logo, accents) |
| `brand/700` | `#047857` | **primaire en thème clair** (boutons) |
| `brand/800` | `#065F46` | texte sur fond `primary-subtle` |
| `brand/900` | `#064E3B` | texte de marque très foncé |

> Nuance premium : la **couleur d'identité** est `brand/600` (#059669, ta sélection), mais le **bouton primaire** utilise `brand/700` (#047857) en clair pour rester **AA** avec du texte blanc (≈ 5.5:1). En sombre, on remonte à `brand/400` avec un texte vert quasi-noir.

### 1.2 Neutres — gris chaud (« stone ») pour un rendu premium
| Token | Hex | | Token | Hex |
|---|---|---|---|---|
| `neutral/0` | `#FFFFFF` | | `neutral/500` | `#78716C` |
| `neutral/50` | `#FAFAF9` | | `neutral/600` | `#57534E` |
| `neutral/100` | `#F5F5F4` | | `neutral/700` | `#44403C` |
| `neutral/200` | `#E7E5E4` | | `neutral/800` | `#292524` |
| `neutral/300` | `#D6D3D1` | | `neutral/900` | `#1C1917` |
| `neutral/400` | `#A8A29E` | | | |

### 1.3 Accent premium — Sable doré (usage rare)
Pour les touches « haut de gamme » (passeport implantaire, mises en avant). À utiliser **avec parcimonie**, jamais pour une action.
| Token | Hex |
|---|---|
| `accent/100` | `#F3EAD7` |
| `accent/500` | `#B0894F` |
| `accent/700` | `#876435` |

### 1.4 Couleurs sémantiques (états)
Distinctes de la marque pour éviter toute confusion (le vert de marque ≠ « succès »). **Toujours** doubler la couleur d'une icône + d'un texte (jamais la couleur seule).
| Rôle | fg (clair) | bg (clair) | fg (sombre) | bg (sombre) |
|---|---|---|---|---|
| `success` | `#15803D` | `#DCFCE7` | `#4ADE80` | `#14271A` |
| `warning` | `#B45309` | `#FEF3C7` | `#FBBF24` | `#2A1E05` |
| `danger` | `#B91C1C` | `#FEE2E2` | `#F87171` | `#2A1212` |
| `info` | `#0E7490` | `#CFFAFE` | `#38BDF8` | `#082530` |

> `danger` sert aussi au **bandeau d'urgence** messagerie (priorisation visuelle, jamais décision clinique — cf. `../../docs/03` §2).

### 1.5 Tokens sémantiques (rôles) — la couche que consomme l'UI
C'est **cette table** que le thème Flutter implémente (clair/sombre).

| Rôle | Clair | Sombre |
|---|---|---|
| `bg/page` | `#FAFAF9` | `#1C1917` |
| `bg/surface` | `#FFFFFF` | `#292524` |
| `bg/elevated` | `#FFFFFF` | `#44403C` |
| `text/primary` | `#1C1917` | `#FAFAF9` |
| `text/secondary` | `#57534E` | `#D6D3D1` |
| `text/tertiary` | `#A8A29E` | `#A8A29E` |
| `text/on-primary` | `#FFFFFF` | `#052E22` |
| `border/subtle` | `#E7E5E4` | `#44403C` |
| `border/default` | `#D6D3D1` | `#57534E` |
| `border/strong` | `#A8A29E` | `#78716C` |
| `primary` | `#047857` | `#34D399` |
| `primary/hover` | `#065F46` | `#6EE7B7` |
| `primary/pressed` | `#064E3B` | `#A7F3D0` |
| `primary/subtle-bg` | `#ECFDF5` | `#0B3D2E` |
| `primary/subtle-fg` | `#065F46` | `#A7F3D0` |
| `focus-ring` | `rgba(5,150,105,0.35)` | `rgba(52,211,153,0.45)` |

**Contrastes vérifiés (AA)** : texte blanc sur `primary` clair `#047857` ≈ 5.5:1 ; texte `#052E22` sur `primary` sombre `#34D399` ≈ 7.7:1 ; `text/primary` clair sur `bg/page` ≈ 16:1 ; `text/secondary` clair ≈ 6.8:1.

## 2. Typographie
- **Police UI (corps, interface)** : `Inter` — lisibilité maximale, neutre, AA-friendly. (Flutter : `google_fonts`.)
- **Police display (titres premium, écrans marketing/vides)** : `Fraunces` (serif élégante, optical) — réservée aux grands titres pour la touche « premium ». Dans l'app dense (back-office), rester en `Inter` partout.
- **Poids** : 400 (regular), 500 (medium), 600 (semibold — titres). Pas de 700+.

| Token | Taille / interligne | Poids | Police | Usage |
|---|---|---|---|---|
| `display` | 32 / 40 | 600 | Fraunces | héros, écrans vides premium |
| `h1` | 28 / 36 | 600 | Inter | titre d'écran |
| `h2` | 24 / 32 | 600 | Inter | section |
| `h3` | 20 / 28 | 600 | Inter | sous-section |
| `title` | 18 / 26 | 500 | Inter | titres de carte |
| `body-lg` | 16 / 26 | 400 | Inter | texte principal mobile |
| `body` | 14 / 22 | 400 | Inter | texte courant / back-office |
| `label` | 14 / 20 | 500 | Inter | libellés de champ, boutons |
| `caption` | 13 / 18 | 400 | Inter | aides, métadonnées |
| `micro` | 12 / 16 | 500 | Inter | badges, tags |

## 3. Espacements (base 4px)
| Token | px | | Token | px |
|---|---|---|---|---|
| `space/0` | 0 | | `space/5` | 20 |
| `space/1` | 4 | | `space/6` | 24 |
| `space/2` | 8 | | `space/8` | 32 |
| `space/3` | 12 | | `space/10` | 40 |
| `space/4` | 16 | | `space/12` | 48 |
| | | | `space/16` | 64 |

Conventions : padding interne carte = `space/4` (16) à `space/6` (24) ; gouttière liste = `space/3` (12) ; marge de section = `space/8` (32).

## 4. Rayons (arrondi doux)
| Token | px | Usage |
|---|---|---|
| `radius/xs` | 4 | tags, puces |
| `radius/sm` | 6 | champs, petits boutons |
| `radius/md` | 8 | **défaut** (boutons, inputs) |
| `radius/lg` | 12 | **cartes**, modales |
| `radius/xl` | 16 | grandes surfaces, bottom sheets |
| `radius/full` | 999 | avatars, pills, badges ronds |

## 5. Élévation (ombres) — douces et premium
| Token | Valeur (clair) | Usage |
|---|---|---|
| `shadow/sm` | `0 1px 2px rgba(28,25,23,0.05)` | cartes au repos |
| `shadow/md` | `0 2px 8px rgba(28,25,23,0.07)` | éléments levés, dropdowns |
| `shadow/lg` | `0 8px 24px rgba(28,25,23,0.10)` | modales, sheets |
| `focus/ring` | `0 0 0 3px var(focus-ring)` | focus clavier (a11y) |

> En **thème sombre**, les ombres portent peu : privilégier `border/subtle` + `bg/elevated` pour signifier l'élévation.

## 6. Motion
| Token | Valeur | Usage |
|---|---|---|
| `motion/fast` | 120 ms | hover, petits feedbacks |
| `motion/base` | 200 ms | transitions standard, sheets |
| `motion/slow` | 320 ms | entrées d'écran, modales |
| `easing/standard` | `cubic-bezier(0.2, 0, 0, 1)` | la plupart |
| `easing/entrance` | `cubic-bezier(0, 0, 0, 1)` | apparition |
| `easing/exit` | `cubic-bezier(0.4, 0, 1, 1)` | disparition |

Sobriété : animations utiles et courtes (santé = sérieux), respecter `prefers-reduced-motion`.

## 7. Règles d'usage couleur
- **La couleur ne porte jamais seule une information** (statut, urgence) : toujours + icône + texte.
- **Vert de marque** = identité et actions principales ; **pas** pour « succès » (utiliser `success`).
- Accent **sable** : décoratif et rare (premium), jamais une action.
- Vérifier chaque combinaison en **clair et sombre** (mental test : lisible sur fond quasi-noir ?).

> Suite : composants (`02-composants.md`) et implémentation Flutter (`03-flutter-theme.md`).
