# Instructions agents (Claude Code & opencode)

> Ce fichier était historiquement la racine d'instructions. Le contenu fin a été déplacé dans des `AGENTS.md` par dossier (lazy-load par Claude Code).
> **Lis `AGENTS.md` (racine) en premier** — c'est un router court qui te pointe vers le bon `<dossier>/AGENTS.md`.

## Workflow git (rappel court)
- Remote = **Forgejo** (`origin`), branche par défaut `main`.
- Commits faits par les agents (push auto via leur token Forgejo) ; humains review/merge.
- Avant de commencer : `git pull` puis lecture de `PROGRESS.md` (résumé d'état) + `AGENTS.md` racine.
- Tout choix structurant (archi, dépendance) → noté dans `PROGRESS.md` section « Décisions / notes ».
- Le détail fin par brique vit dans `docs/09-backlog-issues.md` + les issues Forgejo.

## Fin d'étape
1. Mettre à jour `PROGRESS.md` (fait + prochaines étapes + tableau d'état).
2. Push sur la branche `agent/<…>` puis ouvrir la PR vers `main` (en français, impératif).
3. La CI doit être verte (build + tests + `test-integrity`) avant qu'un humain merge.

## Pointeurs
- Routing par dossier : `AGENTS.md` (racine).
- État courant : `PROGRESS.md`.
- Backlog : `docs/09-backlog-issues.md`.
