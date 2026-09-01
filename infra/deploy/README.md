# Déploiement de test — LXC Alpine (192.168.1.100)

Stack Nubia complète déployée à **chaque merge sur `main`** sur un LXC Alpine x86_64,
pour tester (PAS de production : auth `trust` Postgres, secrets en dur, données fictives).

## Topologie (réseau host, podman)

| Conteneur      | Port LXC | Contenu                                              |
|----------------|----------|------------------------------------------------------|
| `nubia-pg`     | 5432 (127.0.0.1) | PostgreSQL 16 + PostGIS                       |
| `nubia-api`    | 3000     | API Rust/Axum (binaire musl statique amd64)          |
| `nubia-console`| 4321     | Back-office Astro (SSR node)                          |
| `nubia-web`    | 8081/8082/8083/8084/8085 | nginx servant les 5 bundles Flutter web |

Fronts : `8081` patient · `8082` praticien · `8083` secrétariat · `8084` pharmacie · `8085` infirmière.
Le **Caddy de l'hôte** (hors LXC) ajoute domaine + TLS → `infra/deploy/Caddyfile.snippet`.

## Pourquoi ce montage

- Runner CI **arm64** (Mac) → cible **amd64** : `rustc` segfault sous QEMU/libkrun.
  Donc l'API est **cross-compilée** (musl statique, `cargo-zigbuild`, sans QEMU) puis
  copiée dans une image `FROM alpine` (build COPY-only, aucun code amd64 exécuté).
- L'image console (Astro/node) est construite **sur le LXC** (amd64 natif, rapide).
- Les 5 apps Flutter sont buildées en **web** (statique). Le cache Drift utilise
  sqlite3 **WASM** sur web (`sqlite3.wasm` embarqué) via import conditionnel —
  `dart:ffi` reste cantonné au natif (cf. `packages/nubia_data/lib/src/cache/executor/`).

## Déploiement manuel (depuis le repo, machine de build)

```bash
DEPLOY_PASSWORD=jipsjips bash infra/deploy/build-and-deploy.sh
```

Variables : `DEPLOY_HOST` (192.168.1.100) · `DEPLOY_USER` (root) · `DEPLOY_PASSWORD` ·
`API_BASE` (défaut `http://<host>:3000` ; mettre l'URL publique si tu passes par un domaine) ·
`YOUSIGN_API_KEY` (optionnelle — sans elle, `POST /v1/quotes/:id/signature` répond
`502 upstream_unavailable`, cf. #5688 ; `/v1/quotes/:id/sign`, le chemin utilisé par
`app_patient`, n'en dépend pas).

Variables optionnelles `CADDY_HOST` / `CADDY_USER` (défaut `root`) / `CADDY_PASSWORD` /
`CADDY_SSH_PORT` (défaut `22`) / `CADDY_CONFIG_PATH` (défaut `/etc/caddy/Caddyfile`) :
si `CADDY_HOST` est renseigné, le bloc Caddy `reservation.doc.nubia-link.com` (cf.
`Caddyfile.snippet`) est poussé et rechargé automatiquement sur l'hôte Caddy en fin de
déploiement (`apply-reservation-caddy.sh`, #6162). Sans `CADDY_HOST`, cette étape est
sautée (no-op) — le collage manuel du snippet complet reste alors nécessaire, cf.
section suivante.

## Déploiement automatique (CI)

`.forgejo/workflows/deploy.yml` (`on: push` → `main`) lance le même script.
Pré-requis une fois :
1. Construire l'image de job : `./ci/deploy/load-into-runner.sh` (dépend de `flutter-ci:stable`).
2. Renseigner les secrets Forgejo : `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PASSWORD`
   (option : variable `NUBIA_API_BASE`, secret optionnel `YOUSIGN_API_KEY`).
   Secrets optionnels `CADDY_HOST` / `CADDY_USER` / `CADDY_PASSWORD` (#6162) :
   sans eux, l'application auto du bloc Caddy `reservation.doc.nubia-link.com`
   est sautée et le collage manuel reste requis (cf. section précédente).

## Fichiers

| Fichier                         | Rôle                                                 |
|---------------------------------|------------------------------------------------------|
| `build-and-deploy.sh`           | Orchestrateur (build local + push + deploy distant)  |
| `provision.sh`                  | Installe podman + arbo `/opt/nubia` sur le LXC       |
| `deploy.sh`                     | Sur le LXC : build console, run pg/api/console/web   |
| `bootstrap-db.sh`               | Rôle owner + base `nubia` + postgis (super-user)     |
| `migrate.sh`                    | Applique `db/migrations/*.sql` (idempotent)          |
| `seed.sh`                       | Seed démo (idempotent, best-effort)                  |
| `api.Dockerfile`                | Image API COPY-only (binaire musl)                   |
| `nginx.conf`                    | Sert les 5 bundles Flutter (8081→8085)               |
| `Caddyfile.snippet`             | Bloc à coller dans le Caddy de l'hôte                |
| `apply-reservation-caddy.sh`    | Application auto (opt-in via `CADDY_HOST`) du bloc `reservation.doc.nubia-link.com` sur l'hôte Caddy (#6162) |
| `verify-public-tls.sh`          | Health-check TLS post-deploy des domaines publics (best-effort, cf. récidive #6116/#6139/#6160/#6162) |

## Comptes démo (seed)

- patient : `marc.dubois@patient.test` / `Nubia2026!`
- praticien : `hugo.marin@cabinet-lyon.test` / `Nubia2026!`
- secrétaire : `sonia.accueil@cabinet-lyon.test` / `Nubia2026!`
- pharmacien : `jean.officine@pharmacie-lyon.test` / `Nubia2026!` (login 2 étapes : `/auth/select-pharmacy-context`)
- infirmière : `infirmier.demo@nubia.test` / `Nubia2026!` (token `kind='pro'` → contexte infirmier)
