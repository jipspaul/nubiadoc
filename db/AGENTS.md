# db/ — PostgreSQL (source unique du schéma)

Tu es dans la **couche données Nubia**. PostgreSQL 16 + PostGIS + pgTAP. Source unique du schéma (l'API et le seed pointent ici).

## Layout
- `migrations/NNNN_xxx.sql` — migrations forward-only, numérotation continue.
- `seed/` — données démo fictives (jamais de PII réelle).
- `tests/` — tests pgTAP (`*.sql`), exécutés par `pg_prove` sous le rôle `nubia_app`.
- `Makefile` — cibles `db-create`, `db-migrate`, `test`, `seed`, `reset`.
- `README.md` — rôles, RLS, chiffrement, rétention, audit, runbook.
- `SCHEMA.md` — vue d'ensemble du schéma (généré ou maintenu à la main).
- `PROMPT-construction-db.md` — historique des décisions data.

## Règles dures
1. **3 rôles séparés** :
   - `nubia_owner` : DDL / migrations (SUPERUSER local seulement).
   - `nubia_app` : runtime applicatif (`NOSUPERUSER`, `NOBYPASSRLS`, **FORCE RLS** activé).
   - `nubia_seed` : seed démo (read-write data, jamais DDL).
2. **RLS sur TOUTE table contenant `tenant_id`.** Policy : `USING (tenant_id = current_setting('app.current_tenant')::uuid)`.
3. **`FORCE ROW LEVEL SECURITY`** activé sur les tables sensibles → même `nubia_owner` ne contourne pas par accident en runtime.
4. **Migrations forward-only.** Une migration mergée = immuable. Si bug : nouvelle migration corrective, jamais d'édition rétroactive.
5. **`audit_log` append-only** : pas de `UPDATE` ni `DELETE` sur cette table — trigger empêche la modif.
6. **Colonnes PII chiffrées** : `<col>_encrypted bytea`, helpers `encrypt_column()`/`decrypt_column()` côté API (KMS).
7. **Tests pgTAP obligatoires** pour chaque policy RLS : un test "cross-tenant doit échouer" + "même-tenant doit passer".

## Workflow local (loop de validation)
```bash
make reset          # drop + recréation + migrations + seed
make test           # pg_prove sous nubia_app
# si rouge : fix, make test, jusqu'à vert
git add . && git commit
```

**Ne push pas tant que `make test` n'est pas vert localement.** La CI est une redondance, pas la validation primaire.

## Référence
- Modèle complet : `docs/05-donnees.md` (depuis racine repo).
- Conformité (rétention, audit, chiffrement) : `docs/07-conformite.md`.
