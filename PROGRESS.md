# État du projet — Nubia

> Porteur de contexte entre machines. Lu en premier à chaque session (voir `CLAUDE.md`).
> Branche par défaut : `main`. Git : **Forgejo** (remote `origin`). CI : `.forgejo/workflows/`.

## En cours
- **🆕 SCOPE RÉVISÉ (02/06) : marketplace santé globale.** Plateforme deux faces — patient (trouver/réserver tout praticien, recherche multi-axes adresse/GPS/spécialité/besoin, carte, salle d'attente virtuelle, téléconsult) + logiciel cabinet. Cadré dans **`docs/11-marketplace-recherche.md`**. Impacts actés : PostGIS (géo), Meilisearch (recherche), **compte patient global** (ADR-011, révise `05`).
- **⭐ Univers UNIFIÉ** : l'app patient = UN seul univers (marketplace + espace perso), pas deux apps. Architecture d'info dans **`design/ia-navigation.md`** (nav 5 onglets : Rechercher/Mes RDV/Messages/Documents/Profil). Maquette de référence : **`design/mockups/nubia-univers.html`** (fait foi ; `nubia-maquettes.html` + `nubia-marketplace.html` = vues détaillées).
- **Phase DESIGN/UX.** Design system livré (`design/03-design-system/`). Flux `design/04-ux-flows/01-03`. User stories `design/user-stories.md` (sections patient + marketplace L→O), toutes logées dans la nav (voir `ia-navigation.md` §5).
- Direction de marque : **premium/esthétique · vert émeraude · clair+sombre · arrondi doux**, Inter + Fraunces.
- **STACK BACK : Rust / Axum.** Motifs : équipe forte en **Rust + Dart**, besoin de **WebSockets** + forte concurrence (cap ~1M users → Tokio). Toute la doc (01-09 + INSTRUCTIONS_PROJET + design handoff réseau) alignée. `api/` = workspace Cargo à scaffolder.
- Backend : PoC Flutter (`flutter_demo/`) + CI Forgejo OK. Scaffold `api/` Rust **à créer** (NUB-T0.1→T1.2). ⚠️ `docs/10` (POC Podman) perdu au reset, à recréer.

## Prochaines étapes
0. **🆕 Maquettes hi-fi intégrées (03/06)** : 4 fichiers dans `design/mockups/` (`Nubia Patient.html`, `Nubia Back-office.html`, `Nubia Spotlight.html`, `Nubia Comparatif.html` + `lib/` + provenance). Docs design **mises à jour** (`02-inventaire-ecrans`, `user-stories`, `ia-navigation`, `README`, nouveau `08-back-office-v2-spotlight.md`). Docs API **réalignées** (`05` §10, `06` E3.1.4/3.1.5/3.2.6/3.2.7 + E4.6→E4.10 + WS7, `07` §8.6/8.7/4.6-4.8, `11` §12). **À trancher : back-office V1 sidebar vs V2 Spotlight.**
1. **Design** : **package handoff dev livré** (`design/07-handoff/`). Reste : microcopy FR (`05-ux-copy/`), audit a11y formel (`06-accessibilite/` — inclure la nav clavier Spotlight), **étendre le handoff aux nouveaux écrans praticien** (consultation au fauteuil, plan & devis, ordonnance, journal clinique, onboarding RPPS).
2. **Arbitrer l'amorce marketplace** (solo/pré-seed) : démarrer sur une profession/zone vs plateforme large (cf. `docs/11` §14).
3. Intégrer le thème Flutter dans `flutter_demo/lib/theme/`.
4. **Backend** : créer le scaffold `api/` en **Rust/Axum** (workspace Cargo : `core/config`, `/health`, mode api/worker, SQLx + migrations, RLS tenant-scoped, 1ʳᵉ suite de tests d'isolation sous `nubia_app`) ; intégrer les modules marketplace (directory/search/geo/booking) au modèle ; puis NUB-T2 (auth/RBAC).
5. Re-câbler la CI `api/` en **Forgejo** ; recréer `docs/10` (POC Podman) si besoin.

## Décisions / notes importantes
- **Stack (actée 03/06)** : **Rust / Axum** modular monolith (workspace de crates) + **SQLx** (migrations `sqlx migrate` + requêtes vérifiées à la compil) · **Flutter partout** (patient + back-office), state management **Bloc (flutter_bloc)** + Dio · PostgreSQL 16 + Redis (**apalis**) + Object Storage · **WebSockets** (Axum, fan-out pub/sub Redis) + FCM. Auth : `jsonwebtoken` + `argon2` + middleware `tower`. Détails : `docs/04` ADR-002/004/005.
- **RLS** : `with_tenant(cabinet_id, |tx| …)` → transaction + `SET LOCAL app.current_cabinet_id = $1` (paramétré). Policies en `current_setting(...,true)` → fail-closed. ⚠️ effective seulement sous rôle Postgres **non-superuser** (`nubia_app`). ⚠️ sur WebSocket longue durée, réinjecter le contexte à chaque opération DB.
- **Drivers interchangeables par env** (POC↔prod) : Storage (MinIO/Scaleway), Mail (Mailpit/Brevo), SMS (log/OctoPush), Signature (Yousign sandbox/prod), KMS (local/Scaleway), Analytics (noop/PostHog).
- **Marketplace (révisions `docs/11`)** : compte **patient global** (`PatientAccount`, hors RLS) vs dossier clinique tenant ; **Meilisearch** (recherche) + **PostGIS** (géo) deviennent cœur ; annuaire public (profils `provider`, listé si RPPS vérifié) ; téléconsult + salle d'attente virtuelle réintégrés ; neutralité du ranking ; avis modérés rattachés à un vrai RDV.
- **POC** : mono-VPS **Podman**, données **fictives** (pas HDS). `infra/poc/compose.yml` + `Caddyfile` présents. ⚠️ `docs/10-deploiement-poc-vps.md` (le détail) a été **perdu au reset** — à recréer si besoin.
- **Conformité** : barrière prod = `docs/07` §11 (G3). **Pas de fonction dispositif médical** (MDR).
- **Couverture tests** : 100% sur le critique (`core/tenancy`…), élargir module par module.
- **🆕 Back-office — 2 paradigmes (03/06)** : V1 sidebar (validée comme base) vs V2 « Spotlight » (command-palette + assistant « Demander à Nubia »). Arbitrage ouvert (`design/08-back-office-v2-spotlight.md`, `docs/06` WS7).
- **🆕 Garde-fou MDR renforcé (03/06)** : l'écran **Ordonnance** des maquettes montre un blocage allergie/interactions + alternative → **EXCLU** (dispositif médical, `docs/07` §8.6). API = affichage passif des allergies, **aucun** moteur de contrôle. Idem **assistant IA** = organisationnel only, post-traction (§8.7).
- **🆕 Onboarding pro self-service (03/06)** : inscription cabinet + **vérification RPPS/ADELI (ANS)** ; `provider` listé seulement si vérifié. Complète le modèle « patient invité par cabinet ».
- **🆕 Couverture santé & proches (03/06)** : régime oblig. (Régime général/AME/CSS), carte mutuelle (doc chiffré), tiers payant ; **ayants droit** = `patient_account` liés par `account_guardianship` (`docs/05` §10.1-10.2).

## État par brique (granularité module)
Légende : ⬜ à faire · 🟨 en cours · ✅ fait

| Brique | Sujet | État |
|---|---|---|
| Docs 01-09 | Cadrage, archi, specs, conformité, plan, backlog | ✅ (réalignés stack Rust 03/06) |
| Doc 10 (POC Podman) | Déploiement VPS | ⚠️ perdu au reset, à recréer |
| Design system | Tokens + composants + thème Flutter | ✅ |
| Maquettes hi-fi | 4 fichiers `design/mockups/` (patient + back-office V1/V2 + comparatif) | ✅ (intégrées 03/06) |
| Design (flux/copy/a11y/handoff) | Reste du dossier `design/` ; handoff à étendre aux écrans praticien | 🟨 |
| Specs API vs maquettes | `docs/05` §10, `06` E4.6-E4.10/WS7, `07` §8.6-8.7 alignés | ✅ |
| Référence API | `docs/12-api-reference.md` (toutes les routes/contrats) | ✅ |
| Gestion DB | `db/` : migrations `0001→0012` + tests pgTAP + seed + Makefile + CI Forgejo + SCHEMA.md | ✅ (SQL exécutable ; `make test` vert from scratch — 118 tests) |
| T0 | Repo + CI (Forgejo) + infra POC | 🟨 scaffold Rust/Axum à créer + CI `api/` Forgejo |
| T1 | Multi-tenant + RLS | ⬜ à implémenter en Rust/SQLx |
| T2 | Auth + RBAC | 🟨 (register ✅, login/refresh/logout ⬜) |
| T3 | crypto + audit + tenancy | ⬜ (tenancy fait) |
| T4-T24 | Domaines, wedge, démo, prod | ⬜ |

## Dernier point
2026-06-03 (7) — **`POST /v1/auth/register` implémenté (issue #182).** Handler Axum public (sans JWT) : transaction atomique `app_user` + `patient_account` + `consent_record(purpose='soins')` + `refresh_token`. Mot de passe haché argon2 (Argon2::default). JWT patient émis (sub/kind/account_id, 15 min). Erreurs : `409 email_taken`, `422 cgu_required`, `422 password_policy`. 3 tests d'intégration verts (`cargo nextest`). `cargo clippy` + `cargo fmt --check` clean. **Bon moment pour committer.** Message suggéré : « Ajoute POST /v1/auth/register — création compte patient ».


2026-06-03 (6) — **DB `db/` : SQL exécutable livré + `make test` vert from scratch.** Écrit le contrat complet de la couche données :
- **Migrations `0001→0012`** (`db/migrations/`, SQLx, SQL pur, forward-only) : extensions+rôles · cabinet/identité · patient/clinique · documents · agenda (+**EXCLUDE** anti-double-booking) · wedge · messagerie · **audit partitionné** append-only · marketplace (PostGIS) · extensions hi-fi · **RLS (enable/force + policies fail-closed)** · index. S'appliquent **from scratch** en `nubia_owner`.
- **Tests pgTAP** (`db/tests/`, **118 tests, tous verts** sous `nubia_app`) : structure/colonnes/types/défauts/FK, rejets CHECK/NOT NULL/UNIQUE, **EXCLUDE** (chevauchement rejeté), **audit append-only** (UPDATE/DELETE refusés), **RLS** (fail-closed, non-fuite A↔B, WITH CHECK cross-tenant, entités plateforme visibles), **garde-fou** « table `cabinet_id` sans policy ».
- **Seed déterministe** (`db/seed/seed.sql`) : Cabinet Lyon fictif, idempotent (`ON CONFLICT DO NOTHING`, UUID/dates figés), RLS-aware. **Makefile** (`migrate/seed/test/reset/lint/verify-rls`, **aucun conteneur**), **CI Forgejo** `.forgejo/workflows/db.yml` + image `ci/db/` (`db-ci:stable`), **`db/SCHEMA.md`** (contrat API), **`.env.example`**.
- **Vérifié** : `make test` (reset→migrate→pgTAP) + `make seed verify-rls lint` **verts** sur PostgreSQL **16.4 + PostGIS 3.4 + pgTAP** (conteneur Podman local servant de « Postgres déjà présent »).
- **⚠️ Déviations vs `docs/05` (esquisse de réf.) à valider — Xav tranche :** (1) colonne générée `patient.is_minor` **supprimée** (impossible : `current_date` non IMMUTABLE → minorité calculée côté API) ; (2) extension **`btree_gist` ajoutée** (requise par l'EXCLUDE `practitioner_id WITH =`) ; (3) **`postgis` provisionnée par l'admin** au `reset` (extension *untrusted* → pas installable par `nubia_owner` non-superuser ; migration `0001` = `IF NOT EXISTS`) ; (4) policy unique **`tenant_isolation`** FOR ALL (USING+WITH CHECK) = `tenant_write` replié dedans ; (5) policies fail-closed durcies avec **`nullif(...,'')`** (robuste si GUC RESET) ; (6) **RLS de `review`/`patient_account` reportée à l'API** au MVP (visibilité published/titulaire portée applicativement) ; (7) `document.category` borné par **CHECK** (testable). ⚠️ **Image `db-ci` non build-testée localement** (Apple Silicon + qemu : `rustc` segfault en émulation amd64) — build natif OK sur runner amd64 ; **tous les outils qu'elle empaquette sont prouvés** (psql 16, sqlx 0.8.6, pg_prove 3.37). ⏭️ Reste : seed chiffré via binaire `nubia` (post-scaffold API). **Bon moment pour committer.** Message suggéré : « Ajoute le SQL exécutable de la base (migrations, tests pgTAP, seed, CI) ».

2026-06-03 (2) — **Maquettes hi-fi intégrées + docs design & API réalignées.** Reçu un bundle handoff Claude Design (4 maquettes + transcripts) → fichiers déposés dans `design/mockups/` (screenshots non versionnés, poids). **Design** : `02-inventaire-ecrans`, `user-stories` (US-P29→P32, US-D07→D12, section P/V01-V03), `ia-navigation`, `README` mis à jour ; nouveau `08-back-office-v2-spotlight.md`. **API** : `docs/05` §10 (couverture santé, proches/`account_guardianship`, journal clinique, `treatment_plan`, `prescription`, `provider_verification`, assistant, routing), `docs/06` (E3.1.4/5, E3.2.6/7, E4.6→E4.10, WS7), `docs/07` §8.6-8.7 + §4.6-4.8, `docs/11` §12. **Points durs tranchés en spec** : blocage médicamenteux & assistant clinique = **hors MDR** (affichage passif only) ; onboarding pro + RPPS ; couverture santé/proches au niveau plateforme. **À arbitrer avec Xav** : V1 sidebar vs V2 Spotlight. ⏭️ Spec only — pas de code. **Bon moment pour committer.** Message suggéré : « Intègre les maquettes hi-fi et réaligne les specs design + API ».

2026-06-03 (3) — **Nettoyage : repo full Rust.** Suppression de l'ancien scaffold TS dans `api/` (il ne reste que `api/README.md`, cible Rust) et effacement de toute mention de stack JS/TS dans la doc, pour éviter toute confusion au moment de coder. Stack figée : **Rust / Axum** (back), **Flutter + Bloc** (fronts), **WebSockets** (temps réel), **SQLx** (données), **apalis** (jobs). `api/` = workspace Cargo à scaffolder (NUB-T0.1→T1.2). **Bon moment pour committer.**

2026-06-03 (4) — **Référence API livrée : `docs/12-api-reference.md`.** Contrat complet de toutes les routes prêt à développer : conventions transverses (auth JWT patient/pro, RBAC + RLS, idempotence, erreurs RFC 9457, pagination, money en centimes), puis tous les modules — auth/onboarding RPPS, cabinet/membres, compte/couverture/proches, RDV + préparation (itinéraire), docs/coffre-fort, messagerie, **wedge** (devis→signature Yousign→paiement Stripe + webhooks), marketplace (search Meilisearch+PostGIS, annuaire, booking, avis), back-office (agenda/salle d'attente, patients/fiche cloisonnée, journal clinique, consultation CCAM, plan & devis, ordonnance **sans moteur d'interactions**), notifications/devices, **WebSocket** (canaux), webhooks, + annexes (V2 assistant post-traction, codes d'erreur, matrice rôles, ordre d'implémentation T0→). Référencé dans `docs/README` + `CLAUDE.md`. ⏭️ Spec only. **Bon moment pour committer.** Message suggéré : « Ajoute la référence API (docs/12) ».

2026-06-03 (5) — **Dossier `db/` créé (gestion PostgreSQL, source unique).** Spec/gouvernance, **pas de SQL exécutable** pour l'instant (`docs/05` reste le modèle). `db/README.md` : rôles (`nubia_owner`/`nubia_app` NOSUPERUSER+NOBYPASSRLS/`nubia_seed`), RLS opérationnelle (FORCE + fail-closed `current_setting(...,true)`), chiffrement colonne KMS/cabinet, rétention/soft-delete/purge, audit append-only partitionné, index, runbook migrations, environnements (POC→HDS), checklist G3. `db/migrations/README.md` : plan ordonné `0001→0012` (extensions/rôles → … → policies RLS → index) mappé sur `docs/05`. `db/seed/README.md` : jeu démo fictif aligné sur les maquettes. Câblé : `api/README` (`sqlx migrate run --source ../db/migrations`, rôles owner/app), `docs/05` + `docs/README` + `CLAUDE.md` cross-refs. ⏭️ Reste à écrire le SQL des migrations au scaffolding. **Bon moment pour committer.** Message suggéré : « Ajoute la gestion DB (dossier db/) ».

2026-06-03 — **Stack back actée : Rust / Axum.** Décision après arbitrage (équipe forte en Rust+Dart, besoin WebSockets + concurrence ~1M users). Doc alignée : `docs/01`, `02`, `03`, `04` (ADR-002/004/005), `08`, `09`, `11`, `README`, `INSTRUCTIONS_PROJET`, `CLAUDE.md`. Briques : Axum, SQLx, apalis (jobs Redis), WebSockets, `cargo test`, clippy.

2026-06-02 — Design system livré (`design/03-design-system/`) : direction premium/émeraude, tokens, composants, thème Flutter. ⚠️ Un reset git (passage Forgejo + ajout `flutter_demo`/CI) a supprimé `CLAUDE.md`, `PROGRESS.md`, `docs/10` et `.github/` — `CLAUDE.md`+`PROGRESS.md` recréés, **Bloc** re-appliqué (les docs étaient revenues à Riverpod). **À committer vite pour ne pas reperdre.** Prochaine session : flux UX (wedge) + intégrer le thème dans `flutter_demo`.
