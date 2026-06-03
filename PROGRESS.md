# État du projet — Nubia

> Porteur de contexte entre machines. Lu en premier à chaque session (voir `CLAUDE.md`).
> Branche par défaut : `main`. Git : **Forgejo** (remote `origin`). CI : `.forgejo/workflows/`.

## En cours
- **🆕 SCOPE RÉVISÉ (02/06) : marketplace santé globale.** Plateforme deux faces — patient (trouver/réserver tout praticien, recherche multi-axes adresse/GPS/spécialité/besoin, carte, salle d'attente virtuelle, téléconsult) + logiciel cabinet. Cadré dans **`docs/11-marketplace-recherche.md`**. Impacts actés : PostGIS (géo), Meilisearch (recherche), **compte patient global** (ADR-011, révise `05`).
- **⭐ Univers UNIFIÉ** : l'app patient = UN seul univers (marketplace + espace perso), pas deux apps. Architecture d'info dans **`design/ia-navigation.md`** (nav 5 onglets : Rechercher/Mes RDV/Messages/Documents/Profil). Maquette de référence : **`design/mockups/nubia-univers.html`** (fait foi ; `nubia-maquettes.html` + `nubia-marketplace.html` = vues détaillées).
- **Phase DESIGN/UX.** Design system livré (`design/03-design-system/`). Flux `design/04-ux-flows/01-03`. User stories `design/user-stories.md` (sections patient + marketplace L→O), toutes logées dans la nav (voir `ia-navigation.md` §5).
- Direction de marque : **premium/esthétique · vert émeraude · clair+sombre · arrondi doux**, Inter + Fraunces.
- **🔁 DÉCISION STACK (03/06) : back en Rust / Axum.** Adieu NestJS/Node **et** Next.js. Motifs : équipe forte en **Rust + Dart**, besoin de **WebSockets** + forte concurrence (cap ~1M users → Tokio). Toute la doc (01-09 + INSTRUCTIONS_PROJET + design handoff réseau) réalignée. ⚠️ L'ancien scaffold `api/` (NestJS+Prisma) est **obsolète** → à remplacer par un workspace Cargo.
- Backend : PoC Flutter (`flutter_demo/`) + CI Forgejo OK. Scaffold `api/` Rust **à créer** (NUB-T0.1→T1.2). ⚠️ `docs/10` (POC Podman) perdu au reset, à recréer.

## Prochaines étapes
1. **Design** : **package handoff dev livré** (`design/07-handoff/` : fondations + 22 composants + specs écran/critères) + hi-fi annoté (`design/mockups/nubia-hifi.html`). Reste : microcopy FR (`05-ux-copy/`), audit a11y formel (`06-accessibilite/`), specs des écrans secondaires.
2. **Arbitrer l'amorce marketplace** (solo/pré-seed) : démarrer sur une profession/zone vs plateforme large (cf. `docs/11` §14).
3. Intégrer le thème Flutter dans `flutter_demo/lib/theme/`.
4. **Backend** : créer le scaffold `api/` en **Rust/Axum** (workspace Cargo : `core/config`, `/health`, mode api/worker, SQLx + migrations, RLS tenant-scoped, 1ʳᵉ suite de tests d'isolation sous `nubia_app`) ; intégrer les modules marketplace (directory/search/geo/booking) au modèle ; puis NUB-T2 (auth/RBAC). Supprimer l'ancien scaffold NestJS.
5. Re-câbler la CI `api/` en **Forgejo** ; recréer `docs/10` (POC Podman) si besoin.

## Décisions / notes importantes
- **Stack (actée 03/06)** : **Rust / Axum** modular monolith (workspace de crates) + **SQLx** (migrations `sqlx migrate` + requêtes vérifiées à la compil) · **Flutter partout** (patient + back-office), state management **Bloc (flutter_bloc)** + Dio · PostgreSQL 16 + Redis (**apalis**) + Object Storage · **WebSockets** (Axum, fan-out pub/sub Redis) + FCM. Auth : `jsonwebtoken` + `argon2` + middleware `tower`. Détails : `docs/04` ADR-002/004/005.
- **RLS** : `with_tenant(cabinet_id, |tx| …)` → transaction + `SET LOCAL app.current_cabinet_id = $1` (paramétré). Policies en `current_setting(...,true)` → fail-closed. ⚠️ effective seulement sous rôle Postgres **non-superuser** (`nubia_app`). ⚠️ sur WebSocket longue durée, réinjecter le contexte à chaque opération DB.
- **Drivers interchangeables par env** (POC↔prod) : Storage (MinIO/Scaleway), Mail (Mailpit/Brevo), SMS (log/OctoPush), Signature (Yousign sandbox/prod), KMS (local/Scaleway), Analytics (noop/PostHog).
- **Marketplace (révisions `docs/11`)** : compte **patient global** (`PatientAccount`, hors RLS) vs dossier clinique tenant ; **Meilisearch** (recherche) + **PostGIS** (géo) deviennent cœur ; annuaire public (profils `provider`, listé si RPPS vérifié) ; téléconsult + salle d'attente virtuelle réintégrés ; neutralité du ranking ; avis modérés rattachés à un vrai RDV.
- **POC** : mono-VPS **Podman**, données **fictives** (pas HDS). `infra/poc/compose.yml` + `Caddyfile` présents. ⚠️ `docs/10-deploiement-poc-vps.md` (le détail) a été **perdu au reset** — à recréer si besoin.
- **Conformité** : barrière prod = `docs/07` §11 (G3). **Pas de fonction dispositif médical** (MDR).
- **Couverture tests** : 100% sur le critique (`core/tenancy`…), élargir module par module.

## État par brique (granularité module)
Légende : ⬜ à faire · 🟨 en cours · ✅ fait

| Brique | Sujet | État |
|---|---|---|
| Docs 01-09 | Cadrage, archi, specs, conformité, plan, backlog | ✅ (réalignés stack Rust 03/06) |
| Doc 10 (POC Podman) | Déploiement VPS | ⚠️ perdu au reset, à recréer |
| Design system | Tokens + composants + thème Flutter | ✅ |
| Design (flux/copy/a11y/handoff) | Reste du dossier `design/` | ⬜ |
| T0 | Repo + CI (Forgejo) + infra POC | 🟨 ancien scaffold NestJS obsolète ; scaffold Rust/Axum à créer + CI `api/` Forgejo |
| T1 | Multi-tenant + RLS | ⬜ à refaire en Rust/SQLx (le travail NestJS est jeté) |
| T2 | Auth + RBAC | ⬜ |
| T3 | crypto + audit + tenancy | ⬜ (tenancy fait) |
| T4-T24 | Domaines, wedge, démo, prod | ⬜ |

## Dernier point
2026-06-03 — **Bascule stack : back en Rust / Axum, abandon de NestJS/Node et de Next.js.** Décision prise après arbitrage (équipe forte en Rust+Dart, besoin WebSockets + concurrence ~1M users). Toute la doc réalignée : `docs/01`, `02`, `03`, `04` (ADR-002/004/005 réécrits), `08`, `09`, `11`, `README`, `INSTRUCTIONS_PROJET`, `CLAUDE.md`. Mapping appliqué : NestJS→Axum, Prisma→SQLx, BullMQ→apalis, SSE/Socket.IO→WebSockets, Jest→`cargo test`, ESLint→clippy. **L'ancien scaffold `api/` (NestJS+Prisma) est obsolète, à supprimer et recréer en workspace Cargo.** ⏭️ Prochaine session : scaffold Rust NUB-T0.1→T1.2. **Bon moment pour committer.**

2026-06-02 — Design system livré (`design/03-design-system/`) : direction premium/émeraude, tokens, composants, thème Flutter. ⚠️ Un reset git (passage Forgejo + ajout `flutter_demo`/CI) a supprimé `CLAUDE.md`, `PROGRESS.md`, `docs/10` et `.github/` — `CLAUDE.md`+`PROGRESS.md` recréés, **Bloc** re-appliqué (les docs étaient revenues à Riverpod). **À committer vite pour ne pas reperdre.** Prochaine session : flux UX (wedge) + intégrer le thème dans `flutter_demo`.
