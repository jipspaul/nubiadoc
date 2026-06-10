# Plan d'implémentation — App Patient Nubia (Flutter)

> **Version 2.1 — 2026-06-09** · Fichier **routeur** (court). Le détail vit dans [`docs/plan/`](docs/plan/).
> Périmètre : App mobile patient (iOS/Android), épics **E3.x** + marketplace **E5.x** + **Compagnon Nubia (GenUI/A2UI)**.
> Architecture : hexagonale (Ports & Adapters) · State : BLoC · Tests : unit + widget + integration.
> Réfs produit : `../docs/02`, `../docs/06`, `../design/ia-navigation.md`, `../design/07-handoff/`.

## Pourquoi cette V2

La V1 listait M0→M12 **toutes cases vides**. En réalité, **l'ossature et la majorité des features sont déjà livrées** (auth, dashboard, RDV, messagerie, documents, profil, notifications + features pro). Cette V2 :

1. **Réaligne l'état réel** → [`docs/plan/00-etat-reel.md`](docs/plan/00-etat-reel.md).
2. **Introduit la direction UX « Compagnon Nubia »** (GenUI/A2UI, façon *Personal Health Companion*, borné conformité) → [`docs/plan/02-ux-compagnon-genui.md`](docs/plan/02-ux-compagnon-genui.md).
3. **Découpe le reste en issues atomiques**, un fichier par lot, pour ne charger qu'un petit fichier par agent.

## Comment utiliser ce plan (pour un agent)

> Charge **uniquement** : ce routeur + [`01-conventions.md`](docs/plan/01-conventions.md) + **le fichier du lot de ton issue**.
> Pour le lot E, lis **en plus** [`02-ux-compagnon-genui.md`](docs/plan/02-ux-compagnon-genui.md) (garde-fous conformité).

## Sommaire

| Doc | Contenu |
|---|---|
| [`docs/plan/00-etat-reel.md`](docs/plan/00-etat-reel.md) | Inventaire fait / partiel / à faire + dette repérée |
| [`docs/plan/01-conventions.md`](docs/plan/01-conventions.md) | Philosophie, gabarit d'issue, commandes, **Definition of Done** |
| [`docs/plan/02-ux-compagnon-genui.md`](docs/plan/02-ux-compagnon-genui.md) | Direction UX GenUI/A2UI + **garde-fous conformité** + arbitrages #E0 |

## Milestones restants → lots d'issues

| # | Milestone | Lot (fichier) | Durée | Dépend de |
|---|-----------|---------------|-------|-----------|
| **R1** | Finaliser le **Wedge** (devis → signature → acompte Stripe) | [Lot A](docs/plan/lot-a-wedge.md) | 2 sem | M3,M6 ✅ |
| **R2** | **Espace financier** 🎭 (factures, échéancier) | [Lot B](docs/plan/lot-b-financier.md) | 1 sem | R1 |
| **R3** | **Écrans 🎭** (plan de traitement, passeport, prévention) | [Lot C](docs/plan/lot-c-ecrans-demo.md) | 1 sem | M0 ✅ |
| **R4** | **Marketplace / Recherche** (E5.x) | [Lot D](docs/plan/lot-d-marketplace.md) | 2 sem | M1 ✅ |
| **R5** | **Compagnon Nubia (GenUI/A2UI)** ⭐ | [Lot E](docs/plan/lot-e-compagnon.md) | 3–4 sem | M2,M3,M5 |
| **R6** | **i18n + a11y + polish + mode démo** | [Lot F](docs/plan/lot-f-polish.md) | 1–2 sem | tout |
| **R7** | **Tests d'intégration** (flows E2E) | [Lot G](docs/plan/lot-g-integration.md) | 1 sem | R1,R4 |
| **R8** | **Dette & hygiène** | [Lot H](docs/plan/lot-h-dette.md) | continu | — |

**47 issues atomiques** au total (A1–A7, B1–B3, C1–C3, D1–D5, E0–E11, F1–F6, G1–G8, H1–H3).

## Dépendances entre lots

```
M2/M3/M6 ✅ ──> A (wedge) ──> B (financier)
M0 ✅ ──────────> C (écrans 🎭)
M1 ✅ ──────────> D (marketplace)
A + C + M3 ────> E (Compagnon GenUI)  ⭐
tout ──────────> F (polish/i18n/démo)
A + D ─────────> G (intégration E2E)
H (dette) ⟂ continu ; H1 ──> F3
```

Graphe inter-issues détaillé : en bas de chaque fichier de lot (section « Séquence interne »).
