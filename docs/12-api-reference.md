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
| POST | `/v1/auth/register` | — | Création compte **patient** (e-mail + mot de passe) + CGU. |
| POST | `/v1/auth/login` | — | Login → access + refresh. Patient ou pro (selon compte). |
| POST | `/v1/auth/refresh` | refresh | Rotation du refresh, nouveau access. |
| POST | `/v1/auth/logout` | oui | Révoque le refresh courant. |
| POST | `/v1/auth/password/forgot` | — | Envoie un lien de reset (réponse neutre, anti-énumération). |
| POST | `/v1/auth/password/reset` | — | Reset via token. |
| POST | `/v1/auth/mfa/enroll` | pro | Démarre l'enrôlement TOTP (renvoie secret/QR). |
| POST | `/v1/auth/mfa/verify` | pro | Valide le code, active la MFA. |
| GET | `/v1/me` | oui | Profil du porteur du token (compte + rôles/cabinets). |
| POST | `/v1/auth/franceconnect/start` · `/callback` | — | FranceConnect patient (**post-MVP**, `07` §9.3). |
| POST | `/v1/auth/psc/start` · `/callback` | — | Pro Santé Connect / e-CPS (**post-MVP**, `07` §9.2). |

**Contrats clés**

`POST /v1/auth/register` — body : `email`, `password`, `accept_cgu:true`, `cgu_version`. → `201 { account_id, access_token, refresh_token }`. Erreurs : `409 email_taken`, `422` (politique mot de passe), `422 cgu_required`. Effet : crée `app_user` + `patient_account` + `consent_record(purpose='soins')` horodaté (`06` E3.1).

`POST /v1/auth/login` — body : `email`, `password`, `mfa_code?`. → `200 { access_token, refresh_token, token_type:"Bearer", expires_in }`. Si pro avec MFA : `401 mfa_required` puis renvoyer avec `mfa_code`. Rate-limited.

`GET /v1/me` → `{ user_id, email, kind:"patient"|"pro", account_id?, memberships:[{ cabinet_id, role }] }`. Pour un pro multi-cabinets, le **choix du cabinet actif** se fait à la connexion (le token porte un seul `cabinet_id`).

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
| GET | `/v1/account/consents` | patient | Consentements (purpose/granted). |
| PUT | `/v1/account/consents/{purpose}` | patient | Donne/révoque un consentement (`consent_record`). |
| GET | `/v1/account/notification-preferences` | patient | Préférences notif. |
| PATCH | `/v1/account/notification-preferences` | patient | MAJ opt-in par canal/type. |
| GET | `/v1/account/dependents` | patient | Proches / ayants droit. |
| POST | `/v1/account/dependents` | patient | Ajoute un proche (crée un `patient_account` lié). |
| GET | `/v1/account/dependents/{id}` | patient | Détail d'un proche. |
| PATCH | `/v1/account/dependents/{id}` | patient | Édite (sa propre couverture incluse). |
| DELETE | `/v1/account/dependents/{id}` | patient | Révoque la tutelle (soft, `account_guardianship.active=false`). |

**Contrats clés**

`PATCH /v1/account/coverage` — body : `{ regime_obligatoire:"regime_general"|"ame"|"css", nss?, mutuelle:{ amc, numero_adherent, plateforme? }, tiers_payant:bool }`. → `200`. ⚠️ `nss` **chiffré** côté serveur (`05` §10.1), jamais renvoyé en clair (masqué : `"2 91 03 …78"`). Audité.

`POST /v1/account/coverage/card` — `multipart/form-data` : `side:"recto"|"verso"`, `file`. → `201 { document_id }`. Antivirus + chiffrement ; `document.category='carte_mutuelle'`.

`POST /v1/account/dependents` — body : `{ first_name, last_name, birth_date, relationship:"enfant"|"conjoint"|…, coverage?{…} }`. → `201 { dependent_account_id }`. Crée un `patient_account` + `account_guardianship(guardian=moi, dependent, authority)`. Le titulaire peut ensuite réserver/gérer pour ce proche (header `X-On-Behalf-Of: <dependent_account_id>` sur les routes RDV/docs ; vérifié contre `account_guardianship`). Conformité mineurs : `07` §4.6.

---

## 7. Patient — tableau de bord, RDV & préparation

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| GET | `/v1/dashboard` | patient | Vue agrégée d'accueil (US-P13). |
| GET | `/v1/appointments` | patient | Mes RDV (tous praticiens), `?status=upcoming\|past`. |
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

`GET /v1/documents` → liste `{ id, category, filename, mime_type, created_at }`. Catégories : `devis, facture, ordonnance, radio, cbct, photo, cr, consigne, attestation, carte_mutuelle, passeport_implantaire, consentement`. Accès **audité** (`read_document`), URL **expirante**, intégrité `sha256` (`06` E3.5). Téléchargement → `302` vers Object Storage signé (`410` si lien expiré).

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

