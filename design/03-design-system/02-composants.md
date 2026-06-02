# Composants — Nubia

> Composants cœur du MVP, consommant les tokens (`01-tokens.md`) et destinés à devenir des **widgets Flutter** (`03-flutter-theme.md`).
> Chaque composant : variantes, états, accessibilité, mapping Flutter. Rappel garde-fous : cloisonnement praticien/secrétariat, zéro PII dans les notifs, aucune promesse clinique.

États standard communs : `default`, `hover`, `focus` (anneau `focus/ring`), `pressed`, `disabled`, `loading`, `error`. Tailles : `sm` (32px h), `md` (40px h, défaut), `lg` (48px h).

---

## 1. Button
Action déclenchée par l'utilisateur.

| Variante | Quand l'utiliser | Style |
|---|---|---|
| `primary` | action principale (Signer, Payer, Prendre RDV) | fond `primary`, texte `text/on-primary` |
| `secondary` | action secondaire | fond `bg/surface`, bordure `border/default`, texte `text/primary` |
| `ghost` | action tertiaire/inline | transparent, texte `primary` |
| `danger` | action destructive (Annuler un RDV) | fond `danger.bg`, texte `danger.fg` (ou plein rouge si critique) |

| Propriété | Type | Défaut | Description |
|---|---|---|---|
| `variant` | enum | `primary` | voir table |
| `size` | sm/md/lg | `md` | hauteur |
| `icon` | iconData? | — | icône avant le label |
| `loading` | bool | false | remplace le label par un spinner, désactive |
| `fullWidth` | bool | false | s'étire (CTA mobile) |

États : hover → `primary/hover` ; pressed → `primary/pressed` ; focus → anneau ; disabled → `neutral/200` fond + `text/tertiary` ; loading → spinner + non interactif.
Accessibilité : rôle bouton ; cible ≥ 44×44 (mobile) ; label explicite (pas « OK » seul) ; `Enter`/`Espace` activent ; état loading annoncé (« chargement »).
Radius `radius/md`. Padding : md = `space/3` vertical, `space/5` horizontal.

```
NubiaButton.primary(label: 'Signer le devis', icon: Icons.draw, onPressed: ...)
```

---

## 2. Text field / Input
Saisie de texte (email, recherche, montant…).

Anatomie : `label` (token `label`) · champ (bordure `border/default`, radius `radius/sm`) · `helper`/`error` (token `caption`).
États : focus → bordure `primary` + anneau ; error → bordure `danger.fg` + message ; disabled → fond `neutral/100`. 
Variantes : `text`, `email`, `password` (toggle œil), `search` (icône loupe), `amount` (suffixe €), `phone`.
Accessibilité : `label` lié au champ ; erreur reliée (annoncée par le lecteur d'écran) ; ne jamais signaler l'erreur par la couleur seule (icône + texte).

```
NubiaTextField(label: 'E-mail', error: state.emailError, keyboardType: email)
```

---

## 3. Card
Conteneur d'un objet borné (RDV, devis, document).

Style : fond `bg/surface`, bordure `border/subtle`, radius `radius/lg`, ombre `shadow/sm`, padding `space/4`–`space/6`.
Variantes : `static`, `interactive` (hover → `shadow/md`, focus → anneau), `selected` (bordure `primary`, fond `primary/subtle-bg`).
Accessibilité : si cliquable, c'est un bouton (rôle + clavier), pas un simple `div`.

---

## 4. Status badge / Pill
Statut court (RDV confirmé, devis signé, message urgent).

| Variante | Couleur | Exemple |
|---|---|---|
| `neutral` | `neutral` | brouillon |
| `success` | `success` | confirmé, signé, payé |
| `warning` | `warning` | en attente, à signer |
| `danger` | `danger` | urgent, annulé, retard |
| `info` | `info` | en salle d'attente |

Style : fond `*.bg`, texte `*.fg`, radius `radius/full`, token `micro`, + **icône** (jamais couleur seule). 
Accessibilité : le texte porte le sens (« Urgent »), la couleur l'appuie.

---

## 5. Dashboard tile
Tuile du tableau de bord (patient & secrétariat) : compteur + libellé + action.

Anatomie : icône (24px) · valeur (token `h2`) · libellé (token `caption`) · zone cliquable entière.
Variantes : `default`, `alert` (bordure/teinte `warning`/`danger` si action requise : « 2 documents à signer »).
Accessibilité : tuile = bouton ; annoncer « 2 documents à signer, ouvrir ».

---

## 6. Message row (file messagerie)
Ligne d'un fil de messagerie côté cabinet.

Anatomie : avatar/initiales · expéditeur · extrait · horodatage · **badge `urgent`** si `triage_flag=urgent` · point « non lu ».
Tri : urgents en tête (priorisation **visuelle** — aucune décision clinique, cf. `../../docs/03` §2).
États : non lu (poids 500 + point `primary`), lu (400), sélectionné.
Accessibilité : annoncer l'état (« non lu, urgent »).

---

## 7. Agenda slot (back-office)
Créneau dans l'agenda praticien.

Anatomie : plage horaire · patient · motif · pastille de statut (`requested`/`confirmed`/`checked_in`/…).
Règle : data-dense mais lisible ; statut = pastille + texte. Drag/déplacement = interaction claire avec retour visuel.
Cloisonnement : le secrétariat voit l'administratif, pas le contenu clinique (vues distinctes).

---

## 8. Quote card / Amount (le wedge)
Affichage d'un devis et du reste à charge — l'écran qui doit être le plus soigné.

Anatomie : montant total (token `h2`/`display`), reste à charge mis en avant, échéances, **CTA primaire** (« Signer », puis « Payer l'acompte »), statut (badge).
Premium touch : accent `sable` discret possible sur l'en-tête ; chiffres alignés (`tabular figures`).
Accessibilité : montants lisibles, devise explicite (« 1 250 € »), parcours signature/paiement sans friction, états d'erreur paiement clairs (cf. `../../docs/06` E5.x).

---

## Navigation (rappel)
- **Mobile patient** : bottom nav 4-5 entrées (Accueil, RDV, Messages, Documents, Profil), radius `radius/xl` en haut si flottante.
- **Back-office** : sidebar gauche (Agenda, Patients, Devis, Messagerie), densité supérieure, `Inter` partout.

> Pour le détail layout/responsive/handoff dev : `../07-handoff/`. Implémentation thème : `03-flutter-theme.md`.
