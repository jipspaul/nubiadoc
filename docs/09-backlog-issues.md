# 09 — Backlog d'issues prêtes à créer

> Backlog **issue-ready** : chaque brique de `08-plan-action-deploiement.md` est éclatée en issues granulaires. Copie un bloc → crée l'issue → traite ses micro-étapes une par une → coche la gate → passe à la suivante.
> Ordre = celui de `08` §3 (T0→T24). **Ne démarre jamais une issue dont le « Bloquée par » n'est pas Done.**

## Comment utiliser ce backlog
- Une **issue** = un titre `NUB-T<n>.<k>`, des **micro-étapes** (cases à cocher = commits/PR), des **critères d'acceptation** (= tests à écrire), une **gate** (le bloc de `08` §4).
- Les estimations : **S** (≤ ½ j), **M** (½–2 j), **L** (2–5 j). À ajuster à ta vélocité.
- Labels suggérés : `area:infra` `area:backend` `area:flutter` `area:security` `area:payments` `area:compliance` · `type:feature` `type:test` `type:chore` · `prio:P0/P1/P2`.

## Stack actée (décisions pour ne pas hésiter demain)
- **Backend** : **Rust / Axum** (modular monolith, workspace de crates) · **SQLx** (schéma + migrations `sqlx migrate`, requêtes vérifiées à la compilation) · pool SQLx pour les requêtes nécessitant le contexte RLS.
- **RLS** : chaque requête métier passe par une **transaction** qui exécute `SET LOCAL app.current_cabinet_id = $1` en premier (détaillé dans NUB-T1/T3). ⚠️ Avec un pooler en mode transaction, `SET LOCAL` n'est valable **que dans une transaction explicite** — d'où le pattern « tout passe par une transaction tenant-scoped ».
- **Tests** : `cargo test` (+ `sqlx::test` / Testcontainers sur Postgres réel) · `cargo-mutants` (mutation) · k6 (charge).
- **Front** : Flutter + **Bloc (flutter_bloc)** + Dio · `flutter_test` / `bloc_test` / `integration_test` · Playwright (back-office web).
- **Async** : apalis (Redis). **Temps réel** : WebSockets (Axum) + FCM.
- **Cloud** : Scaleway managé (Postgres/Redis/Object Storage/Secret Manager), conteneurs managés.

## Template d'issue (à copier)
```md
### NUB-T<n>.<k> — <titre>
**Bloquée par** : <issues> · **Labels** : <…> · **Estimate** : S/M/L

**Objectif** : <une phrase de valeur>

**Micro-étapes**
- [ ] …

**Critères d'acceptation (tests)**
- [ ] …

**Gate** : checklist `08` §4 verte (tests, RLS/RBAC, zéro-PII, couverture, CI, staging).
```

---

# BLOC A — Fondations
> Rien de métier ne démarre avant que tout le Bloc A soit Done + testé.

## T0 — Repo, CI, infra staging

### NUB-T0.1 — Initialiser le monorepo & la qualité de code
**Bloquée par** : — · **Labels** : `area:infra` `type:chore` `prio:P0` · **Estimate** : M

**Objectif** : un repo propre, typé strict, prêt à recevoir du code testé.

**Micro-étapes**
- [ ] Créer le repo Git (mono-repo : `/api` Rust (workspace Cargo), `/app` Flutter patient, `/backoffice` Flutter, `/infra` Terraform, `/docs`).
- [ ] `api` : `cargo new` en workspace, lints stricts (`#![deny(warnings)]` en CI, `clippy::pedantic` ciblé), édition 2021.
- [ ] `rustfmt` + `clippy` + `cargo-deny` ; commit hooks (pre-commit `cargo fmt --check` + `cargo clippy`).
- [ ] Conventions de commit (Conventional Commits) + template de PR + CODEOWNERS.
- [ ] `.env.example` ; **interdiction de secret commité** (ajouter `.gitignore` + scan).
- [ ] README repo : comment lancer dev/test localement.