`GET /v1/search/providers` — query : `q?`, `specialty?`, `near?=lat,lng` **ou** `place?` (géocodé), `radius_km?`, `bbox?` (carte), facettes `sector?`, `tiers_payant?`, `teleconsult?`, `pmr?`, `languages?`, `accepts_new?`, `available?=today|week`, `sort?=relevance|distance|next_slot|rating`, pagination. → `{ data:[{ provider_id, display_name, specialty, sector, distance_m?, next_slot_at?, rating_avg, geo, is_listed:true }], facets:{…}, page:{…} }`. **Seuls les `provider` `is_listed=true` (donc `rpps_verified`)** apparaissent (`05` §9.3, `07` §4.7). `place` → géocodage service EU.

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

`POST /v1/slots/{id}/hold` → `200 { hold_token, expires_at }` (passe le slot en `held` quelques minutes). `POST /v1/bookings` — body : `{ slot_id, hold_token?, motif, on_behalf_of?, new_patient_info? }`, **`Idempotency-Key`**. → `201 { appointment_id }`. Crée l'`appointment` chez le praticien (tenant) **et** le rattache à l'espace patient global. Conflit/hold expiré → `409`. Pré-check-in proposé.

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
| PATCH | `/v1/cabinet/appointments/{id}` | pro | Déplacer/éditer (transition auditée). |
| POST | `/v1/cabinet/slots` | pro | Ouvrir/bloquer un créneau. |
| PATCH/DELETE | `/v1/cabinet/slots/{id}` | pro | Éditer/supprimer un créneau. |
| PUT | `/v1/cabinet/slots/{id}/online` | pro | Exposer le créneau à la réservation en ligne (US-M19). |
| GET | `/v1/cabinet/waiting-room` | pro | File en temps réel (+ WS §20). |
| POST | `/v1/cabinet/waiting-room/call-next` | pro | Appeler le patient suivant (notifie « c'est à vous »). |
| GET | `/v1/cabinet/waiting-list` | secretary+ | Liste d'attente / combler un trou (🎭). |
| POST | `/v1/cabinet/waiting-list/{id}/offer` | secretary+ | Proposer un créneau libéré. |

`GET /v1/cabinet/agenda` → `{ practitioners:[…], slots:[{ id, practitioner_id, starts_at, ends_at, status, patient?:{display}, motif }] }`. Le secrétariat voit le **motif administratif**, pas le contenu clinique. Anti-double-booking via contrainte d'exclusion (`05` §5.4).

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

`POST /v1/cabinet/patients/{id}/notes` — body : `{ note_kind:"observation"|"act", text, tooth?, act_ref?:{ label, ccam?, quote_item_id? } }`. → `201`. Contenu **chiffré**, **horodaté**, **signé** (`author_id`), `practitioner` only (US-D12, `05` §10.3). Pas de suppression dure (soft-delete médical).

---

## 15. Back-office — consultation au fauteuil
> Le cœur clinique (US-D09, `06` E4.7). `practitioner` only.

| Méthode | Chemin | Rôle | Description |
|---|---|---|---|
| POST | `/v1/cabinet/appointments/{id}/start` | practitioner | Démarre la séance (`appointment→in_progress`). |
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
| GET | `/v1/cabinet/quotes` | pro | Suivi devis & paiements (`?status=`, relances). |
| POST | `/v1/cabinet/quotes` | practitioner | Créer un devis (lignes CCAM, AMO/AMC, dent). |
| PATCH | `/v1/cabinet/quotes/{id}` | practitioner | Éditer tant que **non signé** (versioning). |
| POST | `/v1/cabinet/quotes/{id}/send` | practitioner | Envoyer au patient pour signature. |
| GET | `/v1/cabinet/quotes/{id}` | pro | Statut signature/paiement. |
| POST | `/v1/cabinet/quotes/{id}/remind` | pro | Relancer (acompte/signature). |

`POST /v1/cabinet/quotes` — body : `{ patient_id, plan_id?, items:[{ label, ccam_code?, tooth?, qty, unit_amount_cents, amo_part_cents?, amc_part_cents? }], deposit_pct? }`. → `201`. **Reste à charge** = calculé (`unit_amount − amo − amc`). Un devis **signé** : `PATCH`/`send` → `409 quote_locked` (`06` E5.1).

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

`POST /v1/cabinet/prescriptions` — body : `{ patient_id, items:[{ label, form?, posology, duration, quantity }] }`. → `201`.
> 🚨 **L'API n'effectue AUCUN contrôle automatique** d'allergies/interactions/contre-indications et **ne suggère aucune alternative** (= aide à la décision = dispositif médical, **exclu**). Elle peut **afficher** en lecture les allergies que le praticien a saisies dans `medical_record`. Le praticien décide seul. `/sign` réutilise la brique signature du wedge ; `/send` génère un `document(category='ordonnance')`.

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

`POST /v1/devices` — body : `{ fcm_token, platform:"ios"|"android"|"web" }`. → `201`. ⚠️ **Payload push sans PII** (`06` E3.7, `07` §2.7) : le contenu réel se charge **authentifié** après ouverture. Types : RDV à venir/modifié/annulé, document à signer, nouveau message, paiement en attente, « c'est bientôt à vous ».

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
