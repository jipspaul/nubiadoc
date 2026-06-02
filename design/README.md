# Design & UX — Nubia

Espace de travail design/UX du projet. On attaque ici **avant d'aller plus loin dans la tech** : parcours, écrans, design system, copy, accessibilité, handoff.

Tout est ancré sur ce qui est déjà cadré côté produit/tech (voir `../docs/`) :
- **Cibles** : patient (app mobile Flutter), praticien & secrétariat (back-office Flutter Web/Desktop).
- **Périmètre démo** : les 12 rubriques du PDF patient (cf. `../docs/06`), dont certaines mockées 🎭.
- **Le wedge** : devis → signature → acompte (le parcours qui doit être impeccable).
- **Stack front** : Flutter + **Bloc** (state) — le design system doit se traduire proprement en widgets Flutter.

## Structure du dossier
| Fichier / dossier | Contenu | Skill design associée |
|---|---|---|
| `01-personas.md` | 3 personas (patient, praticien, secrétariat) — amorcés | `user-research` / `research-synthesis` |
| `02-inventaire-ecrans.md` | Inventaire des écrans & flux, priorité prod/démo — amorcé | — |
| `03-design-system/` | Tokens (couleurs, typo, espacements), composants, états | `design-system` |
| `04-ux-flows/` | Parcours clés (onboarding, RDV, devis→acompte, messagerie) | `design-critique` |
| `05-ux-copy/` | Microcopy, messages d'erreur, états vides, CTA | `ux-copy` |
| `06-accessibilite/` | Audit RGAA / WCAG 2.1 AA | `accessibility-review` |
| `07-handoff/` | Specs de handoff vers le dev Flutter | `design-handoff` |
| `assets/` | Exports d'images, maquettes, captures | — |

## Méthode suggérée (ordre)
1. **Cadrer les utilisateurs** : finaliser `01-personas.md` (idéalement avec de vrais entretiens cabinets, cf. `../docs/02` Étape 0).
2. **Cartographier** : valider `02-inventaire-ecrans.md` et prioriser pour la **démo investisseurs** (parcours scénarisé).
3. **Parcours** : dessiner les flux clés (`04-ux-flows/`), en commençant par le wedge.
4. **Design system** : poser les tokens et composants (`03-design-system/`) — pensés « Flutter/Bloc ».
5. **Copy** : écrire la microcopy (`05-ux-copy/`) en français, ton du produit.
6. **Accessibilité** : auditer (`06-accessibilite/`) avant le handoff.
7. **Handoff** : specs dev (`07-handoff/`) pour traduire en widgets.

## Garde-fous design (cohérence produit)
- **Démo = données fictives crédibles** ; les écrans 🎭 doivent être beaux même sans logique réelle derrière.
- **Cloisonnement praticien / secrétariat** (secret médical) : le design du back-office doit refléter des vues différentes selon le rôle.
- **Zéro friction sur le wedge** : signer un devis et payer un acompte doit être le parcours le plus fluide de l'app.
- **Accessibilité réelle** : app santé grand public → contrastes, tailles de cible, lisibilité (visée RGAA).
- **Pas de promesse clinique** dans l'UI/copy (cf. garde-fous médicolégaux `../docs/03`, `../docs/07`).
