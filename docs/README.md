# Documentation technique — Nubia (SaaS HealthTech dentaire)

Documentation de cadrage du projet. Elle part du brief existant
(`../INSTRUCTIONS_PROJET.md` + `nubiaDoc.pdf`) pour le challenger et en tirer un
plan d'exécution réaliste.

## État réel du projet

- **Stade** : pré-seed, exécution **solo / petite équipe**, sans financement levé.
- **Front confirmé** : Flutter (app patient). Back : NestJS modular monolith. Infra souveraine managée Scaleway.
- **Principe directeur** : le brief décrit une *vision* (plateforme tout-en-un, 7 piliers, équipe 10-15, 2,5 M€). La documentation ci-dessous la traduit en un *MVP exécutable* centré sur un wedge.

## Sommaire

| Fichier | Contenu |
|---|---|
| [`01-critique-du-brief.md`](./01-critique-du-brief.md) | Challenge critique du brief : écart d'échelle solo/pré-seed, incohérence app patient (PDF) vs plateforme (MD), stack sur-dimensionnée, périmètre des 7 piliers, chiffres business, angles morts réglementaires (HDS, AI Act, **dispositif médical/MDR**). |
| [`02-decoupe-projet.md`](./02-decoupe-projet.md) | Découpe step-by-step : organisation cible « équipe de 10 » (workstreams), épics → user stories, **roadmap réaliste solo** avec jalons Go/No-Go, backlog MoSCoW, conventions de delivery (DoR/DoD). |
| [`03-temps-reel-et-sync.md`](./03-temps-reel-et-sync.md) | Synchro mobile ↔ cabinet : tri des interactions « écosystème vivant » (MVP / post-traction / écarté), garde-fous médicolégaux, architecture de synchro retenue, décision app Compagnon praticien. |
| [`04-architecture.md`](./04-architecture.md) | Architecture cible : schémas C4 (contexte/conteneurs/composants), flux clés, **10 ADRs**, contrats d'API REST, sécurité transverse, environnements. |
| [`05-modele-de-donnees.md`](./05-modele-de-donnees.md) | Schéma PostgreSQL : entités par domaine (DDL de référence), **RLS multi-tenant**, chiffrement colonne, rétention/soft-delete, JSONB, index. |
| [`06-specs-fonctionnelles.md`](./06-specs-fonctionnelles.md) | User stories par épic (E3.1→E5.5) en **Gherkin**, marquage prod/démo, critères d'acceptation transverses. |
| [`07-conformite.md`](./07-conformite.md) | Checklist opérationnelle **HDS / RGPD / AIPD / eIDAS / AI Act / MDR / Ségur** avec statuts, et la **barrière minimale avant le pilote prod (G3)**. |
| [`08-plan-action-deploiement.md`](./08-plan-action-deploiement.md) | Plan d'exécution **tâche par tâche** (T0→T24) ordonné par **dépendances** (DAG), **gate de validation testée** par tâche, **stratégie de tests near-100%** (RLS/sécurité, mutation, seuils CI), pipeline CI/CD et procédure de release staging→démo→prod. |
| [`09-backlog-issues.md`](./09-backlog-issues.md) | **Backlog issue-ready** : chaque brique éclatée en issues `NUB-T<n>.<k>` avec micro-étapes cochables, dépendances, critères d'acceptation/tests, labels et estimations. Stack actée (NestJS+Prisma, pattern RLS détaillé). À copier directement dans tes issues. |

## Comment lire

1. Commence par la **critique** (`01`) — elle pose le diagnostic et les arbitrages.
2. Enchaîne sur la **découpe** (`02`) — elle traduit ces arbitrages en plan d'action.
3. `03` à `07` détaillent la mise en œuvre : synchro, architecture, données, specs, conformité.
4. **Pour démarrer le dev : `08`** (l'ordre des tâches, dépendances, tests) puis **`09`** (les issues prêtes à créer, une par une).

## Les 3 décisions structurantes retenues

1. **Démo investisseurs vs pilote prod** = pour la levée, l'app patient montre **les 12 rubriques du PDF** (mocks autorisés 🎭, données fictives) ; pour la prod, on durcit un **wedge réel** plus étroit : RDV + dossier + devis/signature/acompte. Section 13 (avancé) exclue, sauf paiement.
2. **Stack dégraissée** : **Flutter partout** (app patient + back-office) + NestJS + PostgreSQL + Redis + Object Storage, tout en **managé Scaleway** ; observabilité/analytics via **PostHog (EU Cloud)**. On reporte Temporal, NATS, microservices Python/IA, Meilisearch, TimescaleDB, Keycloak, Kubernetes et le self-hosted.
3. **Conformité par le design** : on exclut du MVP toute fonction qui qualifierait en dispositif médical (interactions médicamenteuses, aide à la prescription/décision) et on reporte l'IA Scribe (chantier AI Act « haut risque »).

## Prochaines étapes de documentation (idées)

Le socle (01→09) est complet. Pistes pour la suite quand tu voudras :

- `10-design-system.md` — tokens, composants Flutter, parcours UI.
- `11-runbook-ops.md` — incidents, sauvegardes/restauration, astreinte (détaille `08` §7).
- `pitch/` — deck investisseurs adossé au jalon démo 🎬.
- **Scaffold du repo** : je peux générer la structure NestJS+Prisma avec T0.1→T1.2 (RLS + 1ère suite de tests d'isolation) prête à coder.

> Dis-moi lequel tu veux attaquer.
