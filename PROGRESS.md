# État du projet — Nubia

> Porteur de contexte entre machines. Lu en premier à chaque session (voir `CLAUDE.md`).
> Branche par défaut : `main`. Git : **Forgejo** (remote `origin`). CI : `.forgejo/workflows/`.

## En cours
- **🆕 SCOPE RÉVISÉ (02/06) : marketplace santé globale.** Plateforme deux faces — patient (trouver/réserver tout praticien, recherche multi-axes adresse/GPS/spécialité/besoin, carte, salle d'attente virtuelle, téléconsult) + logiciel cabinet. Cadré dans **`docs/11-marketplace-recherche.md`**. Impacts actés : PostGIS (géo), Meilisearch (recherche), **compte patient global** (ADR-011, révise `05`).
- **⭐ Univers UNIFIÉ** : l'app patient = UN seul univers (marketplace + espace perso), pas deux apps. Architecture d'info dans **`design/ia-navigation.md`** (nav 5 onglets : Rechercher/Mes RDV/Messages/Documents/Profil). Maquette de référence : **`design/mockups/nubia-univers.html`** (fait foi ; `nubia-maquettes.html` + `nubia-marketplace.html` = vues détaillées).
- **Phase DESIGN/UX.** Design system livré (`design/03-design-system/`). Flux `design/04-ux-flows/01-03`. User stories `design/user-stories.md` (sections patient + marketplace L→O), toutes logées dans la nav (voir `ia-navigation.md` §5).
- Direction de marque : **premium/esthétique · vert émeraude · clair+sombre · arrondi doux**, Inter + Fraunces.
- Backend : scaffold `api/` posé et commité (Bloc A : NestJS+Prisma, RLS, tenancy). PoC Flutter (`flutter_demo/`) + CI Forgejo. ⚠️ `docs/10` (POC Podman) perdu au reset, à recréer.

## Prochaines étapes
1. **Design** : **package handoff dev livré** (`design/07-handoff/` : fondations + 22 composants + specs écran/critères) + hi-fi annoté (`design/mockups/nubia-hifi.html`). Reste : microcopy FR (`05-ux-copy/`), audit a11y formel (`06-accessibilite/`), specs des écrans secondaires.
2. **Arbitrer l'amorce marketplace** (solo/pré-seed) : démarrer sur une profession/zone vs plateforme large (cf. `docs/11` §14).
3. Intégrer le thème Flutter dans `flutter_demo/lib/theme/`.
4. **Backend** : valider le scaffold `api/` (npm install, tests, e2e RLS sous `nubia_app`) ; intégrer les modules marketplace (directory/search/geo/booking) au modèle ; puis NUB-T2 (auth/RBAC).
5. Re-câbler la CI `api/` en **Forgejo** ; recréer `docs/10` (POC Podman) si besoin.

## Décisions / notes importantes
- **Stack** : NestJS modular monolith (TS strict) + Prisma (+ `pg` pour RLS) · **Flutter partout** (patient + back-office), state management **Bloc (flutter_bloc)** + Dio · PostgreSQL 16 + Redis (BullMQ) + Object Storage · SSE + FCM.
- **RLS** : `TenancyService.withTenant(cabinetId, tx => …)` → transaction + `set_config('app.current_cabinet_id',$1,true)` (paramétré). Policies en `current_setting(...,true)` → fail-closed. ⚠️ effective seulement sous rôle Postgres **non-superuser** (`nubia_app`).
- **Drivers interchangeables par env** (POC↔prod) : Storage (MinIO/Scaleway), Mail (Mailpit/Brevo), SMS (log/OctoPush), Signature (Yousign sandbox/prod), KMS (local/Scaleway), Analytics (noop/PostHog).
- **Marketplace (révisions `docs/11`)** : compte **patient global** (`PatientAccount`, hors RLS) vs dossier clinique tenant ; **Meilisearch** (recherche) + **PostGIS** (géo) deviennent cœur ; annuaire public (profils `provider`, listé si RPPS vérifié) ; téléconsult + salle d'attente virtuelle réintégrés ; neutralité du ranking ; avis modérés rattachés à un vrai RDV.
- **POC** : mono-VPS **Podman**, données **fictives** (pas HDS). `infra/poc/compose.yml` + `Caddyfile` présents. ⚠️ `docs/10-deploiement-poc-vps.md` (le détail) a été **perdu au reset** — à recréer si besoin.
- **Conformité** : barrière prod = `docs/07` §11 (G3). **Pas de fonction dispositif médical** (MDR).
- **Couverture tests** : 100% sur le critique (`core/tenancy`…), élargir module par module.

## État par brique (granularité module)
Légende : ⬜ à faire · 🟨 en cours · ✅ fait

| Brique | Sujet | État |
|---|---|---|
| Docs 01-09 | Cadrage, archi, specs, conformité, plan, backlog | ✅ |
| Doc 10 (POC Podman) | Déploiement VPS | ⚠️ perdu au reset, à recréer |
| Design system | Tokens + composants + thème Flutter | ✅ |
| Design (flux/copy/a11y/handoff) | Reste du dossier `design/` | ⬜ |
| T0 | Repo + CI (Forgejo) + infra POC | 🟨 scaffold posé ; CI `api/` à recréer en Forgejo |
| T1 | Multi-tenant + RLS | 🟨 schéma+RLS+tests écrits, à valider |
| T2 | Auth + RBAC | ⬜ |
| T3 | crypto + audit + tenancy | ⬜ (tenancy fait) |
| T4-T24 | Domaines, wedge, démo, prod | ⬜ |

## Dernier point
2026-06-02 — Design system livré (`design/03-design-system/`) : direction premium/émeraude, tokens, composants, thème Flutter. ⚠️ Un reset git (passage Forgejo + ajout `flutter_demo`/CI) a supprimé `CLAUDE.md`, `PROGRESS.md`, `docs/10` et `.github/` — `CLAUDE.md`+`PROGRESS.md` recréés, **Bloc** re-appliqué (les docs étaient revenues à Riverpod). **À committer vite pour ne pas reperdre.** Prochaine session : flux UX (wedge) + intégrer le thème dans `flutter_demo`.
