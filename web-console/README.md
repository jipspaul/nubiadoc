# Nubia Web Console

Back-office Astro (SSG + SSR) pour la plateforme Nubia — gestion cabinets, patients, agenda, facturation.

---

## 1. Quick start

**Option A — Stack complète depuis la racine du repo :**

```bash
./scripts/dev-stack.sh
```

Lance Postgres (Podman), applique les migrations, démarre l'API Rust sur `:38030` et la web-console sur `:38040`.

**Option B — Web-console seule (si l'API tourne déjà) :**

```bash
cd web-console
npm install
npm run dev
```

La console est accessible sur <http://localhost:38040>.

---

## 2. URLs & comptes démo

| Rôle       | URL                                     | Email                          | Mot de passe |
|------------|-----------------------------------------|--------------------------------|--------------|
| Patient    | http://localhost:38040/patient/accueil  | patient.demo@nubia.test        | NubiaDemo1!  |
| Praticien  | http://localhost:38040/praticien/dashboard | praticien.demo@nubia.test   | NubiaDemo1!  |
| Secrétaire | http://localhost:38040/secretary/dashboard | secretaire.demo@nubia.test  | NubiaDemo1!  |

> Ports canon : API `:38030`, web-console `:38040` (anti-collision intentionnelle).

---

## 3. Rôles & accès

| Rôle          | Routes accessibles                        | Cookie(s) requis                          | Middleware             |
|---------------|-------------------------------------------|-------------------------------------------|------------------------|
| `patient`     | `/patient/*`                              | `nubia_jwt`, `nubia_role=patient`         | vérification de rôle   |
| `practitioner`| `/praticien/*`                            | `nubia_jwt`, `nubia_role=practitioner`    | vérification de rôle   |
| `secretary`   | `/secretary/*`                            | `nubia_jwt`, `nubia_role=secretary`, `nubia_ctx` (doit contenir un secretariatId) | vérification de rôle + contexte |
| `admin`       | `/praticien/*`, `/admin/*`                | `nubia_jwt`, `nubia_role=admin`           | vérification de rôle   |
| `manager`     | (pas de routes dédiées — accès via API)   | `nubia_jwt`, `nubia_role=manager`         | —                      |

**Flux middleware** (`src/middleware.ts`) :
- Route protégée sans `nubia_jwt` → redirect vers `/auth/login?next=<url>`.
- Rôle non autorisé sur le préfixe → redirect vers `/auth/login?next=<url>`.
- Route `/secretary/*` sans `nubia_ctx` valide → redirect vers `/auth/select-context?next=<url>`.
- `/app` → redirect vers la page d'accueil du rôle (`ROLE_HOME`).

---

## 4. Structure

```
src/pages/
├── index.astro                  # Redirect racine
├── auth/
│   ├── login.astro
│   ├── register.astro
│   ├── me.astro
│   ├── mfa-verify.astro
│   ├── select-context.astro
│   ├── password/
│   └── pro/
├── patient/
│   ├── accueil.astro
│   ├── rdv/
│   ├── soins/
│   ├── documents/
│   ├── messages/
│   ├── profil/
│   └── devis/
├── praticien/
│   ├── dashboard.astro
│   ├── agenda.astro
│   ├── file.astro
│   ├── profil-public.astro
│   ├── secretariats.astro
│   ├── patients/
│   ├── consultation/
│   └── ordonnances/
├── secretary/
│   ├── dashboard.astro
│   ├── agenda.astro
│   ├── liste-attente.astro
│   ├── cabinet/
│   ├── equipe/
│   ├── facturation/
│   ├── messagerie/
│   └── patients/
├── admin/
│   └── secretariats/
├── search/
│   ├── index.astro
│   ├── providers.astro
│   └── providers/
└── webhooks/

tests/
├── e2e/          # ~157 specs Playwright (couverture API endpoint par endpoint)
└── flows/        # ~23 flows E2E scénarisés (ED*, EP*, ES*, EX*)

src/components/kit/
├── Badge.astro
├── Button.astro
├── Card.astro
├── EmptyState.astro
├── Field.astro
├── Modal.astro
├── Spinner.astro
├── Table.astro
├── Tabs.astro
└── Toast.astro
```

---

## 5. Build & test

```bash
# Build de production
npm run build

# Vérification TypeScript sans émission
npx tsc --noEmit

# Tous les tests E2E (projet par défaut)
npx playwright test

# Flows scénarisés uniquement
npx playwright test --project=flows
```

> Les tests E2E nécessitent que l'API tourne sur `:38030` (ou `API_BASE` configuré).

---

## 6. Variables d'environnement

| Variable          | Obligatoire | Défaut                       | Description                                  |
|-------------------|-------------|------------------------------|----------------------------------------------|
| `PUBLIC_API_BASE` | non         | `http://localhost:38030`     | Base URL de l'API (exposée côté client)      |
| `API_BASE`        | non         | `http://localhost:38030`     | Base URL de l'API (côté serveur SSR)         |

Exemple `.env` :

```dotenv
PUBLIC_API_BASE=http://localhost:38030
API_BASE=http://localhost:38030
```

> `PUBLIC_API_BASE` est accessible dans le bundle client (`import.meta.env.PUBLIC_API_BASE`).
> `API_BASE` est réservée au code serveur (pages SSR, middleware).
