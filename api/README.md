# Nubia API

Backend **Rust / Axum** (modular monolith, workspace de crates) — multi-tenant par **Row-Level Security** PostgreSQL.
Scaffold des briques **T0/T1** (cf. `../docs/08`, `../docs/09`). Runtime conteneurs : **Podman** (cf. `../docs/10`).

> ⚠️ **Migration en cours (03/06/2026)** : l'ancien scaffold **NestJS + Prisma** est **obsolète** (décision stack Rust, cf. `../PROGRESS.md` et `../docs/04` ADR-002). Les fichiers Node/TS encore présents dans ce dossier sont à supprimer et à remplacer par le workspace Cargo décrit ci-dessous. Ce README décrit la **cible Rust**.

## Démarrage local
```bash
cd api
cp .env.example .env          # ajuste DATABASE_URL / REDIS_URL si besoin

# DB + Redis + MinIO + Mailpit en local via Podman (depuis la racine du repo) :
podman-compose -f ../infra/poc/compose.yml up -d postgres redis minio mailpit

# Applique le schéma + la RLS :
cargo install sqlx-cli --no-default-features --features postgres   # une fois
sqlx migrate run

cargo run --bin nubia-api     # API sur http://localhost:3000  (GET /health)
# Worker (même binaire/workspace, autre mode) :
APP_MODE=worker cargo run --bin nubia-api
```

> ⚠️ Pour que la RLS s'applique vraiment, l'app doit se connecter avec un rôle **NON-superuser** (`nubia_app`),
> pas avec `postgres`. Voir la CI Forgejo (`.forgejo/workflows/`) qui crée ce rôle.

## Commandes
| Commande | Effet |
|---|---|
| `cargo run --bin nubia-api` | API (watch via `cargo watch -x run`) |
| `cargo fmt --check` / `cargo clippy -- -D warnings` | qualité (zéro warning) |
| `cargo test` / `cargo llvm-cov` | tests + couverture (seuils bloquants) |
| `cargo test --test rls_isolation` | test sécurité : **isolation RLS** (DB réelle) |
| `cargo audit` / `cargo deny check` | scan des dépendances |

## Structure (cible)
```
Cargo.toml                        # workspace
crates/
├── api/                          # binaire : bootstrap Axum, router, mode api/worker
│   └── src/main.rs               # + couche d'erreur uniforme (docs/04 §7.2)
├── core/
│   ├── config/                   # validation env fail-fast (figment/serde)
│   ├── db/                       # pool SQLx
│   ├── tenancy/                  # ⭐ with_tenant() = cœur RLS (+ tests 100%)
│   ├── realtime/                 # hub WebSocket + fan-out pub/sub Redis
│   └── drivers/storage/          # driver interchangeable POC(MinIO)/prod(Scaleway)
└── modules/                      # cabinet, identity, scheduling, … (cf. docs/04 §4)
migrations/                       # sqlx migrate (SQL) : tables + RLS policies
tests/
└── rls_isolation.rs             # ⭐ test sécurité : aucune fuite inter-cabinet
```

## Conventions clés
- **Toute** lecture/écriture tenant passe par `with_tenant(cabinet_id, |tx| ...)` → `SET LOCAL app.current_cabinet_id`.
- Le `cabinet_id` vient du **JWT**, jamais du corps de requête.
- Sur une connexion **WebSocket** longue durée, réinjecter le contexte tenant à chaque opération DB (pas qu'à l'ouverture).
- `STORAGE_DRIVER` (et les futurs `MAIL_DRIVER`, `KMS_DRIVER`, …) basculent POC↔prod **par config**.
- Pas de log de PII : logger structuré `tracing` avec scrubbing (à venir, NUB-T3.3).

Prochaines briques : T2 (auth/RBAC), T3 (crypto/audit), T4 (files). Détail dans `../docs/09`.
