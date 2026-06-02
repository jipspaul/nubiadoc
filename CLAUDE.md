# Instructions projet — pour les agents Cowork / Claude

Ce projet (Nubia, SaaS dentaire) est travaillé **depuis plusieurs Mac**. La continuité passe **uniquement par le repo git**, jamais par l'état local d'une session. Respecte ce workflow **automatiquement**.

> Git : **Forgejo** (remote `origin`), branche par défaut `main`. CI : `.forgejo/workflows/`.
> ⚠️ Les commits sont faits **par Xav** (le sandbox n'a pas les accès SSH). Mon rôle : produire les fichiers, tenir `PROGRESS.md` à jour, et **signaler quand c'est un bon moment de committer**.

## Au démarrage de CHAQUE session
1. `git pull` pour récupérer le dernier état.
2. Lis **`PROGRESS.md`** : où on en était + prochaines étapes + tableau d'état par brique.
3. `git status` et **annonce la branche** avant de commencer.

## Pendant le travail
- Travaille dans le dossier du repo.
- Tout **choix structurant** (archi, convention, dépendance) → noté dans `PROGRESS.md` (section « Décisions / notes »).
- Le **détail fin par brique** vit dans `docs/09-backlog-issues.md` + les issues. Ne pas dupliquer.

## Fin d'étape / quand on s'arrête
1. Mettre à jour **`PROGRESS.md`** (fait + prochaines étapes concrètes + tableau d'état).
2. **Signaler à Xav que c'est un bon moment de committer** (c'est lui qui commit/pull/push).
3. Message de commit suggéré : **impératif, en français**, clair (ex. « Ajoute le design system »). Jamais « update »/« wip ».

## Règles git (rappel pour Xav)
- Jamais de `--force` sans validation.
- Sur conflit de `git pull` : s'arrêter, montrer les fichiers, ne pas merger seul.
- Ne pas toucher `main` directement si une branche de feature est active.
- ⚠️ **Committer souvent** : un fichier non commité peut être perdu lors d'un reset/pull (déjà arrivé le 02/06).

## Gestion du suivi (PROGRESS)
- **Un seul `PROGRESS.md` racine** = porteur de contexte. Pas un fichier par brique (fragmente + pourrit). Granularité module = le **tableau d'état** dans `PROGRESS.md`.
- Exception : un gros chantier multi-sessions peut avoir un `docs/progress/T<xx>.md` dédié, pointé depuis `PROGRESS.md`.

## Repères du repo
- `docs/` — cadrage : `01` critique · `02` découpe · `03` temps réel · `04` archi · `05` données · `06` specs · `07` conformité · `08` plan/tests · `09` backlog d'issues. (`10` POC Podman : à recréer, perdu au reset.)
- `design/` — design/UX : `01` personas · `02` inventaire écrans · `03-design-system/` (tokens, composants, thème Flutter) · `04` flux · `05` copy · `06` a11y · `07` handoff.
- `api/` — backend NestJS (scaffold Bloc A : RLS, tenancy, /health, drivers).
- `flutter_demo/` — PoC Flutter (CI). `infra/poc/` — POC Podman (compose + Caddy). `tests/e2e/` — e2e web.

## Garde-fous produit
- **POC / démo = données fictives uniquement.** Aucune donnée patient réelle avant la barrière G3 (`docs/07` §11).
- **RLS multi-tenant + chiffrement + audit** dès le départ (non rétrofittables).
- **Pas de fonction « dispositif médical »** (interactions médicamenteuses, aide à la décision) — `docs/07` §8.
- Front **Flutter + Bloc**. Conteneurs **Podman** (pas Docker). IA souveraine (Mistral/Scaleway), pas avant la traction.
