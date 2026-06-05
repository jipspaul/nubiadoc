# design/ — UX, design system, handoff

Tu es dans la **partie design Nubia**. Pas de code applicatif ici, uniquement des specs.

## Layout
- `01-personas.md` — personas utilisateurs.
- `02-inventaire-ecrans.md` — liste des écrans.
- `03-design-system/` — tokens (couleurs, typo, spacings), composants, thème Flutter (`flutter_theme.dart` exportable).
- `04-ux-flows/` — flows utilisateur (mermaid ou markdown).
- `05-ux-copy/` — copy (FR/EN), tone of voice.
- `06-accessibilite/` — règles a11y (AA minimum, AAA pour les flows critiques).
- `07-handoff/` — handoff vers dev (specs détaillées par écran).
- `08-back-office-v2-spotlight.md` — focus sur la v2 du back-office.

## Règles dures
1. **Pas de pixel-perfect en absolu.** Les tokens du design system (`03-design-system/`) sont la source de vérité — les écrans doivent les utiliser, pas dupliquer leurs valeurs.
2. **A11y AA minimum** sur tout flow utilisateur. Contraste, taille de touche tactile (44px), focus visible, labels d'accessibilité.
3. **Copy FR par défaut.** EN est une traduction, pas une variante. Toute string a un identifiant stable utilisé côté Flutter (`AppLocalizations`).
4. **Pas de feature design "dispositif médical"** (interactions médicamenteuses, aide à la décision clinique) — interdit produit (cf. `docs/07` §8).
5. **Cohérence inter-écrans** : un nouvel écran réutilise les composants existants avant d'en créer de nouveaux. Si nouveau composant : il rentre dans `03-design-system/`.

## Workflow
- Écrire/modifier les `.md` directement.
- Si tu ajoutes un visuel, mets-le dans `<dossier>/assets/` et référence-le en relatif.
- `markdownlint` côté CI (`.forgejo/workflows/`).

## Référence
- Personas → écrans : `01-personas.md` → `02-inventaire-ecrans.md`.
- Composants Flutter consommateurs : `app/lib/features/<feature>/` + `app/ARCHITECTURE.md`.
