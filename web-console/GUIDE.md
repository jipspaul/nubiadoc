# Guide complet — Faire de la web-console la démo UX des 3 apps Nubia

> **Objectif** (reformulé) : transformer la `web-console` (aujourd'hui un banc de test d'endpoints) en une **démo UX complète et lite** couvrant les **3 publics** — **Patient**, **Praticien**, **Secrétaire** — branchée sur la **vraie API**, lançable via `./scripts/dev-stack.sh` pour valider **les flux et l'UX** (pas le polish visuel).
>
> Ce document est le **guide step-by-step**. Il est **challengé** (section 2) : l'audit a révélé un **bloqueur d'authentification backend** que le plan générique précédent ignorait. À lire de haut en bas ; chaque phase est livrable indépendamment.

---

## 0. TL;DR (décisions clés, après challenge)

1. **Bloqueur P0 (backend, prérequis absolu)** : `POST /v1/auth/login` émet pour un pro un token **sans `cabinet_id` ni `role`**. Or **tous** les endpoints `/v1/cabinet/*` décodent `cabinet_id`+`role` **depuis le JWT**. Conséquence : **un praticien/secrétaire qui se connecte ne peut accéder à AUCUN écran cabinet**. Sans correctif, "Praticien app + Secrétaire app sur vraie API" est **impossible**. → **Étape 1 du plan = corriger le login.** (détail §2.1, §4)
2. **Architecture retenue : 1 seule app Astro, 3 espaces de routes** (`/patient/*`, `/praticien/*`, `/secretary/*`) + public `/search/*` + `/auth/*`. Plus lite que 3 serveurs, partage auth/session/composants. `dev-stack.sh` **publie les 3 URLs + 3 comptes de démo**. (mode 3-ports optionnel décrit §10)
3. **Routage par rôle = lecture du JWT** : `kind` (`patient`|`pro`) puis, pour les pros, `role` (`admin`|`practitioner`|`secretary`). Le modèle existe déjà côté API. (§3.2)
4. **On consolide, on ne empile pas** : ~150 pages plates (`/test/*` + doublons `scheduling` vs `appointments`) → fusionnées dans les 3 espaces. (§7, todo `p3-cleanup`)
5. **Lite assumé** : tokens design (émeraude) en variables CSS, composants Astro minimalistes, zéro framework JS lourd, pas de pixel-perfect. Données **fictives** uniquement (règle G3).

---

## 1. Audit de l'existant (état réel, vérifié)

