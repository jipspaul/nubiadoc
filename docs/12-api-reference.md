# 12 — Référence API (contrats)

> Contrat complet des routes de l'API **Rust / Axum**, prêt à développer. Couvre tout le produit : auth/comptes, cabinet, patient (RDV, docs, messagerie, wedge), marketplace, back-office (clinique, devis, ordonnance), temps réel, webhooks. Le back-office **V2 (Spotlight + assistant)** est en **annexe** (post-traction).
> Source de vérité métier : `06` (specs), `05` (modèle), `04` (archi/ADR), `11` (marketplace), `07` (conformité). En cas de divergence, ces docs priment et ce fichier doit être réaligné.
> Statut : **spécification** — aucune route n'est encore codée. Implémentation séquencée par `09` (NUB-T*).

## Sommaire
1. Conventions transverses
2. Système & santé
3. Auth & comptes (`identity`)
4. Onboarding pro & vérification RPPS (`onboarding-pro`)
5. Cabinet & membres (`cabinet`)
6. Compte patient, couverture & proches (`account`)
7. Patient — tableau de bord, RDV & préparation (`scheduling` côté patient)
8. Patient — documents & coffre-fort (`documents`)
9. Patient — messagerie (`messaging`)
10. Wedge — devis, signature, paiement (`billing`)
11. Parcours de soins patient (plan, passeport, suivi)
12. Marketplace — recherche, annuaire, réservation, avis (`directory`/`search`/`booking`/`reviews`)
13. Back-office — agenda & salle d'attente (`scheduling`)
14. Back-office — patients & clinique (`clinical`)
15. Back-office — consultation au fauteuil
16. Back-office — plan de traitement & devis
17. Back-office — ordonnance (`prescription`)
18. Back-office — messagerie priorisée
19. Notifications & devices
20. Temps réel (WebSocket)
21. Webhooks entrants (prestataires)
22. Pharmacie — tenant, annuaire & click-and-collect (`pharmacy`)
- **Annexe A** — Back-office V2 (recherche unifiée + assistant) · post-traction
- **Annexe B** — Codes d'erreur · matrice rôles · index des routes

---

## 1. Conventions transverses

### 1.1 Base & versioning
- **Base URL** : `/v1`. Toute rupture de contrat → `/v2`. Préfixe santé hors version : `/health`.
- **Format** : JSON UTF-8. Clés en **`snake_case`** (cohérent avec `05`). `Content-Type: application/json`.
- **IDs** : UUID v4 (string). **Dates** : ISO 8601 UTC (`2026-06-03T09:12:00Z`). **Fuseaux** : stockés en UTC, l'affichage local est côté client.
- **Montants** : entiers en **centimes** (`amount_cents: 206000`) + `currency` (`"EUR"`). Jamais de float (cf. `05` §1).

### 1.2 Authentification
- **Bearer JWT** : `Authorization: Bearer <token>`. Access token court (~15 min) + refresh token (rotation).
- **Deux audiences** :
  - **Token patient** (plateforme) : claim `sub` = `app_user_id`, `account_id` = `patient_account_id`, `aud: "patient"`.
  - **Token pro** (cabinet) : `sub` = `app_user_id`, **`cabinet_id`** + **`role`** (`practitioner|secretary|admin`), `aud: "pro"`.
- ⚠️ **`cabinet_id` ne vient JAMAIS du client** (corps/query/header) : uniquement du token (cf. `05` §2). Toute route pro ouvre sa transaction via `with_tenant(cabinet_id, …)` → `SET LOCAL app.current_cabinet_id`.
- Routes **publiques** (annuaire, recherche, profils) : pas de token requis ; un token patient enrichit la réponse (ex. « déjà patient ici »).

### 1.3 Rôles & RBAC (par-dessus la RLS)
| Rôle | Portée |
|---|---|
| `patient` | Ses propres données (compte global + dossiers liés), ses RDV, ses docs. |
| `secretary` | **Administratif** du cabinet courant. **Jamais** le contenu clinique (note, odontogramme, journal, ordonnance) → `403`. |
| `practitioner` | Clinique **+** administratif du cabinet courant. |
| `admin` | Gestion du cabinet (membres, réglages) + tout le reste du cabinet. |
- Une action interdite au rôle → **`403 forbidden`** (cf. `06` critères transverses §2, `07` §4). Le cloisonnement secrétariat/clinique est **non négociable**.

### 1.4 Pagination, tri, filtres
- **Cursor-based** par défaut : `?limit=20&cursor=<opaque>`. Réponse : `{ "data": [...], "page": { "next_cursor": "…"|null, "limit": 20 } }`.
- Tri : `?sort=-created_at` (préfixe `-` = desc). Filtres : query params nommés (documentés par route).

### 1.5 Idempotence
- **Obligatoire** sur toute mutation à effet externe (paiement, signature, booking, envoi) : header **`Idempotency-Key: <uuid>`**. Rejouer la même clé → **même réponse**, pas de double effet (cf. `06` §6, `07` §6.3). Clé conservée ≥ 24 h.

### 1.6 Format d'erreur (RFC 9457 — `application/problem+json`)
```json
{
  "type": "https://nubia.health/errors/validation",
  "title": "Requête invalide",
  "status": 422,
  "code": "validation_error",
  "detail": "Le champ 'starts_at' est requis.",
  "errors": [{ "field": "starts_at", "rule": "required" }],
  "trace_id": "01J…"
}
```
- `code` = identifiant machine stable (cf. **Annexe B**). `trace_id` = corrélation logs (jamais de PII).

### 1.7 Codes HTTP standard
`200` OK · `201` créé · `202` accepté (async) · `204` sans contenu · `400` malformé · `401` non authentifié · `403` interdit (rôle/cloisonnement) · `404` introuvable · `409` conflit (ex. devis signé, double-booking) · `410` expiré (lien/URL signée) · `422` validation · `429` rate limit · `5xx` serveur.

### 1.8 Sécurité & audit
- **TLS** partout, HSTS, en-têtes sécurité. **Rate limiting** renforcé sur `/v1/auth/*` (`07` §10.2).
- **Audit** (`audit_log`, append-only) : tout accès/écriture sur donnée de santé journalisé (`actor`, `action`, `entity`, `entity_id`), **zéro PII** dans le log (`06` §3, `07` §2.9).
- **Consentement** : toute opération sur donnée de santé vérifie un `consent_record` valide (`06` §5).
- **Uploads** : antivirus + vérif `mime`/taille ; documents chiffrés au repos, accès par **URL signée expirante** (`05` §5.3).

### 1.9 Conventions de nommage des routes
- Collections au pluriel (`/appointments`), sous-ressources imbriquées (`/conversations/{id}/messages`).
- Espace **pro** préfixé `/cabinet/...` quand il y a ambiguïté avec l'espace patient (ex. `/v1/cabinet/patients` ≠ `/v1/appointments`).
- Actions non-CRUD = sous-chemin verbe : `POST …/{id}/sign`, `POST …/{id}/cancel`, `POST …/call-next`.

---

## 2. Système & santé

| Méthode | Chemin | Auth | Description |
|---|---|---|---|
| GET | `/health` | — | Liveness. `200 {"status":"ok"}`. |
| GET | `/health/ready` | — | Readiness (DB, Redis joignables). `200`/`503`. |
| GET | `/metrics` | interne | Prometheus (réseau interne uniquement). |

---

## 3. Auth & comptes (`identity`)

| Méthode | Chemin | Auth | Description |
|---|---|---|---|
| POST | `/v1/auth/register` | — | Création compte **patient** (e-mail + mot de passe) + CGU. Réponse `201` même si l'email est déjà pris (anti-énumération, #4436). |
| POST | `/v1/auth/login` | — | Login → access + refresh. Patient ou pro (selon compte). |
| POST | `/v1/auth/refresh` | refresh | Rotation du refresh, nouveau access. |
| POST | `/v1/auth/logout` | oui | Révoque le refresh courant. |
| POST | `/v1/auth/password/forgot` | — | Envoie un lien de reset (réponse neutre, anti-énumération). |
| POST | `/v1/auth/password/reset` | — | Reset via token. |
| POST | `/v1/auth/mfa/enroll` | pro | Démarre l'enrôlement TOTP (renvoie secret/QR). |
| POST | `/v1/auth/mfa/verify` | pro | Valide le code, active la MFA. |
| GET | `/v1/me` | oui | Profil du porteur du token (compte + rôles/cabinets + pharmacies). |
| POST | `/v1/auth/select-pharmacy-context` | pro (login) | Émet un JWT `kind:"pharma"` scopé pharmacie (cf. §22). |
| POST | `/v1/auth/franceconnect/start` · `/callback` | — | FranceConnect patient (**post-MVP**, `07` §9.3). |
| POST | `/v1/auth/psc/start` · `/callback` | — | Pro Santé Connect / e-CPS (**post-MVP**, `07` §9.2). |

**Contrats clés**

`POST /v1/auth/register` — body : `email`, `password`, `accept_cgu:true`, `cgu_version`. → `201 { account_id, access_token, refresh_token }`. Si l'email est déjà pris, renvoie aussi `201` avec un `account_id`/`access_token`/`refresh_token` leurres (aucun compte créé, aucun token exploitable) plutôt qu'un `409 email_taken` — anti-énumération, parité avec `login`/`forgot` (§1.8, #4436). Erreurs restantes : `422` (politique mot de passe), `422 cgu_required`. Effet (email libre) : crée `app_user` + `patient_account` + `consent_record(purpose='soins')` horodaté (`06` E3.1).

`POST /v1/auth/login` — body : `email`, `password`, `mfa_code?`. → `200 { access_token, refresh_token, token_type:"Bearer", expires_in }`. Si pro avec MFA : `401 mfa_required` puis renvoyer avec `mfa_code` (`401 unauthenticated` si le code est faux ; `503 kms_not_configured` si la clé KMS du serveur est inexploitable, cf. ci-dessous). Rate-limited.

`POST /v1/auth/mfa/enroll` — porteur : token pro, body `{}`. → `200 { totp_secret, otpauth_url }` (Base32 ; `otpauth://` SHA1, 6 chiffres, période 30 s). Rien n'est persisté à cette étape ; chaque appel rend un secret neuf.

`POST /v1/auth/mfa/verify` — porteur : token pro, body : `totp_secret` (rendu par `/enroll`), `totp_code`. Le code est validé **avant** toute écriture. → `200 { message:"MFA activée." }` : enrôlement chiffré écrit dans `mfa_enrollment` (secret jamais stocké en clair), `app_user.totp_enabled = true`, le login suivant exige `mfa_code`. Un nouvel appel (ré-enrôlement) remplace l'enrôlement existant. Erreurs : `422 validation_error` (secret non Base32, code faux/expiré, champ inconnu ou manquant), `403 forbidden` (token patient/pharma), `401 unauthorized` (sans token), `503 kms_not_configured` (`KMS_MASTER_KEY` absente/mal formée côté serveur — #6980/#7216 : cette lacune de déploiement répondait auparavant `500 internal_error` sur tout code **valide**, un code faux répondant 422, d'où une MFA inactivable ; le binaire refuse désormais de démarrer sans clé valide, ce `503` reste la garde en profondeur).

