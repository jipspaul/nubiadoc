# api/ — backend Rust (Axum + SQLx + PostGIS)

Tu es dans le **backend Nubia**. Stack Rust + Axum + SQLx + PostgreSQL/PostGIS.

## Layout
- `Cargo.toml` — workspace racine.
- `crates/` — crates métier (un sous-dossier par bounded context).
- `src/` — binaire principal (entrypoint Axum).
- `tests/` — tests d'intégration (un fichier par feature, pas par crate).
- `README.md` — runbook local + variables d'env.

## Règles dures (non négociables)
1. **`#[forbid(unsafe_code)]` et zéro `unwrap()`/`panic!()` dans le code applicatif.** Pour les tests : OK.
2. **Tenancy RLS** : toute requête SQLx PASSE par `with_tenant(tenant_id, |conn| ...)` (set `app.current_tenant` puis exécute). JAMAIS un `pool.acquire()` brut dans un handler.
3. **Migrations forward-only** : ajouter une nouvelle `db/migrations/NNNN_xxx.sql`, jamais éditer une migration passée. La numérotation est ordonnée et committée.
4. **`sqlx::query!`/`query_as!` macros** (vérif compile-time vs `.sqlx/` checké en CI via `cargo sqlx prepare --check --workspace`).
5. **Pas d'API publique non versionnée.** Toute route monte sous `/v1/...`. Breaking change = `/v2/...`.
6. **Colonnes chiffrées** (PII patient) : `*_encrypted bytea` + helper `encrypt_column()`/`decrypt_column()` côté Rust. Jamais `String` clair stocké directement.

## Workflow tests
- Unit : dans le crate, sous `#[cfg(test)] mod tests`.
- Intégration : `tests/<feature>.rs` avec DB fixture (Postgres via `sqlx::test` ou container).
- Audit RLS : un test pgTAP côté `db/tests/` valide que la policy bloque un cross-tenant. Le test côté Rust valide juste le happy path.

## Avant de committer
- `cargo fmt`
- `cargo clippy --workspace -- -D warnings`
- `cargo sqlx prepare --check --workspace` (si tu as touché à du SQL macro)
- `cargo nextest run --workspace`

## Référence
- Routes complètes : `docs/12-reference-api.md` (depuis racine repo).
- Modèle de données : `docs/05-donnees.md`.
- Rôles DB : `db/README.md` (`nubia_app` NOSUPERUSER NOBYPASSRLS pour runtime).