**Critères d'acceptation (tests)**
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` existent et passent à vide.
- [ ] Un secret factice commité fait **échouer** le scan (test du garde-fou).

---

### NUB-T0.2 — Pipeline CI (bloquant au merge)
**Bloquée par** : T0.1 · **Labels** : `area:infra` `type:chore` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Forgejo Actions : jobs `fmt` (`cargo fmt --check`), `clippy`, `test` (avec service Postgres ou Testcontainers), `build`.
- [ ] **Scan dépendances** (`cargo audit` / `cargo-deny` / Trivy sur l'image) + **scan secrets** (gitleaks).
- [ ] Calcul de **couverture** + publication ; **seuils bloquants** (voir T-tests) configurés mais permissifs au départ, durcis ensuite.
- [ ] Cache des dépendances pour accélérer.
- [ ] Branche `main` protégée : merge interdit si CI rouge ou sans PR.

**Critères d'acceptation**
- [ ] Une PR rouge **ne peut pas** être mergée (vérifié).
- [ ] La CI tourne en < ~10 min sur le job principal.

---

### NUB-T0.3 — Infra staging (Terraform, Scaleway HDS)
**Bloquée par** : T0.1 · **Labels** : `area:infra` `type:chore` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] Terraform : projet Scaleway, **Postgres managé**, **Redis managé**, **Object Storage**, **Secret Manager**.
- [ ] Conteneurs managés (service `api` + service `worker`), registry d'images.
- [ ] Réseau : TLS, nom de domaine `api-staging`, en-têtes de sécurité (HSTS).
- [ ] Secrets injectés depuis Secret Manager (aucun en clair).
- [ ] Déploiement auto `main` → staging.
- [ ] Sauvegardes Postgres activées (PITR) — même en staging, pour roder la procédure.

**Critères d'acceptation**
- [ ] `terraform plan` reproductible, state distant chiffré.
- [ ] L'API « hello » répond en HTTPS sur staging.
- [ ] Smoke test post-déploiement automatique (health-check).

---

### NUB-T0.4 — Socle applicatif Rust/Axum (config, health, erreurs)
**Bloquée par** : T0.1 · **Labels** : `area:backend` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Crate `core/config` (validation des env vars au boot via `figment`/`serde`, fail-fast).
- [ ] `GET /health` (liveness/readiness : DB, Redis).
- [ ] **Gestion d'erreur centralisée** (type `AppError` + `IntoResponse`) → format d'erreur uniforme (`04` §7.2) avec `request_id`.
- [ ] Logger structuré JSON (`tracing` + `tracing-subscriber`) + **couche de scrubbing PII** (placeholder, complété en T3).
- [ ] Validation des payloads (extractor `Json` + `validator`), rejet des champs inconnus (`deny_unknown_fields`).
- [ ] Mode `api` vs `worker` via variable d'environnement (un seul binaire).

**Critères d'acceptation (tests)**
- [ ] `/health` renvoie 200 avec dépendances OK, 503 si DB down (testé).
- [ ] Une erreur métier renvoie le **format uniforme** + bon code HTTP (testé).
- [ ] Une requête avec champ inconnu est rejetée (whitelist).

---

## T1 — Modèle multi-tenant + RLS

### NUB-T1.1 — Schéma SQL de base + migrations (SQLx)
**Bloquée par** : T0.3, T0.4 · **Labels** : `area:backend` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Migrations `sqlx migrate` (SQL) + structs Rust mappées : `Cabinet`, `AppUser`, `CabinetMembership`, `Practitioner` (cf. `05` §5.1).
- [ ] Conventions : `id uuid`, `created_at/updated_at/deleted_at`, `cabinet_id` partout où requis.
- [ ] Première migration + script de seed **dev** (données fictives).
- [ ] Rôle Postgres applicatif **non-superuser** (créé via migration SQL).

**Critères d'acceptation (tests)**
- [ ] Migration s'applique et se rollback proprement (testé en CI via Testcontainers).
- [ ] Le rôle applicatif ne peut pas faire de DDL destructeur.

---

### NUB-T1.2 — Activer la RLS + policies tenant ⚠️ (issue critique)
**Bloquée par** : T1.1 · **Labels** : `area:security` `area:backend` `type:feature` `prio:P0` · **Estimate** : L

**Objectif** : isolation cabinet garantie **au niveau base**, même en cas de bug applicatif.

**Micro-étapes**
- [ ] Migration SQL : `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY` sur chaque table tenant.
- [ ] Policy `tenant_isolation` (USING + WITH CHECK sur `cabinet_id = current_setting('app.current_cabinet_id')::uuid`).
- [ ] Helper `with_tenant(cabinetId, fn)` : ouvre une **transaction interactive**, exécute `SET LOCAL app.current_cabinet_id`, puis `fn`.
- [ ] S'assurer que **toutes** les requêtes métier passent par ce helper (lint/architecture rule).
- [ ] Vérifier le comportement avec le **pooler** (mode transaction) : `SET LOCAL` valide uniquement en transaction.

**Critères d'acceptation (tests SÉCURITÉ — non négociables)**
- [ ] Cabinet A **ne lit jamais** une ligne de cabinet B (test par table tenant).
- [ ] Cabinet A **ne peut pas écrire** avec un `cabinet_id` de B (WITH CHECK).
- [ ] Une requête **hors** `with_tenant` (sans contexte) ne renvoie **aucune** ligne (échec sûr).
- [ ] Le rôle applicatif **ne bypasse pas** la RLS (test explicite).

---

## T2 — Auth + RBAC

### NUB-T2.1 — Authentification (JWT + refresh + MFA)
**Bloquée par** : T1.1 · **Labels** : `area:security` `area:backend` `type:feature` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] `POST /auth/login` (email + mot de passe ; hash **argon2id**).
- [ ] Access token JWT court (15 min) + **refresh token rotatif** (stocké hashé, révocable).
- [ ] **MFA** (TOTP) : enrôlement + `POST /auth/mfa/verify` ; obligatoire sur comptes cabinet.
- [ ] `POST /auth/refresh`, `POST /auth/logout` (révocation).
- [ ] Le JWT porte `user_id`, `cabinet_id` (claim), `role` — **jamais** acceptés depuis le client ensuite.
- [ ] **Rate limiting** + anti-brute-force sur `/auth`.

**Critères d'acceptation (tests)**
- [ ] Mauvais mot de passe → 401 générique (pas d'info sur l'existence du compte).
- [ ] Refresh rotatif : un ancien refresh réutilisé est rejeté (détection de replay).
- [ ] MFA requis bloque l'accès tant que non vérifié.
- [ ] Rate limit déclenché après N tentatives (testé).

---

### NUB-T2.2 — RBAC + garde tenant
**Bloquée par** : T2.1, T1.2 · **Labels** : `area:security` `area:backend` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] `@Roles()` decorator + `RolesGuard` (praticien / secrétariat / admin / patient).
- [ ] Middleware/extractor **tenancy** (`tower`) : extrait `cabinet_id` du token → ouvre `with_tenant` pour toute la requête.
- [ ] Matrice de permissions (`05`/`06`) : le secrétariat n'accède pas au contenu clinique.
- [ ] 403 uniforme sur permission refusée.

**Critères d'acceptation (tests SÉCURITÉ)**
- [ ] Secrétariat → `GET` contenu clinique = **403** (cloisonnement R.4127-72).
- [ ] Patient ne peut accéder qu'à **ses** données.
- [ ] `cabinet_id` falsifié dans le body est **ignoré** (seul le token fait foi).

---

## T3 — core : crypto, audit, tenancy

### NUB-T3.1 — Chiffrement colonne (KMS, clé par cabinet)
**Bloquée par** : T1.2, T2.2 · **Labels** : `area:security` `type:feature` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] Service `core/crypto` : chiffrement **applicatif** (AES-GCM) avant écriture, déchiffrement à la lecture.
- [ ] Clé **par cabinet** dérivée/enveloppée via Scaleway Key Manager (KMS) ; stocker `key_ref` (version), pas la clé.
- [ ] Helpers `encrypt_field` / `decrypt_field` + colonne `bytea` (ciphertext) + `key_ref`.
- [ ] Rotation de clé documentée (re-chiffrement par lot, job apalis).
- [ ] Traitement **INS** comme PII critique (chiffré, hash de recherche séparé si besoin).

**Critères d'acceptation (tests)**
- [ ] La valeur en base est bien du **ciphertext** (jamais le clair).
- [ ] Round-trip chiffrer→déchiffrer correct ; clé d'un autre cabinet **ne déchiffre pas**.
- [ ] Couverture **100 %** du module (critique) + **mutation testing** OK.

---

### NUB-T3.2 — Audit log append-only
**Bloquée par** : T1.2 · **Labels** : `area:security` `area:compliance` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Table `audit_log` partitionnée par mois (cf. `05` §6) ; privilèges **INSERT seul** pour le rôle applicatif.
- [ ] Couche `core/audit` (`tower`) : journalise accès/écriture sur donnée de santé (qui, quoi, quand) **sans PII**.
- [ ] Helper `audit(action, entity, entityId, metadata)`.
- [ ] Job de purge/archivage selon rétention (≥ 10 ans) journalisant chaque purge.

**Critères d'acceptation (tests)**
- [ ] `UPDATE`/`DELETE` sur `audit_log` par le rôle applicatif **échoue** (append-only prouvé).
- [ ] Lire un dossier patient crée une entrée `read_record` (testé).
- [ ] Aucune PII en clair dans `metadata` (assertion).

---

### NUB-T3.3 — Scrubbing PII des logs (finaliser T0.4)
**Bloquée par** : T0.4 · **Labels** : `area:security` `area:compliance` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Middleware logger : regex + listes (INS, emails, tél, noms) → masquage avant émission.
- [ ] Règle de lint custom interdisant `console.log` et le log d'objets « patient/medical » bruts.
- [ ] Tester sur des payloads piégés.

**Critères d'acceptation (tests)**
- [ ] Un log contenant un INS/email/tél ressort **masqué** (testé sur plusieurs formats).
- [ ] La CI **échoue** si un log brut de donnée santé est introduit (test du garde-fou).

---

## T4 — core : files / Object Storage

### NUB-T4.1 — Upload sécurisé + URLs signées + antivirus
**Bloquée par** : T3.1 · **Labels** : `area:backend` `area:security` `type:feature` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] Service `core/files` : upload vers Object Storage (objet **chiffré au repos**), clé `storage_key` par document.
- [ ] **URL signée temporaire** pour download (expiration courte).
- [ ] **Antivirus** sur tout upload avant stockage (ClamAV ou service) ; rejet si infecté.
- [ ] Calcul **sha256** (intégrité) + `mime_type` + taille max + types autorisés.
- [ ] Suppression = soft-delete + suppression objet selon rétention.

**Critères d'acceptation (tests)**
- [ ] Un fichier infecté (EICAR) est **rejeté** (testé).
- [ ] L'URL signée expire et devient invalide (testé).
- [ ] Type/MIME non autorisé rejeté ; sha256 vérifié au download.
- [ ] Accès à un document d'un autre cabinet **impossible** (RLS + scope).

---

> **Fin du Bloc A.** À ce stade : infra + CI + RLS + auth/RBAC + crypto + audit + files sont **prouvés par des tests**. Tu peux bâtir le métier sans risque de fondation.

---

# BLOC B — Domaines cœur

## T5 — Patient + MedicalRecord + consentements

### NUB-T5.1 — CRUD Patient (chiffré, tenant-scoped)
**Bloquée par** : T3.1, T3.2 · **Labels** : `area:backend` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Struct/table `patient` (cf. `05` §5.2) : INS chiffré, `contact`/`mutuelle` JSONB, `is_minor` calculé.
- [ ] Endpoints : `POST /patients`, `GET /patients/{id}`, `PATCH /patients/{id}` (tous via `with_tenant`).
- [ ] DTO + validation (format tél, n° sécu, email) ; mapping camelCase↔snake_case.
- [ ] Audit sur chaque accès/écriture ; INS jamais loggé.
- [ ] Soft-delete (pas de suppression dure).

**Critères d'acceptation (tests)**
- [ ] INS stocké chiffré ; absent des logs.
- [ ] Isolation tenant (A↛B) ; secrétariat OK sur admin, KO sur clinique.
- [ ] `is_minor` correct selon `birth_date` (cas limites majorité).

---

### NUB-T5.2 — MedicalRecord + ConsentRecord
**Bloquée par** : T5.1 · **Labels** : `area:backend` `area:compliance` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] `medical_record` (antécédents/allergies/traitements **chiffrés**).
- [ ] `consent_record` (purpose, granted, granted_at, revoked_at, evidence) — **révocable**.
- [ ] Garde « consentement valide » réutilisable : toute fonction santé le vérifie.
- [ ] `dental_chart` (teeth_status JSONB) — base du plan de traitement.

**Critères d'acceptation (tests)**
- [ ] Action santé sans consentement valide → **refus** (testé).
- [ ] Révocation de consentement effective immédiatement.
- [ ] Contenu médical chiffré en base.

---

## T6 — Notifications infra (FCM / Brevo / OctoPush)

### NUB-T6.1 — Canal push FCM (zéro PII) + jobs apalis
**Bloquée par** : T2.2 · **Labels** : `area:backend` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Intégration FCM ; enregistrement des device tokens patient.
- [ ] Payload **sans PII** : `{type, ref}` ; le contenu se charge ensuite authentifié.
- [ ] File apalis `notifications` (retry + backoff + idempotence par clé).
- [ ] Opt-in notifications + gestion des tokens expirés.

**Critères d'acceptation (tests)**
- [ ] Le payload push ne contient **aucune** donnée de santé (assertion).
- [ ] Un job rejoué n'envoie pas deux fois la même notif (idempotence).
- [ ] Échec d'envoi → retry, puis dead-letter loggé sans PII.

---

### NUB-T6.2 — Email transactionnel (Brevo) + SMS fallback (OctoPush)
**Bloquée par** : T6.1 · **Labels** : `area:backend` `type:feature` `prio:P1` · **Estimate** : M

**Micro-étapes**
- [ ] Templates email Brevo (confirmation RDV, document dispo, reçu paiement) **sans PII sensible**.
- [ ] SMS OctoPush en fallback (patient sans push) ; Twilio en backup config.
- [ ] Abstraction `NotificationChannel` (push|email|sms) + sélection par préférence/disponibilité.

**Critères d'acceptation (tests)**
- [ ] Sélection du canal correcte selon préférences/disponibilité (testé).
- [ ] Aucun contenu de santé dans email/SMS (assertion).

---

## T15 — Infos pratiques cabinet (facile, peut être avancé)

### NUB-T15.1 — Cabinet settings + endpoint public-cabinet
**Bloquée par** : T0.4 · **Labels** : `area:backend` `area:flutter` `type:feature` `prio:P2` · **Estimate** : S

**Micro-étapes**
- [ ] `cabinet.settings` JSONB (coordonnées, horaires, plan d'accès, contacts d'urgence, infos pratiques).
- [ ] `GET /cabinet/info` (lecture, scope cabinet).
- [ ] Écran Flutter « Infos cabinet ».

**Critères d'acceptation (tests)**
- [ ] Lecture renvoie les settings du **bon** cabinet (tenant).
- [ ] Écran affiche les infos (widget test).

---

## T7 — RDV + agenda + anti-double-booking

### NUB-T7.1 — Modèle Appointment + contrainte anti-chevauchement
**Bloquée par** : T5.1 · **Labels** : `area:backend` `area:security` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Modèle `appointment` + enum status (`05` §5.4).
- [ ] **Contrainte d'exclusion gist** anti-double-booking praticien (hors annulés/no_show).
- [ ] Machine à états (transitions valides uniquement) : requested→confirmed→checked_in→in_progress→done ; cancelled/no_show.

**Critères d'acceptation (tests)**
- [ ] Deux RDV chevauchants sur un praticien → **rejet** (testé).
- [ ] Transition d'état invalide → 409 (testé).
- [ ] Isolation tenant.

---

### NUB-T7.2 — Disponibilités & prise de RDV (API + app)
**Bloquée par** : T7.1, T6.1 · **Labels** : `area:backend` `area:flutter` `type:feature` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] `GET /availability` (créneaux libres par praticien) ; `POST /appointments`.
- [ ] `PATCH /appointments/{id}` (modif/annulation dans les délais).
- [ ] Confirmation auto (notif) + libération de créneau à l'annulation.
- [ ] App Flutter : écrans prise/modif/annulation, RDV à venir, historique.

**Critères d'acceptation (tests)**
- [ ] Créneau indisponible non réservable (API + UI).
- [ ] Annulation hors délai refusée avec message.
- [ ] E2E : prise de RDV bout-en-bout (intégration).

---

### NUB-T7.3 — Rappels automatiques (J-1) idempotents
**Bloquée par** : T7.2 · **Labels** : `area:backend` `type:feature` `prio:P1` · **Estimate** : M

**Micro-étapes**
- [ ] Job planifié apalis : sélection des RDV à rappeler, envoi push/email/SMS.
- [ ] Idempotence : un RDV n'est rappelé qu'une fois par fenêtre.

**Critères d'acceptation (tests)**
- [ ] Double exécution du job → **un seul** rappel (testé).
- [ ] Pas de rappel sur RDV annulé.

---

## T8 — Documents + coffre-fort

### NUB-T8.1 — Documents patient (upload, catégories, download signé)
**Bloquée par** : T4.1, T5.1 · **Labels** : `area:backend` `area:flutter` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] `POST /documents` (catégorie : devis, facture, ordo, radio, cbct, photo, cr, consigne, attestation).
- [ ] `GET /documents?category` + `GET /documents/{id}` (URL signée temporaire).
- [ ] Écran coffre-fort Flutter : liste par catégorie + téléchargement.
- [ ] Audit `read_document` à chaque consultation.

**Critères d'acceptation (tests)**
- [ ] Download via URL signée expirante ; intégrité sha256 vérifiée.
- [ ] Accès cross-cabinet impossible ; accès patient limité à ses docs.
- [ ] Audit présent à chaque lecture.

---

## T9 — Messagerie + triage par règles

### NUB-T9.1 — Conversations & messages chiffrés
**Bloquée par** : T5.1, T3.1 · **Labels** : `area:backend` `type:feature` `prio:P1` · **Estimate** : M

**Micro-étapes**
- [ ] Modèles `conversation` (scope cloisonné) + `message` (corps **chiffré**).
- [ ] Endpoints : lister conversations, envoyer message (texte/photo/doc), marquer lu.
- [ ] Pièces jointes via `core/files` (antivirus).

**Critères d'acceptation (tests)**
- [ ] Corps de message chiffré en base.
- [ ] Cloisonnement : un rôle ne voit que les scopes autorisés.
- [ ] Pièce jointe infectée rejetée.

---

### NUB-T9.2 — Triage par règles (flag visuel, NON décisionnel) 🚨
**Bloquée par** : T9.1 · **Labels** : `area:backend` `area:compliance` `type:feature` `prio:P1` · **Estimate** : S

**Objectif** : **prioriser visuellement**, jamais décider à la place de l'humain (ADR-009, `03` §2).

**Micro-étapes**
- [ ] Moteur de **règles mots-clés** → `triage_flag = urgent|normal` + `triage_reason` (traçabilité).
- [ ] Aucun routage automatique qui contourne le secrétariat ; pas de décision clinique.
- [ ] Affichage cabinet : urgents en tête de file.

**Critères d'acceptation (tests)**
- [ ] Un mot-clé d'urgence met `flag=urgent` **et** journalise la raison.
- [ ] Le flag **ne déclenche aucune** action clinique automatique (vérifié).
- [ ] Faux positifs/négatifs documentés (le flag reste indicatif).

---

> **Fin du Bloc B.** Patient, dossier, RDV, documents, messagerie, notifications : tout est tenant-scopé, chiffré, audité et testé.

---

# BLOC C — Wedge monétisable (chaîne stricte T10→T13)
> C'est ce qui se vend et ce qui impressionne en démo. Chaîne stricte : devis → signature → acompte → espace financier. Idempotence partout (paiement/signature/webhooks).

## T10 — Devis + versioning + CCAM

### NUB-T10.1 — Devis & lignes (CCAM, montants AMO/AMC)
**Bloquée par** : T5.1 · **Labels** : `area:backend` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Modèles `quote` + `quote_item` (cf. `05` §5.5) ; calcul `total_amount` (numeric, jamais float).
- [ ] Endpoints : `POST /quotes`, `GET /quotes`, ajout/suppression de lignes (tant que `draft`).
- [ ] Champs dentaires : `ccam_code`, `tooth`, `amc_part`, `amo_part`.
- [ ] Back-office Flutter : écran création/édition devis.

**Critères d'acceptation (tests)**
- [ ] Total recalculé correctement (cas multi-lignes, remises) — pas d'erreur d'arrondi.
- [ ] Isolation tenant.

---

### NUB-T10.2 — Versioning & immutabilité du devis signé
**Bloquée par** : T10.1 · **Labels** : `area:backend` `area:compliance` `type:feature` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] `POST /quotes/{id}/versions` (nouvelle version tant que non signé).
- [ ] À la signature : statut `signed`, **immuable**, `signed_sha256` + horodatage.
- [ ] Toute modif d'un devis `signed` → **409**.

**Critères d'acceptation (tests)**
- [ ] Modifier un devis signé → 409 (testé sur plusieurs champs).
- [ ] Le sha256 correspond au PDF signé (intégrité).
- [ ] Une nouvelle version ne casse pas l'historique des précédentes.

---

## T11 — Signature Yousign (eIDAS avancé)

### NUB-T11.1 — Intégration Yousign + webhook idempotent
**Bloquée par** : T10.2 · **Labels** : `area:payments` `area:backend` `type:feature` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] Intégration Yousign (création de procédure, niveau **AES**), backup Universign en abstraction.
- [ ] `POST /quotes/{id}/sign` (avec **Idempotency-Key**) → renvoie l'URL de signature in-app.
- [ ] `POST /webhooks/yousign` : **vérification de signature** + traitement **idempotent** → `quote.signed`, stockage `signature` (certificat probant).
- [ ] Parcours signature dans l'app patient (in-app, retour de statut).
- [ ] Archivage probant du document signé (sha256 + horodatage ; tiers-archiveur post-MVP).

**Critères d'acceptation (tests)**
- [ ] Webhook rejoué → **pas** de double signature/double effet (idempotence).
- [ ] Webhook avec signature invalide → rejeté.
- [ ] Statut visible des deux côtés ; échec géré (relance possible).
- [ ] Le déclenchement sans Idempotency-Key est refusé.

---

## T12 — Acompte Stripe/GoCardless + webhooks

### NUB-T12.1 — Encaissement acompte (CB + Apple/Google Pay)
**Bloquée par** : T11.1 · **Labels** : `area:payments` `area:backend` `type:feature` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] `POST /payments/intent` (Idempotency-Key) → PaymentIntent Stripe (CB, **Apple/Google Pay**).
- [ ] `POST /webhooks/stripe` : vérif signature + idempotent → `payment.paid`, génération **facture**, statut.
- [ ] GoCardless (SEPA) pour prélèvement ; abstraction provider.
- [ ] Parcours paiement dans l'app patient après signature.
- [ ] **PCI** : aucun numéro de carte ne transite/stocke chez nous (délégué Stripe).

**Critères d'acceptation (tests)**
- [ ] Webhook Stripe rejoué → **un seul** paiement enregistré (idempotence).
- [ ] Signature webhook invalide → rejet.
- [ ] Facture générée une seule fois ; montants exacts.
- [ ] Aucune donnée de carte loggée/stockée (assertion).

---

### NUB-T12.2 — Réconciliation & états de paiement
**Bloquée par** : T12.1 · **Labels** : `area:payments` `type:feature` `prio:P1` · **Estimate** : M

**Micro-étapes**
- [ ] États `pending/paid/failed/refunded` ; gestion des échecs et remboursements.
- [ ] Job de réconciliation (vérifie cohérence Stripe ↔ base) + alerte sur écart.
- [ ] Event WebSocket `quote.paid` vers back-office (badge cabinet).

**Critères d'acceptation (tests)**
- [ ] Échec de paiement géré (statut + retry éventuel).
- [ ] Écart de réconciliation détecté (testé sur cas simulé).

---

## T13 — Espace financier patient

### NUB-T13.1 — Vue financière patient (consultation 🟧)
**Bloquée par** : T10.1, T12.1 · **Labels** : `area:flutter` `area:backend` `type:feature` `prio:P1` · **Estimate** : M

**Micro-étapes**
- [ ] API agrégée : devis, factures, règlements, montant restant, échéances, messages admin.
- [ ] Écran Flutter « Espace financier ».

**Critères d'acceptation (tests)**
- [ ] Montants restants exacts (cas partiellement payé).
- [ ] Isolation patient (ne voit que ses données).

---

### NUB-T13.2 — Échéancier & financement 🎭 (démo)
**Bloquée par** : T13.1 · **Labels** : `area:flutter` `type:feature` `prio:P2` · **Estimate** : S

**Micro-étapes**
- [ ] Écran échéancier multi-jalons + rappels — **mocké** (données fictives) pour la démo.
- [ ] Marquer clairement « démo » dans le module (pas branché prod).

**Critères d'acceptation**
- [ ] Affiche un échéancier crédible sur données fictives ; **aucune** vraie donnée patient.

---

> **Fin du Bloc C.** Le wedge est complet et **prouvé** : devis versionné/immuable, signé eIDAS, acompte encaissé, espace financier. Idempotence vérifiée sur signature et paiement.

---

# BLOC D — Temps réel, agrégation, suivi

## T14 — Suivi & prévention

### NUB-T14.1 — Moteur de rappels de suivi 🟧 (scénarios 🎭)
**Bloquée par** : T6.1 · **Labels** : `area:backend` `type:feature` `prio:P2` · **Estimate** : M

**Micro-étapes**
- [ ] Règles de rappel (contrôle annuel, détartrage, implanto, paro, ortho, post-chirurgie).
- [ ] Job planifié : relance des patients sans consultation > 1 an.
- [ ] Scénarios cliniques détaillés **mockés** pour la démo ; moteur simple réel pour la prod.

**Critères d'acceptation (tests)**
- [ ] Un rappel se déclenche à l'échéance, une seule fois (idempotence).
- [ ] Relance > 1 an cible les bons patients (testé).

---

## T16 — WebSocket temps réel back-office

### NUB-T16.1 — Flux d'événements WebSocket (scope cabinet)
**Bloquée par** : T7.2, T9.1, T12.1 · **Labels** : `area:backend` `area:flutter` `type:feature` `prio:P1` · **Estimate** : M

**Micro-étapes**
- [ ] `GET /events/stream` (text/event-stream, **scopé cabinet**), via Redis pub/sub.
- [ ] Events : `appointment.updated`, `checkin.arrived`, `quote.paid`, `message.received`.
- [ ] Back-office Flutter : abonnement + mise à jour ciblée (badge, ligne d'agenda).
- [ ] Reconnexion auto + heartbeat.

**Critères d'acceptation (tests)**
- [ ] Un event d'un cabinet **n'arrive jamais** à un autre (isolation testée).
- [ ] Aucune PII dans le payload d'event.
- [ ] Reconnexion reprend sans doublon.

---

## T17 — Dashboard patient agrégé

### NUB-T17.1 — Tableau de bord d'accueil
**Bloquée par** : T7.2, T8.1, T9.1, T13.1 · **Labels** : `area:flutter` `area:backend` `type:feature` `prio:P1` · **Estimate** : M

**Micro-étapes**
- [ ] API agrégée : prochain RDV, docs à signer, questionnaires, messages non lus, paiements en attente, suivis, actions.
- [ ] Écran d'accueil Flutter (tuiles cliquables → écrans concernés).
- [ ] Optimiser le chargement (1 appel agrégé, cache court).

**Critères d'acceptation (tests)**
- [ ] Compteurs exacts (cas multiples) ; chaque tuile route au bon écran.
- [ ] Chargement < 2 s sur jeu de données réaliste.

---

# BLOC E — Démo investisseurs 🎬

## T18 — Plan de traitement 🎭

### NUB-T18.1 — Écran plan de traitement (données fictives)
**Bloquée par** : T5.2 · **Labels** : `area:flutter` `type:feature` `prio:P2` · **Estimate** : S

**Micro-étapes**
- [ ] Écran : soins réalisés/restants, prochaines étapes, RDV associés, coût global, reste à charge.
- [ ] Alimenté par `dental_chart` fictif / seed démo.

**Critères d'acceptation** : affichage crédible sur données fictives ; aucune logique métier réelle promise.

---

## T19 — Passeport implantaire 🎭

### NUB-T19.1 — Écran passeport implantaire (données fictives)
**Bloquée par** : T5.2 · **Labels** : `area:flutter` `type:feature` `prio:P2` · **Estimate** : S

**Micro-étapes**
- [ ] Écran : marque, références/lots, date de pose, position, documents associés, **export PDF**.
- [ ] Données fictives via seed démo.

**Critères d'acceptation** : PDF généré crédible ; pas de vraie donnée patient.

---

## T20 — Module démo + seed + scénario

### NUB-T20.1 — Module `demo` & jeu de données fictives réalistes
**Bloquée par** : T17.1 · **Labels** : `area:backend` `area:flutter` `type:chore` `prio:P1` · **Estimate** : M

**Micro-étapes**
- [ ] Module `demo` : seed cohérent (patients, RDV, devis, implants, radios factices) **isolé de la prod** (ADR-010).
- [ ] Flag d'environnement empêchant tout mélange fictif/réel.
- [ ] **Scénario de démo scripté** (parcours pas-à-pas pour le pitch) + polish UI.
- [ ] Répétition du parcours complet (rubriques 1-12) sans accroc.

**Critères d'acceptation (gate GD 🎬)**
- [ ] App patient complète jouable de bout en bout sur **données fictives**.
- [ ] Parcours fluide, rien ne casse à l'écran.
- [ ] Garde-fou : aucune connexion à une base de prod.

> **Jalon GD atteint** → pitch / poursuite vers le pilote prod.

---

# BLOC F — Vers le pilote prod 🚀 (G3)

## T21 — Durcissement sécurité

### NUB-T21.1 — Hardening applicatif
**Bloquée par** : socle (Bloc A-C) · **Labels** : `area:security` `type:chore` `prio:P0` · **Estimate** : M

**Micro-étapes**
- [ ] Revue en-têtes sécurité (CSP, HSTS, etc.), rate-limit global, rotation des secrets.
- [ ] Revue complète **scrubbing logs** + désactivation autocapture PostHog sur champs santé.
- [ ] Revue des permissions Postgres (moindre privilège).
- [ ] Dépendances à jour ; surface d'attaque minimale.

**Critères d'acceptation** : checklist sécurité passée ; scans sans vulnérabilité critique.

---

## T22 — Pré-audit / pen-test

### NUB-T22.1 — Test d'intrusion ciblé + correctifs
**Bloquée par** : T21.1 · **Labels** : `area:security` `area:compliance` `type:chore` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] Pré-audit interne (OWASP ASVS) ; puis pen-test ciblé (prestataire).
- [ ] Correctifs des findings ; re-test.

**Critères d'acceptation** : aucun finding critique/élevé ouvert avant prod.

---

## T23 — Conformité (parallèle, non bloquante pour le code)

### NUB-T23.1 — Dossier conformité prod (`07` §11)
**Bloquée par** : — (démarre tôt, en parallèle) · **Labels** : `area:compliance` `type:chore` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] **AIPD** validée par le DPO.
- [ ] **DPA** signés (Scaleway, Stripe, GoCardless, Yousign, Brevo, OctoPush, FCM, PostHog).
- [ ] Hébergement **HDS** contractualisé ; registre des traitements ; politique de confidentialité.
- [ ] Procédure **violation de données** ; **RC pro santé** souscrite.

**Critères d'acceptation** : les **8 points de `07` §11** sont ☑.

---

## T24 — Bascule prod (G3)

### NUB-T24.1 — Mise en production du pilote
**Bloquée par** : T21.1, T22.1, T23.1 · **Labels** : `area:infra` `area:compliance` `type:chore` `prio:P0` · **Estimate** : L

**Micro-étapes**
- [ ] Infra **prod** HDS (Terraform), secrets prod, monitoring/alerting (erreurs, latence, jobs).
- [ ] **Sauvegardes + test de restauration** prouvé ; plan de **rollback** (< 15 min) testé en staging.
- [ ] Déploiement blue/green ou rolling + health-checks avant bascule trafic.
- [ ] **Runbook d'incident** ; fenêtre d'astreinte planifiée (le solo = l'astreinte).
- [ ] Onboarding du cabinet pilote ; support défini.

**Critères d'acceptation (gate G3 🚀 — la plus stricte)**
- [ ] Les 8 points conformité ☑ (`07` §11) **avant** toute donnée patient réelle.
- [ ] Restauration testée ; rollback testé.
- [ ] Smoke tests prod verts ; alerting actif.

> **G3 atteint** = pilote en production sur données réelles, conforme. Démo = fictif ; prod = conformité complète. On ne mélange jamais.

---

## Récapitulatif — ordre de création des issues
T0.1 → T0.2 → T0.3 → T0.4 → T1.1 → **T1.2** → T2.1 → T2.2 → **T3.1** → T3.2 → T3.3 → T4.1 → T5.1 → T5.2 → T6.1 → T6.2 → T15.1 → T7.1 → T7.2 → T7.3 → T8.1 → T9.1 → T9.2 → **T10.1 → T10.2 → T11.1 → T12.1** → T12.2 → T13.1 → T13.2 → T14.1 → T16.1 → T17.1 → T18.1 → T19.1 → **T20.1 (GD)** → T21.1 → T22.1 → T23.1 (en parallèle dès le début) → **T24.1 (G3)**.

> Les issues **en gras** sont les verrous critiques : ne les bâcle pas, c'est là que vivent les vrais risques (RLS, crypto, wedge, signature/paiement, démo, prod).