`GET /v1/me` → `{ user_id, email, kind:"patient"|"pro", account_id?, display_name?, memberships:[{ cabinet_id, role, cabinet_name }], pharmacy_memberships:[{ pharmacy_id, role, pharmacy_name }] }`. `display_name` (#6170) : `"{first_name} {last_name}"` (`app_user`), absent si les deux sont vides. Pour un pro multi-cabinets, le **choix du cabinet actif** se fait à la connexion (le token porte un seul `cabinet_id`). Les memberships pharmacie (tenant dédié, §22) partagent le même login ; le contexte pharmacie s'active via `POST /v1/auth/select-pharmacy-context`.

`POST /v1/auth/select-pharmacy-context` — body : `pharmacy_id`. Porteur : token pro de login. → `200 { access_token, token_type, expires_in, context:{ pharmacy_id, role } }` avec claims `{ kind:"pharma", pharmacy_id, role }`. Erreurs : `404` (pharmacie inconnue ou non listée pour un non-membre, anti-énumération), `403 no_membership`.

---

## 4. Onboarding pro & vérification RPPS (`onboarding-pro`)
> Self-service B2B (US-D07, `06` E4.9). Un pro crée son compte **et** son cabinet, soumet son RPPS/ADELI, qui est vérifié au référentiel **ANS**. Profil annuaire **non listé** tant que non `verified`.

| Méthode | Chemin | Auth | Description |
|---|---|---|---|
| POST | `/v1/pro/register` | — | Crée `app_user` (pro) + `cabinet` + `cabinet_membership(admin)` + `provider`. |
| POST | `/v1/pro/verification` | pro(admin) | Soumet RPPS **ou** ADELI pour vérification ANS. |
| GET | `/v1/pro/verification` | pro | Statut : `pending|verified|rejected`. |
| PATCH | `/v1/cabinet/provider` | pro | Édite le **profil public** (bio, actes, tarifs, langues, PMR, photo). |
| PUT | `/v1/cabinet/provider/listing` | pro | Active/désactive la **mise en ligne** (refusée si non `verified`). |

**Contrats clés**

`POST /v1/pro/register` — body : `email`, `password`, `cabinet:{ raison_sociale, siret?, specialite }`, `practitioner:{ first_name, last_name, rpps?, adeli? }`. → `201 { account_id, cabinet_id, provider_id, access_token }`. L'`app_user` reçoit `role=admin` sur le cabinet créé.

`POST /v1/pro/verification` — body : `{ id_type:"rpps"|"adeli", identifier }`. → `202 { verification_id, status:"pending" }`. Async : un job interroge l'annuaire ANS → met `provider.rpps_verified` + `provider_verification.status`. Tant que `≠ verified`, `PUT …/listing` renvoie `409 provider_not_verified` (`07` §4.7).

---

## 5. Cabinet & membres (`cabinet`)

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/cabinet` | pro | Cabinet courant (`settings` : horaires, branding, infos pratiques). |
| PATCH | `/v1/cabinet` | admin | Édite réglages/infos pratiques. |
| GET | `/v1/cabinet/members` | admin | Liste des membres + rôles. |
| POST | `/v1/cabinet/members` | admin | **Crée un compte** (praticien/secrétaire) → invite. |
| PATCH | `/v1/cabinet/members/{user_id}` | admin | Change le rôle/permissions. |
| DELETE | `/v1/cabinet/members/{user_id}` | admin | Désactive l'accès (soft). |

`POST /v1/cabinet/members` — body : `{ email, role:"practitioner"|"secretary"|"admin", first_name, last_name, rpps? }`. → `201`. Crée `app_user` (si nouveau) + `cabinet_membership`. Le dashboard pro peut donc créer des comptes (US-D07).

### 5.1 Reprise de données (`imports`, DP-F14.a #7179)

Pipeline générique **upload → dry-run → run**, suivi dans `data_import_job` (migrations 0168 + 0268). Rôle `admin`. Le fichier source est stocké **chiffré** (enveloppe KMS sous le cabinet : il peut contenir des INS) ; le rapport ne contient jamais de PII au-delà de la clé externe.

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| POST | `/v1/cabinet/imports` | admin | Upload multipart (`kind`, `file`, `source_system?`) → `201` job `pending` (ou `failed` si le fichier est inexploitable, motif dans `report`). Aucune écriture patient/RDV. |
| POST | `/v1/cabinet/imports/{id}/dry-run` | admin | Analyse à blanc : même pipeline que le run, transaction annulée → rapport ligne à ligne (`report.mode="dry_run"`), statut inchangé. |
| POST | `/v1/cabinet/imports/{id}/run` | admin | Import effectif, **idempotent** (re-jouable). `running` pendant l'exécution → `completed` (erreurs de lignes dans le rapport) ou `failed` (erreur technique, rien d'écrit). Run concurrent → `409 invalid_status`. |
| GET | `/v1/cabinet/imports/{id}` | admin | Statut, compteurs (`total_count`, `imported_count` = créés + mis à jour, `skipped_count` = inchangés, `error_count`), horodatages, `report`. Autre cabinet → `404`. |

`kind` : `csv_patients` | `csv_appointments` (parseur `ImportSource` ; DSIO à venir, DP-F14.b). `file` ≤ 10 Mo.

**Rapport** (`report`) : `{ mode:"upload"|"dry_run"|"run", total, created, updated, unchanged, errors, lines:[{ line, external_ref?, action:"created"|"updated"|"unchanged"|"error", entity_id?, message? }] }` — `line` = numéro dans le fichier (1 = en-têtes). Une ligne en erreur (valeur invalide, chevauchement de RDV `23P01`, patient/praticien introuvable…) n'annule que cette ligne (SAVEPOINT).

**Idempotence / doublons** : (1) clé externe `ref_externe` → `patient.external_ref` / `appointment.external_ref` (unique par cabinet) : re-jouer le même fichier met à jour au lieu de créer ; (2) sans clé externe, **correspondance exacte nom + prénom + date de naissance** (insensible à la casse ; naissance absente = absente des deux côtés) — plusieurs homonymes → ligne en erreur (résolution manuelle), jamais de rattachement arbitraire ; un RDV sans clé externe est reconnu par patient + praticien + début. Un INS déjà connu n'est jamais écrasé ; un INS partagé par deux patients ouvre une paire `patient_merge_candidate` (revue via `GET /v1/cabinet/patients/merge-candidates`).

**Format CSV** (exemples : `api/tests/fixtures/import/patients.csv`, `appointments.csv`) : séparateur `;`, encodage **UTF-8** (BOM toléré), 1re ligne = en-têtes en français (casse/accents/espaces indifférents : `Prénom`, `Date de naissance` acceptés), colonnes inconnues ignorées, cellules vides = absentes. Dates `JJ/MM/AAAA` (ou `AAAA-MM-JJ`) ; horodatages `JJ/MM/AAAA HH:MM` en heure locale **Europe/Paris** (ou RFC 3339 avec décalage explicite).

- `csv_patients` — colonnes : `ref_externe` · **`nom`** · **`prenom`** · `date_naissance` · `telephone` · `email` · `adresse` · `code_postal` · `ville` · `ins` (15 chiffres, chiffré en base). Coordonnées → `patient.contact` (`tel`, `email`, `adresse`, `code_postal`, `ville`).
- `csv_appointments` — colonnes : `ref_externe` · `patient_ref_externe` (ou `nom` + `prenom` + `date_naissance`) · `praticien_rpps` (obligatoire si le cabinet a plusieurs praticiens) · **`debut`** · `fin` ou `duree_min` (défaut 30) · `statut` · `motif`. `statut` : `confirmé`/`planifié` → `confirmed`, `honoré`/`terminé` → `done`, `annulé` → `cancelled`, `absent`/`lapin` → `no_show`, `demandé` → `requested` (valeurs de l'énum acceptées telles quelles) ; vide → `done` si passé, `confirmed` sinon. Importer les patients **avant** les RDV.

Erreurs : `422 validation_error` (`kind` inconnu, `file` absent/vide/trop gros), `403 forbidden` (rôle ≠ admin), `404` (job inconnu ou autre cabinet), `409 invalid_status` (run en cours, ou fichier inexploitable), `503 kms_not_configured` si `KMS_MASTER_KEY` absente/mal formée (#6980). Audit : `data_import_upload`, `data_import_run` (`entity = data_import_job`).

---

## 6. Compte patient, couverture & proches (`account`)
> Niveau **plateforme** (`patient_account`), portable entre cabinets (`05` §9-10).

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/account` | patient | Identité, contact. |
| PATCH | `/v1/account` | patient | MAJ coordonnées (audité, `06` E3.1.2). |
| GET | `/v1/account/coverage` | patient | Couverture santé. |
| PATCH | `/v1/account/coverage` | patient | Régime oblig., n° sécu, mutuelle, tiers payant (US-P29). |
| POST | `/v1/account/coverage/card` | patient | Upload carte mutuelle recto/verso (→ `document`). |
| GET | `/v1/account/avatar` | patient | Photo de profil (octets + content-type ; 404 si aucune). |
| PUT | `/v1/account/avatar` | patient | Pose la photo de profil (`{mime, data_base64}` ; JPEG/PNG/WebP ≤ 300 Ko ; 422 sinon). |
| GET | `/v1/account/consents` | patient | Consentements (purpose/granted). |
| PUT | `/v1/account/consents/{purpose}` | patient | Donne/révoque un consentement (`consent_record`). |
| GET | `/v1/account/notification-preferences` | patient | Préférences notif. |
| PATCH | `/v1/account/notification-preferences` | patient | MAJ opt-in par canal/type. |
| GET | `/v1/account/dependents` | patient | Proches / ayants droit. |
| POST | `/v1/account/dependents` | patient | Ajoute un proche (crée un `patient_account` lié). |
| GET | `/v1/account/dependents/{id}` | patient | Détail d'un proche. |
| PATCH | `/v1/account/dependents/{id}` | patient | Édite (sa propre couverture incluse). |
| DELETE | `/v1/account/dependents/{id}` | patient | Révoque la tutelle (soft, `account_guardianship.active=false`) ; révoque aussi la demande d'accès d'origine s'il y en a une. |
| GET | `/v1/account/access-requests` | patient | Demandes d'accès « proche adulte » envoyées (`direction:"sent"`) ET reçues (`direction:"received"`, avec `requester_first_name`/`requester_last_name`). |
| POST | `/v1/account/access-requests` | patient | Invite un proche adulte : demande `envoyee`, aucun accès avant acceptation ; notification in-app + e-mail à l'invité. |
| POST | `/v1/account/access-requests/{id}/resend` | patient | Relance une demande `envoyee` (invitant). |
| DELETE | `/v1/account/access-requests/{id}` | patient | Annule une demande `envoyee` (invitant, soft `cancelled_at`). |
| POST | `/v1/account/access-requests/{id}/accept` | patient | L'invité accepte (body optionnel `{scope}` pour restreindre) → crée `account_guardianship(guardian=demandeur, dependent=invité, authority='delegated')`. |
| POST | `/v1/account/access-requests/{id}/refuse` | patient | L'invité refuse : rien n'est accordé. |
| POST | `/v1/account/access-requests/{id}/revoke` | patient | Retire un accès `acceptee` — par l'invité OU le demandeur ; désactive le lien et notifie l'autre partie. |

**Contrats clés**

`PATCH /v1/account` — body : `{ first_name?, last_name?, phone?, birth_date?, address?{…} }`. `email` toujours rejeté (`422`). `birth_date` : réglable une seule fois — `POST /v1/auth/register` crée le compte sans date de naissance, donc le premier PATCH qui en fournit une l'enregistre ; en fournir une alors qu'elle est déjà connue → `422` (#7036).

`PATCH /v1/account/coverage` — body : `{ regime_obligatoire:"regime_general"|"ame"|"css", nss?, mutuelle:{ amc, numero_adherent, plateforme? }, tiers_payant:bool }`. → `200`. ⚠️ `nss` **chiffré** côté serveur (`05` §10.1), jamais renvoyé en clair (masqué : `"2 91 03 …78"`). Audité.

`POST /v1/account/coverage/card` — `multipart/form-data` : `side:"recto"|"verso"`, `file`. → `201 { document_id }`. Antivirus + chiffrement ; `document.category='carte_mutuelle'`.

`POST /v1/account/dependents` — body : `{ first_name, last_name, birth_date, relationship:"enfant", coverage?{…} }`. → `201 { dependent_account_id }`. Crée un `patient_account` + `account_guardianship(guardian=moi, dependent, authority='full')`. **Réservé à un enfant mineur (#7009)** : `birth_date` obligatoire ; `relationship` ≠ `enfant` ou 18 ans et plus → `422 { code:"adult_requires_consent" }` — un adulte ne peut être rattaché qu'après son accord, via `POST /v1/account/access-requests`. Le titulaire peut ensuite réserver/gérer pour ce proche (header `X-On-Behalf-Of: <dependent_account_id>` sur les routes RDV/docs ; vérifié contre `account_guardianship`). Conformité mineurs : `07` §4.6.

`POST /v1/account/access-requests` — body : `{ first_name, last_name, relationship:"conjoint"|"autre"|"enfant", channel:"email"|"sms", email?, phone?, scope:["rendez_vous"|"documents"|"ordonnances"|"dossier_medical"|"messages"] }`. → `201 { id, direction:"sent", first_name, last_name, relationship, status:"envoyee", channel, scope, sent_at }`. Sens du lien (maquette « Invitation proche adulte ») : le demandeur veut gérer le dossier de l'invité ; l'invité décide. Si un compte patient porte déjà l'e-mail, il est lié (`invitee_account_id`) et notifié (`access_request_received`) ; sinon la demande lui sera rapprochée par e-mail/téléphone à sa prochaine lecture de `GET /v1/account/access-requests`. Doublon actif → `409 duplicate_access_request` ; s'inviter soi-même → `422`. `accept` (body optionnel `{ scope }`, sous-ensemble du périmètre proposé) matérialise l'accès dans `account_guardianship` (`authority='delegated'`) et notifie le demandeur (`access_request_decided`) ; `revoke` (invité ou demandeur) le désactive et notifie l'autre partie (`access_request_revoked`). Statuts : `envoyee` / `acceptee` / `refusee` / `expiree`, plus `revoked_at` (accès retiré) et `decided_at`. Une demande `envoyee` sans décision sous 30 jours passe automatiquement `expiree` (reaper périodique `access_request_expiry.rs`, #7296) — elle sort de l'anti-doublon (`status IN ('envoyee', 'acceptee')`), une nouvelle invitation redevient possible pour le même couple.

---

## 7. Patient — tableau de bord, RDV & préparation

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/dashboard` | patient | Vue agrégée d'accueil (US-P13). |
| GET | `/v1/appointments` | patient | Mes RDV (tous praticiens), `?filter=upcoming\|history` (alias `?status=upcoming\|past`). Les deux vues **partitionnent** l'ensemble des RDV : `history` = statut terminal (`done`/`cancelled`/`no_show`, **quelle que soit** la position de `starts_at` par rapport à `now()` — un patient reçu et clôturé avant l'heure de son créneau y apparaît immédiatement, #6875) ou RDV `requested`/`confirmed` dont l'heure est passée ; `upcoming` = `requested`/`confirmed` à venir, ou `checked_in`/`in_progress` dans `now() ± 1 jour`. |
| GET | `/v1/appointments/{id}` | patient | Détail d'un RDV. |
| POST | `/v1/appointments` | patient | Prendre RDV (voir aussi `/bookings` marketplace §12). |
| PATCH | `/v1/appointments/{id}` | patient | Modifier (dans les délais). |
| POST | `/v1/appointments/{id}/cancel` | patient | Annuler (libère le créneau). |
| POST | `/v1/appointments/{id}/checkin` | patient | Check-in (QR/app/géofencing). |
| GET | `/v1/appointments/{id}/preparation` | patient | Préparer mon RDV (adresse, à apporter, infos). |
| GET | `/v1/appointments/{id}/directions` | patient | Temps de trajet (`?mode=car\|transit\|walk`). |
| GET | `/v1/appointments/{id}/queue` | patient | Position en salle d'attente virtuelle (+ via WS §20). |
| POST | `/v1/appointments/{id}/callback-request` | patient | Demander à être rappelé (US-P11). |
| POST | `/v1/waiting-list` | patient | S'inscrire sur liste d'attente (🎭, US-P12). |

**Contrats clés**

`GET /v1/dashboard` → `{ next_appointment?, to_sign:[{quote_id,…}], to_pay:[{amount_cents,…}], unread_messages:int, questionnaires_todo:[…], reminders:[…] }`. Chaque entrée porte un lien profond. Chargement visé < 2 s (`06` E3.3).

`POST /v1/appointments` — body : `{ provider_id, slot_id?, starts_at?, motif, on_behalf_of? }`. → `201 { appointment_id, status:"requested"|"confirmed" }`. Anti-double-booking = contrainte d'exclusion DB (`05` §5.4) → conflit = `409 slot_taken`. Confirmation auto (push+email). Délai d'annulation dépassé sur `cancel`/`PATCH` → `409 too_late`.

`GET /v1/appointments/{id}/preparation` → `{ provider:{name,…}, establishment:{ address, geo, access:{ door_code?, parking?, pmr? } }, bring:[{label, required}], reminder_at }`. La liste `bring` est **dérivée** (Vitale, carte mutuelle si `tiers_payant`, ordonnances/radios) — US-P32.

`GET /v1/appointments/{id}/directions?mode=car` → `{ mode, duration_min, distance_m, deeplink }`. **Calculé à la volée** (service routing EU), **non stocké** (`05` §10.7, `07` §2). Itinéraire détaillé = `deeplink` vers l'app carto.

`GET /v1/appointments/{id}/queue` → `{ position:int, est_wait_min:int, status }`. Mises à jour temps réel via WebSocket (§20). La file **informe**, ne trie pas cliniquement (`11` §8).

---

## 8. Patient — documents & coffre-fort (`documents`)

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/documents` | patient | Coffre-fort, `?category=&patient_account=`. |
| GET | `/v1/documents/{id}` | patient | Métadonnées + URL signée. |
| GET | `/v1/documents/{id}/download` | patient | Redirige vers l'URL signée expirante. |
| POST | `/v1/documents` | patient | Upload (pièce jointe / justificatif). |

`GET /v1/documents` → liste `{ id, category, filename, mime_type, created_at }`. Catégories : `devis, facture, ordonnance, radio, cbct, photo, cr, consigne, attestation, carte_mutuelle, passeport_implantaire, consentement, courrier`. Accès **audité** (`read_document`), URL **expirante**, intégrité `sha256` (`06` E3.5). Téléchargement → `302` vers Object Storage signé (`410` si lien expiré).

**Stockage des uploads utilisateur** (#7135 / #6894 / #6802) — `POST /v1/documents`, `POST /v1/account/coverage/card` et `POST /v1/cabinet/patients/{id}/documents` passent tous par le même chemin d'écriture (`api/src/upload_storage.rs::store_upload`) : les octets sont écrits dans l'`ObjectStorage` (Postgres `object_storage_blob` — servi par `GET /v1/storage/local/*key` sans `SCW_*`, Scaleway sinon) **avant** le `COMMIT` de la ligne `document`, sous une clé `coffre/<uuid>`, `carte-mutuelle/<uuid>` ou `dossier/<uuid>`. Un `201` garantit donc que `GET <download_url>` sert les octets d'origine (taille et `sha256` du `201`) ; échec d'écriture → `500`, aucune ligne `document` créée.

---

## 9. Patient — messagerie (`messaging`)

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/conversations` | patient | Mes fils par cabinet. |
| POST | `/v1/conversations` | patient | Démarrer un fil avec un cabinet. |
| GET | `/v1/conversations/{id}/messages` | patient | Messages (paginés). |
| POST | `/v1/conversations/{id}/messages` | patient | Envoyer (texte + pièces jointes). |
| POST | `/v1/conversations/{id}/read` | patient | Accusé de lecture. |

`POST /v1/conversations/{id}/messages` — body : `{ body, attachments?:[document_id] }`. → `201`. Le contenu est **chiffré** (`05` §5.6). Un **`triage_flag` (`normal\|urgent`)** est calculé par **règles mots-clés** — **priorisation visuelle uniquement, aucune décision clinique** (`06` E3.4, `07` §8.3). Notif au cabinet sans PII.

---

## 10. Wedge — devis, signature, paiement (`billing`)
> Le parcours monétisable, à la fluidité maximale (`01` §wedge, `06` WS5). Côté patient ci-dessous ; création côté pro en §16.

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/quotes` | patient | Mes devis (`?status=`). |
| GET | `/v1/quotes/{id}` | patient | Détail devis (lignes, reste à charge). |
| POST | `/v1/quotes/{id}/signature` | patient | Démarre la signature eIDAS (Yousign). |
| GET | `/v1/quotes/{id}/signature` | patient | Statut de signature. |
| GET | `/v1/invoices` | patient | Factures. |
| GET | `/v1/payments` | patient | Historique des règlements. |
| POST | `/v1/payments/intent` | patient | Crée un PaymentIntent (acompte/solde). |
| GET | `/v1/payment-schedules` | patient | Échéanciers (🎭/post-MVP). |

**Contrats clés** (idempotence requise — `Idempotency-Key`)

`POST /v1/quotes/{id}/signature` → `202 { signature_id, provider:"yousign", redirect_url|embed_token }`. Le résultat arrive par **webhook** (§21). Un devis **signé est immuable** : toute modif ultérieure → `409 quote_locked` (`06` E5.1, `07` §5.5).

`POST /v1/quotes/{id}/sign` (stub synchrone, app patient) → `200 { signed:true, signed_at }`. Devis déjà `signed` → `200` **idempotent** avec le `signed_at` existant ; `draft`/`refused`/`expired` → `409 invalid_status`.

**Règle « double-submit » (signatures, #7012/#6794/#7015)** : la transition de statut est **sérialisée en base** (`SELECT … FOR UPDATE` dans la transaction) — N appels simultanés sur le même objet produisent **exactement une** signature et **un** document dans le coffre-fort, et chaque perdant reçoit **la réponse déterministe d'un second appel séquentiel**, jamais un 5xx : `200` idempotent (`signed_at` existant) pour `POST /v1/quotes/{id}/sign`, `409 invalid_status` pour `POST /v1/cabinet/prescriptions/{id}/sign` (§17).

`POST /v1/payments/intent` — body : `{ quote_id, kind:"deposit"|"installment"|"full", amount_cents, method:"card"|"apple_pay"|"google_pay"|"sepa" }`. → `201 { payment_id, client_secret }` (Stripe ; SEPA via GoCardless). Confirmation finale par **webhook** ; statut `pending→paid|failed|refunded`. PCI délégué (`07` §6.1). Rejouable via la clé d'idempotence.

---

## 11. Parcours de soins patient (plan, passeport, suivi)

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/treatment-plans` | patient | Mes plans de traitement (🎭). |
| GET | `/v1/treatment-plans/{id}` | patient | Phases, actes faits/restants, coût, reste à charge. |
| GET | `/v1/implant-passport` | patient | Passeport implantaire (🎭). |
| GET | `/v1/implant-passport/export` | patient | Export PDF (URL signée). |
| GET | `/v1/reminders` | patient | Rappels de suivi/prévention. |
| GET | `/v1/cabinets/{id}/info` | patient/public | Infos pratiques d'un cabinet (US-P28). |

---

## 12. Marketplace — recherche, annuaire, réservation, avis
> Face découverte (`11`). Routes **publiques** (lecture annuaire) + réservation authentifiée. Recherche = **Meilisearch** (facettes) + **PostGIS** (géo).

### 12.1 Recherche & taxonomie
| Méthode | Chemin | Auth | Description |
|---|---|---|---|
| GET | `/v1/search/providers` | public | Recherche multi-axes + facettes + géo. |
| GET | `/v1/search/slots` | public | Recherche **slot-centrée** (« 1re dispo », US-P31). |
| GET | `/v1/search/suggest` | public | Autocomplete + **mapping besoin→spécialité** (suggestion, pas diagnostic). |
| GET | `/v1/professions` | public | Référentiel professions. |
| GET | `/v1/specialties` | public | Spécialités (`?profession_id=`). |
| GET | `/v1/acts` | public | Actes/motifs (`?specialty_id=`). |

`GET /v1/search/providers` — query : `q?`, `specialty?`, `near?=lat,lng` **ou** `place?` (géocodé), `radius_km?`, `bbox?` (carte), facettes `sector?`, `tiers_payant?`, `teleconsult?`, `pmr?`, `languages?`, `accepts_new?` (alias `accepts_new_patients?` — nom du champ écho en sortie, #6700), `available?=today|week`, `sort?=relevance|distance|next_slot|rating`, pagination. → `{ data:[{ provider_id, display_name, specialty, sector, distance_m?, next_slot_at?, rating_avg, geo, is_listed:true }], facets:{…}, page:{…} }`. **Seuls les `provider` `is_listed=true` (donc `rpps_verified`)** apparaissent (`05` §9.3, `07` §4.7). `place` → géocodage service EU.

`GET /v1/search/slots` — mêmes filtres + renvoie par praticien ses **prochains créneaux** : `{ data:[{ provider_id, display_name, distance_m, first_slot_at, slots:[{slot_id, starts_at}] }] }`. Trié par `first_slot_at`.

`GET /v1/search/suggest?q=mal de dent` → `{ specialties:[{id,label,score}], acts:[…] }`. **Garde-fou** : suggestion d'orientation, **jamais de diagnostic** (`07` §8, `11` §4).

### 12.2 Profil public & disponibilités
| Méthode | Chemin | Auth | Description |
|---|---|---|---|
| GET | `/v1/providers/{id}` | public | Profil public (spécialité vérifiée, tarifs, actes, langues, bio, avis agrégés). |
| GET | `/v1/providers/{id}/availability` | public | Créneaux ouverts (`?from=&to=&motif=`). |
| GET | `/v1/establishments/{id}` | public | Établissement (adresse, mini-carte, accès). |

`GET /v1/providers/{id}/availability` → `{ data:[{ slot_id, starts_at, ends_at, motif? }] }` (projection `availability_slot` status `open`). Réserver via §12.3.

### 12.3 Réservation cross-provider (`booking`)
| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| POST | `/v1/bookings` | patient | Réserver chez n'importe quel praticien (motif→créneau→confirm). |
| POST | `/v1/slots/{id}/hold` | patient | Pose une **réservation temporaire** (anti-concurrence). |

`POST /v1/slots/{id}/hold` → `200 { hold_token, expires_at }` (passe le slot en `held` **10 min**). **Hold expiré** (#6992/#6840) : passé `expires_at`, le créneau est de nouveau réservable — il **réapparaît** dans `/v1/search/slots` et `/v1/providers/{id}/availability` (filtre `expires_at` dans la requête, fonction `slot_hold_expired`), un autre patient peut le tenir, et un reaper périodique (60 s, `release_expired_slot_holds()`) purge le hold et repasse le slot en `open`. Un hold **actif** reste bloquant (`409 slot_taken` pour un autre patient). `POST /v1/bookings` — body : `{ slot_id, hold_token?, motif, on_behalf_of?, new_patient_info? }`, **`Idempotency-Key`**. → `201 { appointment_id }`. Crée l'`appointment` chez le praticien (tenant) **et** le rattache à l'espace patient global. Conflit/hold expiré → `409`. Pré-check-in proposé.

### 12.4 Avis (`reviews`)
| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/providers/{id}/reviews` | public | Avis **publiés** (note + commentaire). |
| POST | `/v1/reviews` | patient | Déposer un avis (rattaché à un **RDV réel**). |

`POST /v1/reviews` — body : `{ appointment_id, rating:1..5, comment? }`. → `201 { review_id, status:"pending" }`. **Anti-faux-avis** : l'`appointment_id` doit appartenir au demandeur et être passé/honoré. **Modération** avant publication ; transparence du tri, droit de réponse (`11` §10, `07` §13).

---

## 13. Back-office — agenda & salle d'attente (`scheduling`)
> Espace pro, cabinet-scoped (RLS). Cloisonnement : le secrétariat gère l'administratif, pas le clinique.

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/cabinet/agenda` | pro | Agenda `?view=day\|week&practitioner_id=&date=`. |
| GET | `/v1/cabinet/appointments` | pro | RDV du cabinet (`?status=&date=`). |
| POST | `/v1/cabinet/appointments/{id}/confirm` | pro | Valider une demande (`requested→confirmed`). |
| POST | `/v1/cabinet/appointments/{id}/checkin` | secretary+ | Enregistrer l'arrivée au comptoir (`confirmed→checked_in`, mode `manual`). Fenêtre temporelle ci-dessous. |
| POST | `/v1/cabinet/appointments/{id}/no-show` | secretary+ | Marquer un RDV manqué (`requested\|confirmed\|checked_in\|in_progress→no_show`) ; `409 too_early` avant `starts_at` pour un patient jamais présenté. |
| POST | `/v1/cabinet/appointments/{id}/cancel` | secretary+ | Annulation cabinet (X12, #6953/#7011) : `{reason?}` ; `requested\|confirmed→cancelled` (créneau libéré, patient notifié `appointment_cancelled`, audit) ; `checked_in→no_show` (patient déjà vu). Sans garde temporelle (un RDV passé jamais clôturé reste annulable). `409 invalid_status` sinon ; `404` hors cabinet/secrétariat. |
| PATCH | `/v1/cabinet/appointments/{id}` | secretary+ | Déplacer/éditer (transition auditée). `status:"no_show"` (RDV commencé, sinon `409 too_early`) ou `status:"cancelled"` (même transition que `…/cancel`, `motif` = motif d'annulation) ; toute autre valeur → `422`. |
| POST | `/v1/cabinet/slots` | pro | Ouvrir/bloquer un créneau. |
| PATCH/DELETE | `/v1/cabinet/slots/{id}` | pro | Éditer/supprimer un créneau. |
| PUT | `/v1/cabinet/slots/{id}/online` | pro | Exposer le créneau à la réservation en ligne (US-M19). |
| GET | `/v1/cabinet/waiting-room` | pro | File en temps réel (+ WS §20). |
| POST | `/v1/cabinet/waiting-room/call-next` | pro | Appeler le patient suivant (notifie « c'est à vous »). |
| GET | `/v1/cabinet/waiting-list` | secretary+ | Liste d'attente / combler un trou (🎭). |
| POST | `/v1/cabinet/waiting-list/{id}/offer` | secretary+ | Proposer un créneau libéré. |

`GET /v1/cabinet/agenda` → `{ practitioners:[…], slots:[{ id, practitioner_id, starts_at, ends_at, status, patient?:{display}, motif }] }`. Le secrétariat voit le **motif administratif**, pas le contenu clinique. Anti-double-booking via contrainte d'exclusion (`05` §5.4).

**Gardes temporelles du cycle de vie d'un RDV** (#6770, #6912, #6875 — code : `api/src/appointment_time_guards.rs`). Un RDV ne peut être « honoré » que le jour de son créneau ; les trois modes de check-in (QR, app, manuel comptoir) passent par la même famille de gardes. Trop tôt → `409 {"code":"too_early"}`, trop tard → `409 {"code":"out_of_window"}`.

| Action | Fenêtre | Note |
|---|---|---|
| `POST /v1/appointments/{id}/checkin` (patient, QR ou app) | `starts_at − 60 min ≤ now ≤ starts_at + 60 min` | Inchangée (#3844). |
| `POST /v1/cabinet/appointments/{id}/checkin` (comptoir) | `starts_at − 2 h ≤ now ≤ ends_at + 1 h` | Le secrétariat constate une présence physique : plus de latitude que le patient (avance, retardataire), mais jamais un RDV de demain ni de 2027. Fenêtre incluse dans celle de la file (`now() ± 1 jour`) : un `checked_in` est toujours visible de la salle d'attente, de `call-next` et de la queue patient. |
| `POST /v1/cabinet/appointments/{id}/start` | depuis `confirmed` : `starts_at ± 60 min` ; depuis `checked_in`/`in_progress` : `now ≥ starts_at − 2 h` | S'applique **quel que soit** le statut d'entrée — avant, un `checked_in` obtenu hors fenêtre suffisait à ouvrir puis clôturer une séance sur un RDV futur (#6770). |
| `POST /v1/cabinet/consultations/{id}/complete` | aucune borne sur `starts_at` | La séance n'existe que via `start` ; clôturer avant l'heure du créneau un patient arrivé en avance est un cas normal (#6875), le RDV `done` tombe alors dans `filter=history`. |
| `POST /v1/cabinet/appointments/{id}/no-show` | `requested`/`confirmed` : `now ≥ starts_at` | `checked_in`/`in_progress` (patient venu puis parti) exemptés (#4396). |

---

## 14. Back-office — patients & clinique (`clinical`)
> ⚠️ **Cloisonnement R.4127-72** : les routes cliniques (note, journal, odontogramme, medical_record) sont **`practitioner` only** → `403` pour `secretary` (`07` §4.1). Les routes « fiche administrative » sont accessibles au secrétariat.

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/cabinet/patients` | pro | Index des dossiers (`?q=&filter=in_treatment\|to_review`). |
| POST | `/v1/cabinet/patients` | pro | Créer/rattacher un dossier patient (lie un `patient_account`). |
| GET | `/v1/cabinet/patients/{id}` | pro | Fiche — **vue selon rôle** (admin vs clinique). |
| GET | `/v1/cabinet/patients/{id}/medical-record` | **practitioner** | Antécédents/allergies/traitements (déchiffré). |
| PATCH | `/v1/cabinet/patients/{id}/medical-record` | **practitioner** | MAJ antécédents/allergies. |
| GET | `/v1/cabinet/patients/{id}/dental-chart` | **practitioner** | Odontogramme (état par dent). |
| PUT | `/v1/cabinet/patients/{id}/dental-chart` | **practitioner** | MAJ odontogramme. |
| GET | `/v1/cabinet/patients/{id}/notes` | **practitioner** | Journal clinique (timeline). |
| POST | `/v1/cabinet/patients/{id}/notes` | **practitioner** | Ajouter une note (globale ou liée à un acte/dent). |
| GET | `/v1/cabinet/patients/{id}/documents` | pro | Documents du dossier (admin voit l'administratif). |
| POST | `/v1/cabinet/patients/{id}/documents` | pro | Ajouter une pièce (upload audité). |

**Contrats clés**

`GET /v1/cabinet/patients/{id}` → fiche dont les **sections cliniques sont omises pour `secretary`** (et l'UI affiche « dossier clinique masqué »). L'accès clinique d'un praticien est **audité** (`read_record`).

`GET`/`PATCH /v1/cabinet/patients/{id}/medical-record` et `GET /v1/cabinet/consultations/{id}` → `medical_alerts[]` : `{ kind:"allergie"|"medico_legal", label, severity? }` — pastilles d'alerte des en-têtes fiche patient et fauteuil, **même calcul** sur les deux routes (`record_medical_alerts`, #4974/#6917). Une entrée `allergie` par élément lisible de `allergies[]`, quelle que soit sa forme (`"…"`, `{substance,severity?}`, `{text,source:"questionnaire_patient"}` importé du questionnaire, `{name}`/`{label}`) ; `severity` (minuscules, ex. `high`) n'est présent que si l'entrée en porte une, les `high` sont listées en tête ; puis un `medico_legal` par flag à `true`. Affichage passif uniquement (pas de contrôle d'interaction — non-dispositif médical). Le questionnaire patient accepte `allergies`/`traitements_en_cours` en texte libre, liste ou objets.

`POST /v1/cabinet/patients/{id}/notes` — body : `{ note_kind:"observation"|"act", text, tooth?, act_ref?:{ label, ccam?, quote_item_id? } }`. → `201`. Contenu **chiffré**, **horodaté**, **signé** (`author_id`), `practitioner` only (US-D12, `05` §10.3). Pas de suppression dure (soft-delete médical).

**Courriers types (#7197, parité Dental Pilot F7.a)** — `secretary`/`practitioner`/`admin`.

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/letter-templates` | pro | Modèles visibles : globaux seedés (`is_global:true`, lecture seule — convocation, relance, courrier confrère, attestation de présence) + ceux du cabinet. `{ id, name, kind, body_template, is_global, placeholders[], created_at }`. |
| POST | `/v1/letter-templates` | pro | `{ name, kind, body_template }` → `201 { template_id, placeholders[] }`. `kind` ∈ `convocation, relance, courrier_confrere, attestation, autre`. |
| POST | `/v1/patients/{id}/letters` | pro | `{ template_id, correspondent_id?, overrides? }` → `201 { document_id, filename, size_bytes, body }` : rend le modèle, produit le PDF (en-tête/pied cabinet + RPPS, pagination) et le stocke en **document patient** `category='courrier'` (audit `generate_letter`). |

Placeholders reconnus (`{{nom}}`, espaces internes tolérés) : `patient.prenom`, `patient.nom`, `patient.date_naissance` (JJ/MM/AAAA), `cabinet.nom`, `cabinet.adresse` (`settings.address`), `cabinet.telephone` (`settings.contact.phone`), `praticien.nom`, `praticien.rpps` (praticien appelant si `practitioner`, sinon celui du RDV), `rdv.date`, `rdv.heure` (heure Paris ; prochain RDV non annulé, sinon le dernier passé), `date.aujourdhui`, `correspondant.nom` (uniquement via `overrides` pour l'instant). `overrides` : `{ "rdv.date": "12/10/2026", … }`, prime sur les valeurs résolues.

Erreurs : placeholder inconnu dans le modèle ou clé d'`overrides` inconnue → `422 { code:"unknown_placeholders", placeholders:[…] }` ; placeholder connu sans valeur ni override → `422 { code:"missing_placeholder_values", placeholders:[…] }` (jamais de courrier rendu avec un trou) ; `{{` non fermé → `422 validation_error` ; `correspondent_id` fourni → `501 { code:"correspondent_not_supported" }` (aucune entité correspondant cabinet encore, cf. issue dédiée) ; patient ou modèle hors cabinet → `404`.

---

## 15. Back-office — consultation au fauteuil
> Le cœur clinique (US-D09, `06` E4.7). `practitioner` only.

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| POST | `/v1/cabinet/appointments/{id}/start` | practitioner | Démarre la séance (`appointment→in_progress`). |
| GET | `/v1/ccam/acts` | practitioner | Référentiel CCAM (actes dentaires), recherche `?q=` code/libellé (accent-insensible). |
| GET | `/v1/cabinet/consultations` | practitioner | Historique des séances du cabinet (filtres `patient_id`, `status` ; tri `started_at` desc ; `limit` ≤ 100). Sans note clinique. |
| GET | `/v1/cabinet/consultations/{id}` | practitioner | Contexte clinique de la séance. |
| POST | `/v1/cabinet/consultations/{id}/acts` | practitioner | Ajouter un acte **CCAM** réalisé. |
| DELETE | `/v1/cabinet/consultations/{id}/acts/{actId}` | practitioner | Retirer un acte non finalisé. |
| PUT | `/v1/cabinet/consultations/{id}/note` | practitioner | Note de séance (chiffrée). |
| POST | `/v1/cabinet/consultations/{id}/complete` | practitioner | **Terminer & facturer** (génère devis/facture, étape suivante). |

`POST …/acts` — body : `{ ccam_code, label, tooth?, amount_cents?, included?:bool }`. → `201`. Alimente `clinical_note.ccam_codes` + le devis/plan. `POST …/complete` → `200 { invoice_id?, next_step? }` : clôt la séance, déclenche la facturation, propose l'étape suivante du plan.

---

## 16. Back-office — plan de traitement & devis
> US-D10 + `06` E4.3/E5.1. `practitioner` crée le clinique ; le devis est partagé avec le patient (§10).

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/cabinet/treatment-plans` | practitioner | Plans du cabinet. |
| POST | `/v1/cabinet/treatment-plans` | practitioner | Créer un plan (phases). |
| POST | `/v1/cabinet/treatment-plans/{id}/phases` | practitioner | Ajouter une phase. |
| GET | `/v1/cabinet/patients/{id}/orthodontics` | practitioner | Traitements orthodontiques du patient, étapes triées par `step_number` (#4135). |
| POST | `/v1/cabinet/patients/{id}/orthodontics` | practitioner | Créer un traitement orthodontique. |
| POST | `/v1/cabinet/orthodontics/{id}/steps` | practitioner | Ajouter une étape (`bague`/`contention`/`gouttiere`). |
| GET | `/v1/cabinet/quotes` | pro | Suivi devis & paiements (`?status=`, `?overdue=true` #4130, relances). |
| POST | `/v1/cabinet/quotes` | practitioner | Créer un devis (lignes CCAM, AMO/AMC, dent). |
| PATCH | `/v1/cabinet/quotes/{id}` | practitioner | Éditer tant que **non signé** (versioning). |
| POST | `/v1/cabinet/quotes/{id}/send` | practitioner | Envoyer au patient pour signature. |
| GET | `/v1/cabinet/quotes/{id}` | pro | Statut signature/paiement. |
| POST | `/v1/cabinet/quotes/{id}/remind` | pro | Relancer (acompte/signature). |

`POST /v1/cabinet/quotes` — body : `{ patient_id, plan_id?, items:[{ label, ccam_code?, tooth?, qty, unit_amount_cents, amo_part_cents?, amc_part_cents? }], deposit_pct? }`. → `201`. **Reste à charge** = calculé (`unit_amount − amo − amc`). Un devis **signé** : `PATCH`/`send` → `409 quote_locked` (`06` E5.1).

---

## 16bis. Back-office — inventaire cabinet (`stock_item`/`stock_movement`, #4143/#4144)
> Tâche opérationnelle du cabinet, pas une décision clinique — `secretary+` (practitioner/admin/manager également autorisés).

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/cabinet/stock-items` | secretary+ | Articles d'inventaire du cabinet, par référence. |
| POST | `/v1/cabinet/stock-items` | secretary+ | Créer un article (`quantity_on_hand` démarre à 0). |
| POST | `/v1/cabinet/stock-items/{id}/movements` | secretary+ | Mouvement (`reception`/`consumption`/`adjustment`/`peremption`) — met à jour `quantity_on_hand` atomiquement. |

`POST /v1/cabinet/stock-items` — body : `{ reference, label, unit, alert_threshold? }`. → `201 { item_id }`. `reference` déjà utilisée dans ce cabinet → `409 stock_reference_already_used`.
`POST /v1/cabinet/stock-items/{id}/movements` — body : `{ delta, reason, expiry_date?, consultation_act_id? }`. → `201 { movement_id, quantity_on_hand }`. Article/acte hors tenant → `404`.

### 16ter. Stérilisation — étiquettes & usage par scan (`sterilization_cycle`/`sterilized_pouch`, #4138, DP-F13.a #7181)
> Même garde `secretary+` que l'inventaire. Cycles et sachets : `GET/POST /v1/cabinet/sterilization-cycles`, `GET/POST /v1/cabinet/sterilization-cycles/{id}/pouches` (#4138).

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/sterilization/cycles/{id}/labels.pdf` | secretary+ | Planche d'étiquettes du cycle (une par sachet, 2 colonnes × 7 lignes / A4, gabarit Avery L7163) : code, cycle, date de stérilisation, péremption, QR encodant le code. |
| POST | `/v1/sterilization/pouches/{code}/use` | secretary+ | Rattacher un sachet scanné à un patient (et une séance), idempotent. |

`GET /v1/sterilization/cycles/{id}/labels.pdf` — `?shelf_life_days=` (défaut **180**, max 730) fixe la péremption (`started_at + N jours`) → `422` hors bornes. → `200 application/pdf` (`Content-Disposition: inline`), 14 étiquettes par page ; cycle sans sachet → 1 page « Aucun sachet » ; cycle `non_conforme` → mention « CYCLE NON CONFORME » sur chaque étiquette. Cycle hors tenant → `404`.
`POST /v1/sterilization/pouches/{code}/use` — body : `{ patient_id, consultation_id? }`. → `200 { pouch_id, code, cycle_id, patient_id, consultation_id?, used_at, already_used }`. Code/patient/séance hors tenant → `404` ; séance d'un autre patient → `422`. Rejeu même patient + même séance → `200 already_used:true` sans écriture (séance absente au premier scan puis fournie → complétée). Sachet déjà utilisé sur un autre patient → `409 pouch_already_used`. Chaque première utilisation est tracée dans `audit_log` (`use_sterilized_pouch`).

---

## 17. Back-office — ordonnance (`prescription`)
> US-D11, `06` E4.8. `practitioner` only. 🚨 **Hors dispositif médical (MDR, `07` §8.6).**

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/cabinet/prescriptions` | practitioner | Ordonnances du praticien. |
| POST | `/v1/cabinet/prescriptions` | practitioner | Créer (lignes médicament). |
| PATCH | `/v1/cabinet/prescriptions/{id}` | practitioner | Éditer (brouillon). |
| POST | `/v1/cabinet/prescriptions/{id}/sign` | practitioner | Signer (eIDAS) → PDF coffre-fort. |
| POST | `/v1/cabinet/prescriptions/{id}/send` | practitioner | Envoyer (pharmacie au choix du patient). |
| POST | `/v1/cabinet/prescriptions/{id}/renew` | practitioner | Renouveler (#4131) : copie les lignes dans un nouveau brouillon. |

`POST /v1/cabinet/prescriptions` — body : `{ patient_id, items:[{ label, form?, posology, duration, quantity }] }`. → `201`.
> 🚨 **L'API n'effectue AUCUN contrôle automatique** d'allergies/interactions/contre-indications et **ne suggère aucune alternative** (= aide à la décision = dispositif médical, **exclu**). Elle peut **afficher** en lecture les allergies que le praticien a saisies dans `medical_record`. Le praticien décide seul. `/sign` réutilise la brique signature du wedge ; `/send` génère un `document(category='ordonnance')`.

`POST /v1/cabinet/prescriptions/{id}/sign` → `200 { signed_at, document_id }` ; ordonnance non `draft` → `409 invalid_status`. Appels **concurrents** (double-clic, deux onglets) : sérialisés par `FOR UPDATE` — une seule signature eIDAS et un seul PDF émis, les perdants reçoivent `409 invalid_status` (règle « double-submit », §10).

---

## 18. Back-office — messagerie priorisée
| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/cabinet/conversations` | pro | File priorisée (urgents en tête via `triage_flag`). |
| GET | `/v1/cabinet/conversations/{id}/messages` | pro | Fil. |
| POST | `/v1/cabinet/conversations/{id}/messages` | pro | Répondre. |
| POST | `/v1/cabinet/conversations/{id}/convert-to-appointment` | pro | Convertir en RDV en 1 clic (US-S07). |

Cloisonnement : un fil clinique escaladé n'est lisible que par le `practitioner` ; le tri `urgent` reste une **priorisation visuelle** (`07` §8.3).

---

## 19. Notifications & devices

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| POST | `/v1/devices` | oui | Enregistrer un token FCM (push). |
| DELETE | `/v1/devices/{id}` | oui | Désenregistrer. |
| GET | `/v1/notifications` | oui | Centre de notifications. |
| POST | `/v1/notifications/{id}/read` | oui | Marquer lue. |
| GET | `/v1/me/notification-preferences` | oui | Préférences notif. du porteur du token (patient, pro, pharma, nurse). |
| PATCH | `/v1/me/notification-preferences` | oui | MAJ opt-in par catégorie/canal (partiel). |

`POST /v1/devices` — body : `{ fcm_token, platform:"ios"|"android"|"web" }`. → `201`. ⚠️ **Payload push sans PII** (`06` E3.7, `07` §2.7) : le contenu réel se charge **authentifié** après ouverture. Types : RDV à venir/modifié/annulé, document à signer, nouveau message, paiement en attente, « c'est bientôt à vous ».

`GET /v1/me/notification-preferences` → `{ inapp_rdv, inapp_messagerie, inapp_devis, inapp_stock, inapp_labo, inapp_visites, email_rdv, email_messagerie, email_devis }` (booléens). Distinct de `/v1/account/notification-preferences` (§6, patient uniquement) : keyed par `app_user_id`, ouvert à tout user authentifié — pro/pharma/nurse inclus (#6257). Défaut avant toute écriture : in-app `true`, email `false`. `PATCH` partiel : seules les clés envoyées sont modifiées (`deny_unknown_fields`, 422 sur clé inconnue). RBAC : RLS scopée par `app.current_user_id`, un user ne lit/écrit que ses propres préférences.

---

## 20. Temps réel (WebSocket)
> Axum/Tokio natif, fan-out **pub/sub Redis** multi-instances (`04` ADR-005, `03`). ⚠️ Sur une connexion longue durée, **réinjecter le contexte tenant/RLS à chaque opération DB** (`05` §2).

- **Endpoint** : `GET /v1/ws` (upgrade WebSocket). Auth par le **même JWT** (query `?access_token=` ou header au handshake). Le `cabinet_id`/`account_id` du token borne les abonnements.
- **Souscription** (message client) : `{ "op":"subscribe", "channel":"waiting_room", "params":{…} }`. `unsubscribe` symétrique. Ping/pong applicatif pour le keep-alive.

| Canal | Public | Événements |
|---|---|---|
| `waiting_room` | pro (cabinet) | `queue_updated`, `patient_called`, `checked_in` |
| `patient_queue:{appointment_id}` | patient | `position_updated`, `your_turn_soon`, `your_turn` |
| `agenda:{practitioner_id}` | pro | `appointment_created\|updated\|moved\|cancelled` |
| `conversation:{id}` | patient/pro | `message_created`, `read` |
| `teleconsult:{appointment_id}` | patient/pro | `room_ready`, `started`, `ended` |

**Enveloppe serveur** : `{ "channel":"…", "event":"…", "data":{…}, "ts":"…" }`. Autorisation par canal vérifiée (RLS + RBAC + propriété). La file **informe**, ne trie pas cliniquement (`11` §8).

---

## 21. Webhooks entrants (prestataires)
> Endpoints **non authentifiés par JWT** mais **vérifiés par signature** du prestataire, et **idempotents** (`07` §6.3, §5).

| Méthode | Chemin | Source | Effet |
|---|---|---|---|
| POST | `/v1/webhooks/yousign` | Yousign | Signature complétée → fige le devis/ordonnance (`signed_at`, `sha256`), notifie. |
| POST | `/v1/webhooks/stripe` | Stripe | PaymentIntent `succeeded/failed` → MAJ `payment.status`, facture. |
| POST | `/v1/webhooks/gocardless` | GoCardless | Mandat/prélèvement SEPA → MAJ paiement. |

Règles : vérifier la **signature** (rejet `400` sinon), traiter de façon **idempotente** (clé = id d'événement prestataire), répondre `200` vite (traitement lourd → job apalis). Aucune confiance dans le payload sans vérif.

---

## 22. Pharmacie — tenant, annuaire & click-and-collect (`pharmacy`)
> Épic #3323. La pharmacie est un **tenant dédié** (tables `pharmacy` + `pharmacy_membership`, GUC RLS `app.current_pharmacy_id`, JWT `kind:"pharma"`, rôles `pharmacist`/`preparator`/`admin`) — cloisonnement structurel vis-à-vis des cabinets (`07` §4) : un token pharma est rejeté (403) par tout endpoint `/v1/cabinet/*`, et réciproquement. Login commun (§3) puis `POST /v1/auth/select-pharmacy-context`.

| Méthode | Chemin | Auth | Description |
|---|---|---|---|
| GET | `/v1/pharmacies` | — | Annuaire public des pharmacies **listées** (`is_listed`). Filtres : `q`, `lat`+`lng` (tri distance PostGIS), `radius_km`, `per_page`. → `{ data:[{ id, raison_sociale, address, phone, distance_m? }] }`. `422` si `lat`/`lng` incomplets ou `radius_km` sans point. |
| GET | `/v1/account/pharmacy` | patient | Pharmacie déclarée du patient. `204` si aucune. |
| PUT | `/v1/account/pharmacy` | patient | Déclare la pharmacie (`{ pharmacy_id }`). `404` si inconnue/non listée. |
| GET | `/v1/cabinet/patients/{id}/pharmacy` | pro | Pharmacie déclarée d'un patient (présélection à l'envoi). `204` si aucune, `404` patient hors cabinet. |
| POST | `/v1/cabinet/prescriptions/{id}/send` | practitioner | Envoie l'ordonnance **signée** à une pharmacie (`{ pharmacy_id, consent_channel? }`) → `201` commande `received`, prescription → `sent`, consentement tracé. `409` non signée ou commande active existante, `404` pharmacie, `422` patient sans compte app. |
| GET | `/v1/account/prescriptions` | patient | Ordonnances visibles par le compte (policy 0109) → `{ data:[{ id, status, document_id?, created_at, signed_at? }] }` — fournit les ids pour l'envoi en pharmacie. |
| POST | `/v1/account/prescriptions/{id}/order` | patient | Le patient transmet son ordonnance (`{ pharmacy_id }`) → `201` commande `received`. Mêmes erreurs que `/send`. |
| GET | `/v1/account/orders` · `/{id}` | patient | Suivi des commandes du patient. |
| GET | `/v1/pharmacy/orders?status=` · `/{id}` | pharma | File des commandes de la pharmacie (RLS pharmacy-scoped, `404` hors tenant). |
| GET | `/v1/pharmacy/orders/{id}/document` | pharma | URL signée du PDF d'ordonnance (policy `document_pharmacy_read` — la pharmacie ne lit jamais les tables cliniques). `410` si lien expiré. |
| POST | `/v1/pharmacy/orders/{id}/accept` | pharma | `received → preparing`. `404` hors tenant, `409` statut. |
| POST | `/v1/pharmacy/orders/{id}/ready` | pharma | `preparing → ready`. `404`/`409`. |
| POST | `/v1/pharmacy/orders/{id}/reject` | pharmacist/admin | `received → rejected` (`{ reason }` obligatoire → `422` si vide). `preparator` → `403`. |
| POST | `/v1/pharmacy/orders/pickup-scan` | pharma | `ready → picked_up` via le token du QR (`{ token }`) — endpoint **par token**, le scanner ne connaît que le QR. `404` token inconnu/autre pharmacie (anti-énumération), `409` statut (double scan compris), `410` expiré. Single-use. |
| POST | `/v1/account/orders/{id}/cancel` | patient | `received|preparing → cancelled`. `409` si prête ou terminale. |
| GET | `/v1/account/orders/{id}/pickup-token` | patient | Token opaque du QR de retrait (~244 bits, **zéro PII/id métier**, seul le hash SHA-256 est stocké). Uniquement si `ready` (`409` sinon), expire à 24 h, chaque appel régénère et invalide le précédent. → `{ token, expires_at }`. |

**Commande** (`OrderDto`) : `{ id, pharmacy_id, pharmacy_name, patient_display_name, prescription_id, status, rejection_reason?, received_at, updated_at, ready_at?, picked_up_at? }`. `patient_display_name` est **minimisé** (« Prénom N. », `07` §2.7). Statuts : `received → preparing → ready → picked_up` + `rejected` (pharmacien, motif requis) et `cancelled` (patient) — une seule commande **active** par ordonnance. Consentement au partage tracé dans `consent_record` (purpose `partage_pharmacie`, evidence `{channel, collected_by?}`).

**Temps réel & notifications (lot B4)** : chaque transition insère une notification in-app (`notification`, kinds `order_received` pour le staff pharmacie, `order_status_changed` pour le patient — titre générique **sans PII**, `data {order_id, status}` en deeplink), enfile un push FCM (`JobDispatcher::enqueue_push_notification`, payload sans PII) et publie sur les canaux WS `pharmacy_orders:<pharmacy_id>` (subscribe réservé au staff `kind:"pharma"` du tenant) et `account_orders:<patient_account_id>` (patient titulaire) — enveloppe `{event:"order_status_changed", data:{order_id, status}}`.

**Demandes de stock (lot B5)** : `stock_request` cabinet → pharmacie, items jsonb `[{label, qty, note?}]` — **jamais de donnée patient**. Cycle `sent → accepted|rejected → fulfilled` (+ `cancelled` cabinet tant que `sent`). Routes : `GET|POST /v1/cabinet/stock-requests`, `POST …/{id}/cancel` (secretary+) ; `GET /v1/pharmacy/stock-requests`, `POST …/{id}/accept|reject|fulfill` (staff pharmacie ; `reject` accepte `{note?}`). Transitions illégales → 409. Le staff est notifié (`stock_request_received`).

**Messagerie patient ↔ pharmacie (lot B6)** : `conversation`/`message` généralisés (scope `patient_pharmacy`, ancre `pharmacy_id`, `sender_kind='pharmacist'`, nom patient minimisé dénormalisé). Cloisonnement triadique préservé : un cabinet ne voit jamais un fil pharmacie et réciproquement (pgTAP). Patient : `POST /v1/conversations {pharmacy_id, subject?}` (XOR `cabinet_id`, 422 sinon), puis fils/messages/read habituels (`cabinet_id` null → sentinel nil, nom du destinataire = pharmacie). Pharmacie : `GET /v1/pharmacy/conversations`, `GET|POST …/{id}/messages`, `POST …/{id}/read` — mêmes formes JSON que `/v1/cabinet/*`, `triage_flag` forcé `normal` (la priorisation d'urgence reste un outil cabinet). Canal WS `conversation:<id>` étendu au `kind:"pharma"`.

**Devis d'officine (lot B7)** : `pharmacy_quote` — produits + prix TTC en **centimes**, rattaché à une commande (`order_id`), volontairement distinct du devis dentaire `quote` (CCAM/AMO/AMC, eIDAS). Cycle `draft → sent → accepted|refused` (+ `expired`). Pharmacie : `GET|POST /v1/pharmacy/quotes` (création par `pharmacist`/`admin`, total calculé serveur), `POST …/{id}/send` (notifie le patient sans PII + WS). Patient : `GET /v1/account/pharmacy-quotes` (**jamais les brouillons**, RLS), `POST …/{id}/accept|refuse` (décision définitive — un devis décidé n'est plus modifiable, ni par le patient ni par la pharmacie).

---

## 23. Interopérabilité — FHIR R4 & HL7 v2 (partenaires externes)
> Chantier interop façon Doctolib (ADR-012, `04-architecture.md`) : synchro agenda, annuaire, référentiel patient pour des EAI (Enovacom, Cloverleaf) ou un SIH. Deux protocoles, une même couche de service. Issues Forgejo #3912-#3930.

### 23.1 Authentification partenaire (REST FHIR)
`POST /v1/interop/oauth/token` — grant `client_credentials` (RFC 6749 §4.4, corps `application/x-www-form-urlencoded`). Réponse et erreurs au format **RFC 6749** (`{"access_token":...}` / `{"error":"invalid_client"}`), volontairement distinct du contrat RFC 9457 du reste de l'API. Token JWT `aud:"interop"`, durée de vie 15 min, scopes : `directory:read`, `slots:read`, `patients:read`, `appointments:read`, `appointments:write`, `subscriptions:write`. Un scope demandé hors du périmètre accordé au client → `invalid_scope` (jamais d'octroi partiel silencieux). Provisioning des clients (`interop_client`/`interop_client_secret`, rotation, révocation) : hors API publique pour l'instant, opération d'administration côté cabinet à définir dans un lot ultérieur.

### 23.2 Base FHIR R4
Toutes les ressources sous `/v1/interop/fhir/...` (le `/v1` respecte la règle de versionnement du reste de l'API ; `/v1/interop/fhir` est la base FHIR déclarée dans le `CapabilityStatement`, `GET /v1/interop/fhir/metadata`). Réponses `application/fhir+json`. Erreurs métier en `OperationOutcome` FHIR (404 `not-found`, 409 `conflict`, 422 `business-rule`/`invalid`, 403 `forbidden` sur scope insuffisant) — distinct du RFC 6749 de §23.1 et du RFC 9457 du reste de l'API. Chaque lecture/écriture est scopée au `cabinet_id` du token (RLS **et** filtre explicite dans la requête — certaines tables source, ex. `establishment`/`practitioner`, n'ont aucune policy RLS propre, cf. `05`).

| Ressource | Méthode/Chemin | Scope | Notes |
|---|---|---|---|
| `Practitioner` | `GET .../Practitioner/{id}` · `GET .../Practitioner` | `directory:read` | Liste = praticiens du cabinet du token uniquement. |
| `Organization` | `GET .../Organization/{id}` | `directory:read` | `{id}` doit être le `cabinet_id` du token — jamais un autre cabinet même si l'UUID existe. |
| `Location` | `GET .../Location/{id}` | `directory:read` | `establishment`, isolé par jointure `provider.cabinet_id` (pas de RLS propre à `establishment`). |
| `Slot` | `GET .../Slot/{id}` · `GET .../Slot?from=&to=` | `slots:read` | Lecture seule. Réservation = `Appointment`, pas d'écriture directe sur `Slot` dans cette tranche. Statuts `availability_slot` → FHIR : `open→free`, `held→busy-tentative`, `booked→busy`, `blocked→busy-unavailable`. |
| `Schedule` | `GET .../Schedule/{id}` | `slots:read` | Représentation minimale (`id` = `practitioner_id`, `actor` → `Practitioner`). |
| `Appointment` | `GET .../Appointment/{id}` · `GET .../Appointment?patient=&practitioner=&date_from=&date_to=` · `POST .../Appointment` · `PATCH .../Appointment/{id}` | `appointments:read` / `appointments:write` | Cœur de la synchro RDV. `POST` : `Idempotency-Key` **obligatoire** (clé rejouée avec une charge différente → `409`), patient/praticien référencés doivent déjà exister dans ce cabinet (pas de création à la volée — c'est `Patient`, hors scope actuel), statut initial `confirmed` (un partenaire qui pousse un RDV affirme une réservation actée, pas une demande — différent du flux patient qui démarre à `requested`). Chevauchement (contrainte DB `appointment_no_overlap`) → `409 conflict`. `PATCH` : changement de statut uniquement, matrice de transitions légales stricte (`done`/`cancelled`/`no_show` sont terminaux). Mapping statut interne → FHIR : `requested→pending`, `confirmed→booked`, `checked_in→checked-in`, `in_progress→arrived` (R4 n'a pas de valeur dédiée), `done→fulfilled`, `cancelled→cancelled`, `no_show→noshow`. |
| `Subscription` | `POST .../Subscription` · `GET .../Subscription/{id}` | `subscriptions:write` | Rest-hook : le partenaire s'abonne à un type de ressource (ex. `Appointment`) sur un `endpoint_url`. Secret HMAC retourné **une seule fois** à la création (`X-Nubia-Signature: sha256=...` sur chaque callback). Payload de notification minimal (type + id + cabinet) — le partenaire re-`GET` la ressource complète avec son propre token s'il en a besoin. |

**Non implémenté dans cette tranche** (voir `07-conformite.md` §9 et le backlog de suivi) : `Patient` (recherche/lecture par INS — bloqué sur `api/crates/core/crypto`, encore un scaffold non implémenté au moment de ces lots), rapprochement/dédoublonnage (`patient_merge_candidate`), écriture `Slot`.

### 23.3 HL7 v2 / MLLP
Listener MLLP dédié (port `2575` par défaut), TLS mutuel obligatoire (empreinte SHA-256 du certificat client, pas le CN — un partenaire est identifié par `hl7v2_partner`/`hl7v2_partner_facility_map`, mécanisme distinct de l'OAuth2 de §23.1, tables volontairement séparées). Messages supportés dans cette tranche : `ADT^A28`/`A31`/`A08` (patient — mapping non encore câblé, dépend de la couche `Patient` ci-dessus), `SIU^S12`/`S14`/`S15` (agenda — mapping non encore câblé, dépend de la couche `Appointment` de §23.2). Le dispatch (résolution partenaire → cabinet via `MSH-4`/`MSH-6`, dédup par `MSH-10`, audit) est en place ; le branchement effectif sur les mêmes chemins d'écriture que le REST FHIR, le listener TCP réel dans `main.rs`, et le test end-to-end restent à faire (backlog de suivi).

---

## Annexe A — Back-office V2 (recherche unifiée + assistant) · post-traction
> Proposition à arbitrer (`../design/08-back-office-v2-spotlight.md`). **Non-MVP.** L'état multi-fenêtres/dock est **client (Bloc)** → pas d'API.

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/cabinet/search` | pro | **Recherche unifiée** : vues + entités (patient, RDV, devis, document). |
| POST | `/v1/cabinet/assistant/ask` | pro | **« Demander à Nubia »** (langage naturel). |

`GET /v1/cabinet/search?q=` → `{ views:[…], entities:[{ type, id, label, snippet }] }`. **Filtré RLS + RBAC** : un `secretary` n'obtient **jamais** d'entité clinique (`07` §4.8).

`POST /v1/cabinet/assistant/ask` — body : `{ prompt }`. → `200 { answer, suggested_actions:[…], sources:[…] }`. 🚨 **Garde-fous** (`07` §8.7) : **organisationnel uniquement** (RDV, encaissements, relances), **aucune aide à la décision clinique ni diagnostic**, données **issues de requêtes réelles** (l'IA met en forme, n'invente pas), **actions suggérées jamais auto-exécutées**, IA **souveraine** (Mistral/Scaleway), requête **journalisée** (`assistant_query`, sans PII).

---

## Annexe B — Codes d'erreur · matrice rôles · index

### B.1 Codes d'erreur applicatifs (champ `code`)
| `code` | HTTP | Sens |
|---|---|---|
| `validation_error` | 422 | Corps/params invalides (voir `errors[]`). |
| `unauthenticated` | 401 | Token absent/expiré. |
| `mfa_required` | 401 | MFA pro requise. |
| `kms_not_configured` | 503 | Clé maître KMS (`KMS_MASTER_KEY`) absente/mal formée côté serveur : chiffrement MFA/reprise/INS impossible (#6980). Lacune de config, pas une panne — normalement bloquée au démarrage. |
| `forbidden` | 403 | Rôle/cloisonnement (ex. secrétariat → clinique). |
| `not_found` | 404 | Ressource inexistante ou hors tenant. |
| `email_taken` | 409 | E-mail déjà utilisé. |
| `slot_taken` | 409 | Créneau pris / double-booking. |
| `too_late` | 409 | Hors délai d'annulation/modification. |
| `quote_locked` | 409 | Devis signé immuable. |
| `provider_not_verified` | 409 | Mise en ligne refusée (RPPS non vérifié). |
| `hold_expired` | 409 | Réservation temporaire expirée. |
| `link_expired` | 410 | URL signée / lien périmé. |
| `consent_required` | 422 | Consentement manquant. |
| `rate_limited` | 429 | Trop de requêtes. |

### B.2 Matrice rôles (résumé)
| Domaine | patient | secretary | practitioner | admin |
|---|---|---|---|---|
| Annuaire / recherche | ✅ | ✅ | ✅ | ✅ |
| Ses RDV / docs / wedge | ✅ | — | — | — |
| Agenda / RDV cabinet | — | ✅ | ✅ | ✅ |
| Fiche **administrative** | — | ✅ | ✅ | ✅ |
| **Clinique** (note, journal, odontogramme, medical_record, consultation, ordonnance) | — | **⛔ 403** | ✅ | ✅ |
| Devis (création) | — | — | ✅ | ✅ |
| Suivi devis/paiements | — | ✅ | ✅ | ✅ |
| Membres / réglages cabinet | — | — | — | ✅ |

### B.3 Préfixes par module (pour le routage Axum)
`/health` · `/v1/auth` · `/v1/me` · `/v1/pro` · `/v1/cabinet` · `/v1/account` · `/v1/dashboard` · `/v1/appointments` · `/v1/documents` · `/v1/conversations` · `/v1/quotes` · `/v1/payments` · `/v1/invoices` · `/v1/treatment-plans` · `/v1/implant-passport` · `/v1/reminders` · `/v1/search` · `/v1/providers` · `/v1/establishments` · `/v1/professions` · `/v1/specialties` · `/v1/acts` · `/v1/bookings` · `/v1/slots` · `/v1/reviews` · `/v1/devices` · `/v1/notifications` · `/v1/ws` · `/v1/webhooks`.

### B.4 Ordre d'implémentation conseillé (cf. `09`)
1. **T0/T1** : `/health`, auth (register/login/refresh), `core/tenancy` + RLS, `/v1/me`.
2. **T2** : RBAC, cabinet/membres, onboarding pro + RPPS.
3. **Patient core** : account/couverture/proches, appointments, documents, conversations.
4. **Wedge (T?)** : quotes → signature (Yousign) → payments (Stripe) + webhooks.
5. **Clinique** : patients/fiche, journal, consultation CCAM, plan & devis, ordonnance.
6. **Marketplace** : taxonomy, search (Meilisearch+PostGIS), providers, booking, reviews.
7. **Temps réel** : WebSocket (waiting room, agenda, conversation).
8. **V2 (post-traction)** : recherche unifiée + assistant.

> Modèle de données : `05`. Règles métier & critères d'acceptation : `06`. Architecture & ADR : `04`. Conformité (RLS, MDR, eIDAS, audit) : `07`. Marketplace : `11`.
