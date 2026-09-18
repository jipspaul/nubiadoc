# Nubia API

Backend **Rust / Axum** (modular monolith, workspace de crates) — multi-tenant par **Row-Level Security** PostgreSQL.
Scaffold des briques **T0/T1** (cf. `../docs/08`, `../docs/09`). Runtime conteneurs : **Podman** (cf. `../docs/10`).
Ce dossier est **vierge** (hors ce README) : le workspace Cargo décrit ci-dessous est **à créer**.

## Démarrage local
```bash
cd api
# Crée un .env (DATABASE_URL runtime = nubia_app ; URL owner séparée pour les migrations)

# DB + Redis + MinIO + Mailpit en local via Podman (depuis la racine du repo) :
podman-compose -f ../infra/poc/compose.yml up -d postgres redis minio mailpit

# Applique le schéma + la RLS — migrations gérées dans ../db/ (source unique) :
cargo install sqlx-cli --no-default-features --features postgres   # une fois
sqlx migrate run --source ../db/migrations                         # avec l'URL owner (nubia_owner)

export KMS_MASTER_KEY="$(head -c 32 /dev/urandom | base64)"   # une fois, à conserver (voir encadré ci-dessous)
cargo run --bin nubia-api     # API sur http://localhost:3000  (GET /health)
# Worker (même binaire/workspace, autre mode) :
APP_MODE=worker cargo run --bin nubia-api
```

> 🔑 `KMS_MASTER_KEY` (32 octets en base64, `head -c 32 /dev/urandom | base64`) est **obligatoire au démarrage** (#6980) :
> elle chiffre le secret TOTP à l'activation de la MFA pro, les fichiers de reprise et l'INS. Sans clé valide, `nubia-api`
> refuse de démarrer avec un message explicite (jamais de fallback en clair). `KMS_KEY_VERSION` (défaut `v1`) étiquette la
> clé dans `key_ref` — à incrémenter lors d'une rotation. Ne jamais changer la clé sans ré-enrôler : les secrets déjà
> chiffrés deviendraient illisibles. Résolution partagée : `src/kms_env.rs`.

> ⚠️ Pour que la RLS s'applique vraiment, **le runtime** se connecte avec le rôle **NON-superuser** `nubia_app`
> (`NOBYPASSRLS`), pas `postgres` ni l'owner. Les **migrations** s'appliquent avec `nubia_owner`. Voir `../db/README.md` §3
> et la CI Forgejo (`.forgejo/workflows/`) qui crée ces rôles.

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
tests/
└── rls_isolation.rs             # ⭐ test sécurité : aucune fuite inter-cabinet
```
> Les **migrations SQL** ne vivent pas ici : elles sont dans **`../db/migrations/`** (source unique, cf. `../db/README.md`). L'API les applique via `sqlx migrate run --source ../db/migrations`.

## Conventions clés
- **Toute** lecture/écriture tenant passe par `with_tenant(cabinet_id, |tx| ...)` → `SET LOCAL app.current_cabinet_id`.
- Le `cabinet_id` vient du **JWT**, jamais du corps de requête.
- Sur une connexion **WebSocket** longue durée, réinjecter le contexte tenant à chaque opération DB (pas qu'à l'ouverture).
- `STORAGE_DRIVER` (et les futurs `MAIL_DRIVER`, `KMS_DRIVER`, …) basculent POC↔prod **par config**.
- Pas de log de PII : logger structuré `tracing` avec scrubbing (à venir, NUB-T3.3).

Prochaines briques : T2 (auth/RBAC), T3 (crypto/audit), T4 (files). Détail dans `../docs/09`.
