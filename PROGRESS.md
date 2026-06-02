# État du projet — Nubia

> Porteur de contexte entre machines. Lu en premier à chaque session (voir `CLAUDE.md`).
> Branche par défaut : `main`. Git : **Forgejo** (remote `origin`). CI : `.forgejo/workflows/`.

## En cours
- **Phase DESIGN/UX.** Dossier `design/` créé (personas + inventaire écrans amorcés). **Design system livré** dans `design/03-design-system/` : tokens, composants, thème Flutter.
- Direction de marque actée : **premium/esthétique · primaire vert émeraude (#059669 identité / #047857 bouton clair) · clair+sombre · angles arrondis doux**, typo Inter + Fraunces (`google_fonts`).
- Backend : **scaffold `api/` posé et commité** (Bloc A : NestJS+Prisma, RLS, tenancy, /health, drivers). Validation `npm install` + CI à faire.
- PoC Flutter présent (`flutter_demo/`) + CI Forgejo (flutter-test, web-e2e) + `tests/e2e`.

## Prochaines étapes
1. **Design** : appliquer le design system aux flux clés (`design/04-ux-flows/`), commencer par le wedge devis→signature→acompte ; puis copy (`05`), a11y (`06`).
2. Intégrer le thème Flutter (`design/03-design-system/03-flutter-theme.md`) dans `flutter_demo/lib/theme/` (Inter + Fraunces).
3. **Backend** : valider le scaffold `api/` (`npm install`, lint/typecheck/test, e2e RLS sous rôle `nubia_app`), puis NUB-T2 (auth/RBAC).
4. Re-câbler la CI du `api/` côté **Forgejo** (l'ancienne `.github/workflows/ci.yml` a été perdue au reset — à recréer en `.forgejo/`).

## Décisions / notes importantes
- **Stack** : NestJS modular monolith (TS strict) + Prisma (+ `pg` pour RLS) · **Flutter partout** (patient + back-office), state management **Bloc (flutter_bloc)** + Dio · PostgreSQL 16 + Redis (BullMQ) + Object Storage · SSE + FCM.
- **RLS** : `TenancyService.withTenant(cabinetId, tx => …)` → transaction + `set_config('app.current_cabinet_id',$1,true)` (paramétré). Policies en `current_setting(...,true)` → fail-closed. ⚠️ effective seulement sous rôle Postgres **non-superuser** (`nubia_app`).
- **Drivers interchangeables par env** (POC↔prod) : Storage (MinIO/Scaleway), Mail (Mailpit/Brevo), SMS (log/OctoPush), Signature (Yousign sandbox/prod), KMS (local/Scaleway), Analytics (noop/PostHog).
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
