# Nubia API

Backend NestJS (modular monolith, TypeScript strict) — multi-tenant par **Row-Level Security** PostgreSQL.
Scaffold des briques **T0/T1** (cf. `../docs/08`, `../docs/09`). Runtime conteneurs : **Podman** (cf. `../docs/10`).

## Démarrage local
```bash
cd api
cp .env.example .env          # ajuste DATABASE_URL / REDIS_URL si besoin

# DB + Redis + MinIO + Mailpit en local via Podman (depuis la racine du repo) :
podman-compose -f ../infra/poc/compose.yml up -d postgres redis minio mailpit

npm install
npm run prisma:generate
# Applique le schéma + la RLS :
psql "$DATABASE_URL" -f prisma/migrations/0001_init/migration.sql

npm run start:dev             # API sur http://localhost:3000  (GET /health)
```

> ⚠️ Pour que la RLS s'applique vraiment, l'app doit se connecter avec un rôle **NON-superuser** (`nubia_app`),
> pas avec `postgres`. Voir la CI (`.github/workflows/ci.yml`) qui crée ce rôle.

## Scripts
| Commande | Effet |
|---|---|
| `npm run start:dev` | API en watch |
| `npm run lint` / `typecheck` | qualité (zéro warning) |
| `npm test` / `test:cov` | tests unitaires + couverture (seuils bloquants) |
| `npm run test:e2e` | tests e2e (dont **isolation RLS**, DB réelle) |

## Structure
```
src/
├── main.ts                       # bootstrap + ValidationPipe + filtre d'erreurs
├── app.module.ts
├── common/http-exception.filter.ts   # format d'erreur uniforme (docs/04 §7.2)
├── health/                       # GET /health (liveness DB)
└── core/
    ├── config/env.ts             # validation env fail-fast
    ├── prisma/                   # PrismaService
    ├── tenancy/                  # ⭐ withTenant() = cœur RLS (+ tests 100%)
    └── drivers/storage/          # driver interchangeable POC(MinIO)/prod(Scaleway)
prisma/
├── schema.prisma
└── migrations/0001_init/migration.sql   # tables + RLS policies
test/
└── rls-isolation.e2e-spec.ts     # ⭐ test sécurité : aucune fuite inter-cabinet
```

## Conventions clés
- **Toute** lecture/écriture tenant passe par `TenancyService.withTenant(cabinetId, tx => ...)`.
- Le `cabinetId` vient du **JWT**, jamais du corps de requête.
- `STORAGE_DRIVER` (et les futurs `MAIL_DRIVER`, `KMS_DRIVER`, …) basculent POC↔prod **par config**.
- Pas de `console.log` (lint `no-console`) : risque PII. Logger avec scrubbing (à venir, NUB-T3.3).

Prochaines briques : T2 (auth/RBAC), T3 (crypto/audit), T4 (files). Détail dans `../docs/09`.