### 1.1 web-console (ce qui existe)
- **Stack** : Astro 6 `output: 'server'` + adapter Node standalone. TypeScript (tsconfig `strict` hérité de `astro/tsconfigs/base`). Playwright présent.
- **`src/lib/api.ts`** : ultra-minimal — `apiFetch(path, options)` → `{status, data}`. **N'injecte pas le Bearer**, pas de typage, pas de gestion 401/refresh.
- **`src/lib/session.ts`** : **client-side** (`localStorage` + cookie `nubia_jwt` non-httpOnly, `SameSite=Strict`). `getCurrentUser()` ne décode **que l'email**. **Aucune notion de rôle.**
- **`src/middleware.ts`** : ne protège que `/app/*` (présence du cookie). Pas de garde par rôle.
- **`src/layouts/`** : `Default.astro` (`/test/*`), `DefaultAuth.astro` (`/app/*`, check auth client-side + logout), `PublicLayout.astro`. Thème **sombre générique** (pas les tokens émeraude du design system).
- **`src/components/`** : un seul `NavMenu.astro` — méga-sidebar listant **toutes** les pages, groupées par module API (banc de test).
- **`src/pages/`** : **~150 pages** très plates et **redondantes** : ex. check-in existe en `/appointments/checkin`, `/scheduling/checkin-appointment`, `/test/...`. Beaucoup de pages `/test/*` (≈ 115 specs e2e en miroir).
- **Ports** : `dev-stack.sh` utilise API `:38030` / web `:38040` — **choix volontaire du dev** pour éviter les collisions avec `:3000/:4321` déjà occupés sur sa machine. Ce sont les **ports canon**. En revanche `scripts/dev.sh` + README + le défaut de `api.ts` (`:3000`) sont **restés en retard** sur l'ancien schéma → **incohérence à corriger** (les aligner sur `PUBLIC_API_BASE`, pas l'inverse).
- **`tests/e2e/`** : ~115 specs, une par page de test (logique de banc d'essai, pas des parcours).

> **Verdict** : socle Astro sain mais c'est un **banc de test**, pas un produit. Pas de rôle, pas de parcours, auth client-side faible, duplication massive, thème hors design system.

### 1.2 API backend (ce qui existe — source de vérité : `api/src/lib.rs`)
L'API Rust/Axum est **mature** (35 modules). **Surface complète réelle** (extraite de `lib.rs:161-420`) — voir **Annexe A** pour l'inventaire complet par module. Points saillants :
- **Auth** : register, login, refresh, logout, mfa enroll/verify, password forgot/reset, `GET /v1/me`.
- **Patient** : `account` (+coverage, coverage/card, notification-preferences, dependents, consents), `appointments` (+ cancel/checkin/callback-request/directions/preparation/queue), `documents` (+download), `conversations` (+messages/read), `dashboard`, `treatment-plans`, `quotes`, `payments/intent`, `notifications`, `reminders`, `devices`, `implant-passport`, `waiting-list`, `reviews`.
- **Marketplace public** : `professions`, `specialties`, `acts`, `search/suggest|providers|slots`, `providers/:id` (+reviews), `cabinets/:id/info`.
- **Pro/cabinet** : `pro/register`, `pro/verification`, `cabinet` (get/patch), `cabinet/provider` (+listing), `cabinet/members` (+`:id` patch/delete), `cabinet/patients` (+`:id`, notes, medical-record, dental-chart, documents), `cabinet/consultations/:id` (+acts, complete), `cabinet/conversations`, `cabinet/agenda`, `cabinet/waiting-room` (+call-next), `cabinet/appointments` (+confirm/start/patch), `cabinet/waiting-list` (+offer), `cabinet/slots` (+`:id`, online), `cabinet/prescriptions` (+sign).

### 1.3 Modèle de rôles (source de vérité : `api/src/auth/mod.rs`)
- **JWT** : `kind` ∈ {`patient`,`pro`}. Pour les pros : `role` ∈ {`admin`,`practitioner`,`secretary`} + `cabinet_id`.
- **Extracteurs** : `PatientAccountClaims` (→403 si non-patient), `ProAdminClaims`, `ProPractitionerClaims` (rejette `secretary`), `ProSecretaryPlusClaims` (secretary/practitioner/admin). **Tous décodent `role`/`cabinet_id` depuis le JWT.**
- **Cloisonnement** : ex. `cabinet_messaging` masque le scope `clinical` au `secretary` (secret médical R.4127-72). → la **vue Secrétaire ≠ vue Praticien** sur les mêmes écrans.
- **`GET /v1/me`** : renvoie `memberships:[{cabinet_id, role}]` **uniquement** si le token porte déjà `cabinet_id` (token `register`). Pour un token `login`, `memberships` est **vide** (commenté tel quel dans le code).
- **Table `cabinet_membership(cabinet_id, user_id, role, active)`** = la vérité que le **login devrait** consulter.

---

## 2. Challenge du plan (ce que le plan générique précédent ratait)

> Le plan v1 disait « réutiliser le login existant », « vraie API only », « 3 rôles dès J1 ». L'audit montre que **ces 3 hypothèses sont mutuellement incohérentes** en l'état. Corrections :

### 2.1 ⛔ Bloqueur #1 — Auth pro incomplète (P0)
- **Fait** : `login.rs` (branche pro) émet `ProClaims { sub, kind:"pro", exp }` — **sans `cabinet_id` ni `role`**. `pro/register` émet bien `{…, cabinet_id, role:"admin"}` mais **une seule fois**, **admin seulement**.
- **Fait** : `/v1/cabinet/*` exige `cabinet_id`+`role` **dans le JWT** (décodage strict → sinon 401).
- **Conséquences** :
  1. Après **login**, un pro **ne peut atteindre aucun** `/v1/cabinet/*`.
  2. Il **n'existe aucun chemin** pour obtenir un token **`practitioner`** ou **`secretary`** (ces rôles sont créés via `cabinet/members` mais aucun login ne ré-émet leur `role`+`cabinet_id`).
- **Décision** : **corriger `POST /v1/auth/login`** pour, si `kind=pro`, lire `cabinet_membership` (active) par `user_id`, choisir la membership (si plusieurs : la 1ʳᵉ ou un cabinet par défaut), et **embarquer `cabinet_id`+`role`** dans le JWT (comme `pro/register`). Idem **`refresh.rs`** (même logique, sinon le rôle saute au refresh). → **Étape 1** (§4).
- **Repli si on ne touche pas au backend** (déconseillé) : la démo pro se limiterait à l'**admin fraîchement enregistré** et perdrait l'accès au refresh — incompatible avec "tester tout". Donc **le correctif backend est non-négociable**.

### 2.2 Autres risques tranchés
- **Ports non standards = intentionnels** (`:38030` API / `:38040` web) pour éviter les collisions avec `:3000/:4321` déjà pris sur la machine → **on garde ces ports comme canon, on ne revient pas à 3000/4321**. Le seul vrai problème : `scripts/dev.sh`, le README et le défaut de `api.ts` (`:3000`) sont restés sur l'ancien schéma → **les aligner** sur `PUBLIC_API_BASE` (défaut `:38030`). (§9)
- **Session client-side faible** : `localStorage` + cookie non-httpOnly. Pour une **démo lite c'est acceptable**, mais (a) le **middleware doit pouvoir décider par rôle** → il faut le `kind`/`role` côté serveur. Option lite : après login, poser un cookie **lisible** `nubia_role` (non sensible) en plus du JWT, pour le routage middleware ; le JWT reste la source d'autorité côté API. (§3.3)
- **Duplication massive** : ne pas ajouter de pages par-dessus → **consolider** (§7).
- **MFA** : `login` peut renvoyer `401 mfa_required` (pros TOTP) → le **flux login doit gérer l'étape code**. (§3.3)
- **Scope clinique/secrétaire** : mêmes URLs, **données filtrées par rôle** → prévoir des composants qui masquent le clinique pour `secretary`. (§6.3)
- **Temps réel** (salle d'attente live WebSocket) : **hors lite** → polling simple (refetch toutes N s) pour la démo. (§6.2)

---

## 3. Architecture cible (lite)

### 3.1 Une app, des espaces par rôle
```
src/pages/
  index.astro              → splash : "Se connecter" + entrée annuaire public
  auth/                    → login, register (patient), pro/register, mfa, password/*
  search/                  → annuaire PUBLIC (sans compte) : recherche, résultats, profil praticien
  patient/                 → ESPACE PATIENT (kind=patient)
  praticien/               → ESPACE PRATICIEN (kind=pro, role in {practitioner,admin})
  secretary/               → ESPACE SECRÉTAIRE (kind=pro, role in {secretary,admin})
```
> "Publier les 3 apps" = **3 URLs** servies par le même serveur : `/patient`, `/praticien`, `/secretary`. `dev-stack` les imprime + les 3 comptes de démo. (mode 3-ports optionnel §10.3)

### 3.2 Routage par rôle (déduit du JWT)
| Espace | Condition d'accès (claims) | Home |
|---|---|---|
| `/patient/*`   | `kind == "patient"` | `/patient/accueil` |
| `/praticien/*` | `kind == "pro" && role ∈ {practitioner, admin}` | `/praticien/dashboard` |
| `/secretary/*` | `kind == "pro" && role ∈ {secretary, admin}` | `/secretary/dashboard` |
| `/search/*`, `/auth/*` | public | — |

Après login : appeler **`GET /v1/me`** (post-correctif il renverra la/les membership(s)) **ou** lire `role` du JWT corrigé → rediriger vers la home du rôle. `admin` voit praticien **et** secrétaire (sélecteur d'espace dans le header).

### 3.3 Auth & session (lite, mais role-aware)
- **login.astro** (client) : POST `/v1/auth/login` → si `200` stocke `access_token`+`refresh_token` ; si `401 mfa_required` affiche le champ code et renvoie avec `mfa_code`.
- **`session.ts`** (à étendre) : décoder le JWT → exposer `{ email, kind, role, account_id, cabinet_id, exp }`. Poser un cookie **non-sensible** `nubia_role` (`patient|practitioner|secretary|admin`) pour le middleware.
- **`middleware.ts`** (à étendre) : pour chaque espace, vérifier présence du JWT **et** que `nubia_role` est autorisé pour le préfixe ; sinon `redirect('/auth/login?next=…')` ou `/403`.
- **`api.ts`** (à étendre) : `apiFetch` injecte `Authorization: Bearer <access_token>` ; sur `401` tente **un** refresh (`/v1/auth/refresh`) puis rejoue ; échec → purge session + redirect login. Conserver le retour `{status,data}`.

### 3.4 Design lite
- Importer les **tokens** de `design/03-design-system/` (couleurs émeraude, typo Inter/Fraunces, arrondis) dans un `src/styles/tokens.css` global, remplacer le thème sombre générique. **Pas** de refonte visuelle : juste cohérence + lisibilité.
- **Kit composants** Astro minimal : `Button`, `Field` (label+input+erreur), `Card`, `Table`, `Modal`, `Tabs`, `Toast`, `Badge`, `EmptyState`, `Spinner`, `AppShell` (header + nav + slot). Tout en `.astro`, hydratation `client:*` seulement si nécessaire (formulaires).

---

## 4. PHASE 1 — Débloquer l'auth pro (P0, backend) `todo: p0-auth-login-fix`
> Fichiers : `api/src/auth/login.rs`, `api/src/auth/refresh.rs` (+ `mod.rs` si nouveau claim). Respecter `api/AGENTS.md` (RLS, `query!` macros, `cargo sqlx prepare`, fmt/clippy/nextest).

1. Dans `login.rs`, branche `else` (pro) : avant d'encoder, ouvrir une tx, `set_config('app.current_user_id', sub)` puis lire :
   ```sql
   SELECT cabinet_id, role FROM cabinet_membership
   WHERE user_id = $1 AND active = true
   ORDER BY created_at ASC LIMIT 1;
   ```
   - **0 ligne** → pro sans cabinet : émettre token `kind:"pro"` sans cabinet (comportement actuel) **ou** `403 no_active_membership` (selon UX voulue ; pour la démo, garder le token "nu" et laisser le front afficher "aucun cabinet").
   - **≥1 ligne** → encoder un claim `{ sub, kind:"pro", cabinet_id, role, exp }` (réutiliser la struct de `pro/register`).
2. Idem dans `refresh.rs` (re-résoudre la membership pour ne pas perdre `role`/`cabinet_id`).
3. **Multi-cabinet** (post-démo) : si un pro appartient à plusieurs cabinets, prévoir `POST /v1/auth/select-cabinet` ré-émettant un token ciblé. **Hors lite** : LIMIT 1 suffit pour la démo.
4. **Tests** : ajouter `api/tests/auth_login_pro.rs` — login practitioner → token porte `role:"practitioner"`+`cabinet_id` → `GET /v1/cabinet/agenda` = 200 ; login secretary → 200 sur agenda, mais conversation `scope=clinical` filtrée.
5. **DoD** : `cargo fmt --check`, `cargo clippy -D warnings`, `cargo sqlx prepare --check`, `cargo nextest run` verts ; un token issu de **login** accède aux endpoints cabinet selon son rôle.

---

## 5. PHASE 2 — Comptes de démo + seed `todo: p0-seed-accounts`
1. Vérifier/compléter le **seed** `db/` : au moins **4 comptes** activables via `/v1/auth/login` :
   - `patient.demo@nubia.test` (kind patient, avec RDV/docs/devis fictifs)
   - `praticien.demo@nubia.test` (membership role `practitioner`)
   - `secretaire.demo@nubia.test` (membership role `secretary`)
   - `admin.demo@nubia.test` (role `admin`) — optionnel mais pratique
   Tous rattachés au **même cabinet fictif** avec agenda, patients, créneaux, conversations.
2. Documenter les **identifiants** (mot de passe commun de démo) dans le futur `web-console/README.md` et les **imprimer** par `dev-stack.sh`.
3. **DoD** : pour chacun, `login` → `GET /v1/me` cohérent + au moins 1 endpoint clé de son espace en 200.

---

## 6. PHASE 3 — Foundations front `todo: p1-foundation-kit`, `p1-routing-login`

### 6.1 Kit & infra (`p1-foundation-kit`)
- `src/styles/tokens.css` (tokens design system) importé globalement.
- `src/lib/session.ts` étendu (décodage `kind`/`role`/`account_id`/`cabinet_id`, cookie `nubia_role`).
- `src/lib/api.ts` étendu (Bearer + refresh-on-401). Ajouter `src/lib/endpoints.ts` : **client typé** (fonctions par route, regroupées par domaine) basé sur **Annexe A** + contrats `docs/12-api-reference.md`.
- `src/middleware.ts` étendu (garde par préfixe/rôle).
- `src/components/kit/*` : composants listés §3.4. `src/layouts/AppShell.astro` paramétré par rôle (nav différente).

### 6.2 Login + routage (`p1-routing-login`)
- `auth/login.astro` (gère MFA), `auth/register.astro` (patient), `auth/pro/register.astro` (cabinet + RPPS), `auth/password/forgot|reset`, `auth/mfa-verify`.
- Post-login : redirection par rôle (§3.2). Header avec **sélecteur d'espace** si `admin`.
- **Temps réel** : helper `poll(fn, ms)` (refetch) pour salle d'attente/notifs — **pas** de WebSocket en lite.

---

## 7. PHASE 4 — Les 3 espaces (cœur) 

> Chaque écran ci-dessous liste **route(s) API réelles** (Annexe A) et le **rôle**. Construire par parcours, pas par endpoint. Réutiliser le kit. Mapping design : `design/02-inventaire-ecrans.md` + `design/ia-navigation.md`.

### 7.1 ESPACE PATIENT `todo: p2-patient-app` (nav 5 onglets, cf. `ia-navigation.md`)
**Onglet Accueil / Rechercher**
- `patient/accueil.astro` — dashboard agrégé : `GET /v1/dashboard` (prochain RDV, à signer, à régler, messages non lus) + barre de recherche.
- `search/*` (public, réutilisé) — `GET /v1/search/suggest|providers|slots`, `GET /v1/providers/:id` (+`/reviews`), `GET /v1/cabinets/:id/info`, `GET /v1/professions|specialties|acts`.

**Onglet Mes RDV**
- `patient/rdv/index.astro` — `GET /v1/appointments?status=upcoming|past`.
- `patient/rdv/[id].astro` — `GET /v1/appointments/:id` ; actions : `PATCH`, `POST …/cancel`, `POST …/checkin`, `POST …/callback-request`.
- `patient/rdv/[id]/preparation.astro` — `GET …/preparation` + `…/directions`.
- `patient/rdv/[id]/salle-attente.astro` — `GET …/queue` (polling).
- `patient/rdv/reserver.astro` — depuis search/slots → `POST /v1/appointments`.

**Onglet Messages**
- `patient/messages/index.astro` — `GET /v1/conversations` ; `patient/messages/[id].astro` — `GET/POST …/messages`, `POST …/read`, création `POST /v1/conversations`.

**Onglet Documents** (coffre + finances + soins)
- `patient/documents/index.astro` — `GET /v1/documents` ; `[id].astro` — `GET /v1/documents/:id` + `…/download`.
- `patient/devis/index.astro` — `GET /v1/quotes` ; signature (parcours Yousign stub) ; acompte `POST /v1/payments/intent`.
- `patient/soins/plan.astro` — `GET /v1/treatment-plans` (+`/:id`) ; `patient/soins/passeport.astro` — `GET /v1/implant-passport` (+`/export`).

**Onglet Profil**
- `patient/profil/index.astro` — `GET/PATCH /v1/account`.
- `patient/profil/couverture.astro` — `GET/PATCH /v1/account/coverage`, `POST …/coverage/card`.
- `patient/profil/proches.astro` — `GET/POST /v1/account/dependents`, `GET/PATCH/DELETE …/:id`.
- `patient/profil/consentements.astro` — `GET /v1/account/consents`, `PUT …/:purpose`.
- `patient/profil/notifications.astro` — `GET/PATCH /v1/account/notification-preferences` ; centre : `GET /v1/notifications`, `GET /v1/reminders`.

### 7.2 ESPACE PRATICIEN `todo: p2-praticien-app` (sidebar)
- `praticien/dashboard.astro` — journée clinique : `GET /v1/cabinet/agenda`, `GET /v1/cabinet/appointments`, patient suivant via `GET /v1/cabinet/waiting-room`.
- `praticien/agenda.astro` — `GET /v1/cabinet/agenda` ; créneaux : `POST /v1/cabinet/slots`, `PATCH/DELETE …/:id`, `PUT …/:id/online`.
- `praticien/file.astro` — salle d'attente live : `GET /v1/cabinet/waiting-room` (polling) ; `POST …/call-next`.
- `praticien/patients/index.astro` — `GET /v1/cabinet/patients` ; `[id].astro` — `GET …/:id`, notes `GET/POST …/notes`, `GET/PATCH …/medical-record`, `GET/PUT …/dental-chart`, docs `GET/POST …/documents`.
- `praticien/consultation/[id].astro` — fauteuil : `GET /v1/cabinet/consultations/:id`, `POST …/acts`, `POST …/complete` ; démarrage via `POST /v1/cabinet/appointments/:id/start`.
- `praticien/ordonnances/new.astro` + `[id]/sign.astro` — `POST /v1/cabinet/prescriptions`, `POST …/:id/sign`. ⚠️ **display-only**, aucun moteur d'interaction (hors MDR).
- `praticien/profil-public.astro` — `PATCH /v1/cabinet/provider`, `PUT …/provider/listing` ; vérif `GET/POST /v1/pro/verification`.

### 7.3 ESPACE SECRÉTAIRE `todo: p2-secretary-app` (sidebar, **scope clinique masqué**)
- `secretary/dashboard.astro` — opérationnel : `GET /v1/cabinet/appointments`, `GET /v1/cabinet/agenda`, file `GET /v1/cabinet/waiting-room`.
- `secretary/agenda.astro` — `GET /v1/cabinet/agenda` ; gestion RDV : `POST /v1/appointments` (au nom du patient) ou `POST /v1/cabinet/appointments/:id/confirm`, `PATCH /v1/cabinet/appointments/:id` ; créneaux comme praticien.
- `secretary/liste-attente.astro` — `GET /v1/cabinet/waiting-list`, `POST …/:id/offer` (🎭 démo).
- `secretary/patients/index.astro` — `GET /v1/cabinet/patients` (vue **admin** : pas le clinique), `[id]` : identité, couverture, docs administratifs.
- `secretary/equipe.astro` — `GET/POST /v1/cabinet/members`, `PATCH/DELETE …/:user_id`.
- `secretary/cabinet.astro` — `GET/PATCH /v1/cabinet`, `GET /v1/cabinets/:id/info`.
- `secretary/facturation.astro` — `GET /v1/quotes` (vue cabinet), suivi paiements.
- `secretary/messagerie.astro` — `GET /v1/cabinet/conversations` (**scope clinique filtré côté API** pour secretary — afficher uniquement non-clinique).

---

## 8. PHASE 5 — Consolidation & nettoyage `todo: p3-cleanup`
- Fusionner les doublons : `appointments/*`, `scheduling/*`, `cabinet/*`, `clinical/*`, `account/*`, `app/*`, `me/*` → vers les 3 espaces.
- `/test/*` : **option A** supprimer ; **option B** garder un `/test/index` minimal "dev only" derrière un flag. Recommandé : **A** (la vraie démo remplace le banc).
- Remplacer le méga-`NavMenu.astro` par **3 navs de rôle** (dans `AppShell`).
- Mettre à jour les ~115 specs e2e (beaucoup deviendront caduques → voir Phase 7).

---

## 9. PHASE 6 — dev-stack publie les 3 apps `todo: p3-devstack-seed`
- `scripts/dev-stack.sh` : après démarrage web, **imprimer** :
  ```
  Patient    → http://localhost:38040/patient    (patient.demo@nubia.test)
  Praticien  → http://localhost:38040/praticien   (praticien.demo@nubia.test)
  Secrétaire → http://localhost:38040/secretary   (secretaire.demo@nubia.test)
  Mot de passe démo : <…>
  ```
- Vérifier que `PUBLIC_API_BASE=http://localhost:38030` est bien injecté (déjà le cas). Les ports **`:38030`/`:38040` sont le canon volontaire** (anti-collision sur cette machine) — **ne pas** revenir à `:3000/:4321`. Aligner uniquement `scripts/dev.sh` + `README` + le **défaut de `api.ts`** sur ce schéma (idéalement : `api.ts` défaut `:38030`, et/ou échec explicite si `PUBLIC_API_BASE` absent).
- **Optionnel (mode 3-ports)** : variables `WEB_PORT_PATIENT/PRO/SECRETARY` lançant 3 `astro preview` — **non nécessaire** en lite (1 serveur, 3 chemins suffit). Documenter mais ne pas implémenter par défaut.

---

## 10. PHASE 7 — Tests E2E `todo: p3-tests`
Parcours "happy path" par rôle (Playwright, vraie API via dev-stack + seed) :
- **Patient** : login → `accueil` (dashboard chargé) → réserver un créneau → voir le RDV → check-in.
- **Praticien** : login → dashboard → ouvrir RDV → `start` → ajouter un acte → `complete` → créer + signer une ordonnance.
- **Secrétaire** : login → créer un RDV → inviter un membre → voir facturation. Vérifier **403** sur une route praticien-only (cloisonnement).
- **Cross-rôle** : patient réserve → praticien le voit dans l'agenda → secrétaire le confirme.
- Config Playwright : `baseURL` = web (38040), `webServer` optionnel ; comptes seed.

---

## 11. PHASE 8 — Docs `todo: p3-docs`
- `web-console/README.md` : rôles, URLs, identifiants démo, run (`./scripts/dev-stack.sh`), troubleshooting.
- `web-console/ARCHITECTURE.md` : espaces/rôles, flux auth (schéma), kit composants, **matrice de couverture** écran↔endpoint↔rôle, points lite assumés (polling, session client-side).

---

## 12. Ordre d'exécution & jalons
```
P0  Étape 1  Backend login/refresh (cabinet_id+role)      [bloqueur]   p0-auth-login-fix
P0  Étape 2  Seed 3-4 comptes + creds                                  p0-seed-accounts
P1  Étape 3  Foundations (kit, session, api, middleware)               p1-foundation-kit
P1  Étape 4  Login + routage rôle                                      p1-routing-login
P2  Étape 5  Espace Patient                                            p2-patient-app
P2  Étape 6  Espace Praticien                                          p2-praticien-app
P2  Étape 7  Espace Secrétaire                                         p2-secretary-app
P3  Étape 8  Consolidation/nettoyage                                   p3-cleanup
P3  Étape 9  dev-stack 3 URLs + creds                                  p3-devstack-seed
P3  Étape 10 Tests E2E par rôle                                        p3-tests
P3  Étape 11 README + ARCHITECTURE                                     p3-docs
```
**Jalon démo** = fin Étape 9 : les 3 espaces se connectent et déroulent leurs parcours sur la vraie API. Étapes 10-11 = qualité.

## 13. Definition of Done (global)
- [ ] Un **praticien** et un **secrétaire** issus de **login** accèdent à leurs endpoints cabinet (P0 résolu).
- [ ] 3 espaces navigables avec nav propre, brancés vraie API, données seed fictives.
- [ ] Parcours critiques OK : réserver/check-in (patient), consultation+ordonnance (praticien), créer RDV+inviter membre (secrétaire).
- [ ] Cloisonnement vérifié : secrétaire bloqué sur clinique (403 + UI masquée).
- [ ] `./scripts/dev-stack.sh` imprime les 3 URLs + creds ; tout démarre d'une commande.
- [ ] `npm run build` + `npx tsc --noEmit` + Playgright happy-paths verts.
- [ ] Doublons `/test` & legacy supprimés ou clairement isolés.

---

## Annexe A — Inventaire complet des routes API (source `api/src/lib.rs`)
**Auth/compte** : `POST /v1/auth/register|login|refresh|logout`, `POST /v1/auth/mfa/enroll|verify`, `POST /v1/auth/password/forgot|reset`, `GET /v1/me`.
**Patient – compte** : `GET|PATCH /v1/account`, `GET|PATCH /v1/account/coverage`, `POST /v1/account/coverage/card`, `GET|PATCH /v1/account/notification-preferences`, `GET|POST /v1/account/dependents`, `GET|PATCH|DELETE /v1/account/dependents/:id`, `GET /v1/account/consents`, `PUT /v1/account/consents/:purpose`.
**Patient – RDV** : `GET|POST /v1/appointments`, `GET|PATCH /v1/appointments/:id`, `POST /v1/appointments/:id/cancel|checkin|callback-request`, `GET /v1/appointments/:id/directions|preparation|queue`.
**Patient – docs/msg/finances/soins** : `GET|POST /v1/documents`, `GET /v1/documents/:id`, `GET /v1/documents/:id/download`, `GET|POST /v1/conversations`, `GET|POST /v1/conversations/:id/messages`, `POST /v1/conversations/:id/read`, `GET /v1/dashboard`, `GET /v1/treatment-plans` (+`/:id`), `GET /v1/quotes`, `POST /v1/payments/intent`, `GET /v1/notifications`, `GET /v1/reminders`, `POST /v1/devices`, `GET /v1/implant-passport` (+`/export`), `POST /v1/waiting-list`.
**Marketplace public** : `GET /v1/professions|specialties|acts`, `GET /v1/search/suggest|providers|slots`, `GET /v1/providers/:id`, `GET /v1/providers/:id/reviews`, `POST /v1/reviews`, `GET /v1/cabinets/:id/info`.
**Pro – onboarding/cabinet** : `POST /v1/pro/register`, `GET|POST /v1/pro/verification`, `GET|PATCH /v1/cabinet`, `PATCH /v1/cabinet/provider`, `PUT /v1/cabinet/provider/listing`, `GET|POST /v1/cabinet/members`, `PATCH|DELETE /v1/cabinet/members/:user_id`.
**Pro – clinique/patients** : `GET|POST /v1/cabinet/patients`, `GET /v1/cabinet/patients/:id`, `GET|POST /v1/cabinet/patients/:id/notes`, `GET|PATCH /v1/cabinet/patients/:id/medical-record`, `GET|PUT /v1/cabinet/patients/:id/dental-chart`, `GET|POST /v1/cabinet/patients/:id/documents`, `GET /v1/cabinet/consultations/:id`, `POST /v1/cabinet/consultations/:id/acts|complete`, `POST /v1/cabinet/prescriptions`, `POST /v1/cabinet/prescriptions/:id/sign`.
**Pro – agenda/file** : `GET /v1/cabinet/agenda`, `GET /v1/cabinet/waiting-room`, `POST /v1/cabinet/waiting-room/call-next`, `GET /v1/cabinet/appointments`, `POST /v1/cabinet/appointments/:id/confirm|start`, `PATCH /v1/cabinet/appointments/:id`, `GET /v1/cabinet/waiting-list`, `POST /v1/cabinet/waiting-list/:id/offer`, `POST /v1/cabinet/slots`, `PATCH|DELETE /v1/cabinet/slots/:id`, `PUT /v1/cabinet/slots/:id/online`, `GET /v1/cabinet/conversations`.
**Webhooks** : `POST /v1/webhooks/stripe`.

## Annexe B — Mapping rôle ↔ extracteur de claims (sécurité)
| Endpoints | Extracteur | Règle |
|---|---|---|
| `/v1/account*`, `/v1/appointments*`, `/v1/documents*`, `/v1/quotes`, `/v1/conversations*` (patient) | `PatientAccountClaims` | `kind=patient` sinon 403 |
| `/v1/cabinet/members*`, `/v1/cabinet` (patch) | `ProAdminClaims` | `role=admin` |
| `/v1/cabinet/patients/:id/medical-record|dental-chart`, `consultations*`, `prescriptions*` | `ProPractitionerClaims` | rejette `secretary` |
| `/v1/cabinet/agenda`, `appointments`, `waiting-room`, `slots`, `conversations` | `ProSecretaryPlusClaims` | secretary/practitioner/admin ; clinique filtré pour secretary |

> **Implication front** : l'espace Secrétaire ne doit afficher **aucun** lien clinique (medical-record, dental-chart, consultation, ordonnance) — l'API renverrait 403 et ce serait hors secret médical.
