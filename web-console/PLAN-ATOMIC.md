# Plan d'exécution atomique — 3 équipes `[postgre]` · `[rust]` · `[web]`

> Dérivé de `GUIDE.md`. Chaque tâche est **atomique** (1 route / 1 écran / 1 fichier) et porte son **équipe** et ses **dépendances** (y compris **inter-équipes**).
> Convention d'ID : `P#` = base PostgreSQL (`db/`), `R#` = backend Rust (`api/`), `W#` = web-console (`web-console/`).
> Règle de lecture : une tâche ne démarre que lorsque **toutes** ses dépendances sont vertes.

---

## 0. Le chemin critique (à retenir)

```
P1 (table membership) ─▶ R1 (login encode cabinet_id+role) ─▶ TOUT le web pro (praticien + secrétaire)
P2 (comptes seed) ─▶ P3..P8 (données seed) ─▶ web data-dépendant (patient + pro)
```

- **Bloqueur n°1** : sans **R1**, aucun écran `[web]` praticien/secrétaire ne fonctionne (cf. `GUIDE.md` §2.1). **R1 dépend de P1.**
- **Le patient n'est PAS bloqué par R1** (le login patient marche déjà) → l'équipe `[web]` peut livrer tout l'espace patient **en parallèle** du fix auth, dès que le seed patient (P4–P8) existe.
- **`[web]` foundations (W1–W7)** ne dépendent d'aucune autre équipe → démarrage **immédiat**.

---

## 1. Vagues de parallélisation (vue planning)

| Vague | `[postgre]` | `[rust]` | `[web]` |
|---|---|---|---|
| **V0 — démarrage immédiat** | P1, P2 | _(attend P1)_ | W1, W2, W6 |
| **V1 — déblocage** | P3, P4 | **R1, R2** | W3, W4, W5, W7 |
| **V2 — données + auth front** | P5, P6, P7, P8 | R3, R4, *(R5,R6 opt.)* | W8, W9, W10, W11 |
| **V3 — construction des apps (parallèle)** | P9 (sanity RLS) | _(support/bugfix)_ | Patient W12–W27 · Praticien W28–W34 · Secrétaire W35–W42 |
| **V4 — finition** | — | _(support)_ | W43, W44, W45, W46, W47, W48, W49, W50 |

> Les 3 équipes travaillent **en parallèle dès V0**. Le seul rendez-vous dur est **R1** (fin V1) qui ouvre la construction pro (V3).

---

## 2. `[postgre]` — base de données (`db/`)

| ID | Tâche atomique | Détail / fichier | Dépend de |
|---|---|---|---|
| **P1** | Vérifier la table `cabinet_membership` | colonnes `user_id, cabinet_id, role, active, created_at` (+ index `user_id`). **Précondition du lookup login R1.** Si `created_at` absent → migration `db/migrations/NNNN`. | — |
| **P2** | Seed : cabinet fictif + 4 comptes | 1 `cabinet` + 4 `app_user` (patient / practitioner / secretary / admin), hash argon2, mot de passe démo commun documenté | — |
| **P3** | Seed : memberships + provider | `cabinet_membership` (practitioner, secretary, admin → cabinet) + ligne `provider` (RPPS vérifié, `is_listed=true`) | P2 |
| **P4** | Seed : patient | `patient_account` + `patient_coverage` (régime+mutuelle) + 2 `dependents` + `consent_record` | P2 |
| **P5** | Seed : agenda | `availability_slot` (open) + `appointment` (1 à venir confirmé, 1 passé) liant patient ↔ provider | P3, P4 |
| **P6** | Seed : docs & finances | `document` (ordo, radio, carte mutuelle) + `quote` (devis) + `treatment_plan` + `implant_passport` | P4 |
| **P7** | Seed : messagerie | `conversation` + `message` (1 scope `clinical`, 1 scope `admin`) patient ↔ cabinet | P3, P4 |
| **P8** | Seed : engagement | `waiting_list_entry` + `notification` + `reminder` | P5 |
| **P9** | Sanity RLS seed | chaque compte seed ne voit que ses données (req. sous `nubia_app`) ; non-régression `make test` pgTAP | P5, P6, P7 |

---

## 3. `[rust]` — backend API (`api/`)

| ID | Tâche atomique | Détail / fichier | Dépend de |
|---|---|---|---|
| **R1** | **Login pro porte `cabinet_id`+`role`** | `api/src/auth/login.rs` : si `kind=pro`, lookup `cabinet_membership` (active, `LIMIT 1`) → encode JWT `{sub,kind,cabinet_id,role,exp}` | **P1** |
| **R2** | **Refresh pro re-résout `cabinet_id`+`role`** | `api/src/auth/refresh.rs` : même lookup que R1 (sinon le rôle saute au refresh) | **P1** |
| **R3** | Tests intégration auth pro | `api/tests/auth_login_pro.rs` : login practitioner/secretary → `GET /v1/cabinet/agenda` 200 ; secretary sur conversation `scope=clinical` filtré | R1, R2 |
| **R4** | _(gap)_ `POST /v1/cabinet/appointments` | création RDV **par le secrétariat** pour un patient du cabinet (l'actuel `POST /v1/appointments` exige un token patient). `ProSecretaryPlusClaims`. **Vérifier d'abord si déjà couvert.** | R1 |
| **R5** | _(gap, optionnel)_ Signature devis patient | `POST /v1/quotes/:id/sign` (Yousign stub). Si non livré → `[web]` stub l'UI sans appel. | — |
| **R6** | _(gap, optionnel)_ Détail devis patient | `GET /v1/quotes/:id`. Si non livré → `[web]` réutilise la liste. | — |

> **R1 est LE livrable critique inter-équipes.** Respecter `api/AGENTS.md` (RLS `with_tenant`, `query!` macros, `cargo sqlx prepare --check`, `fmt`/`clippy`/`nextest`).

---

## 4. `[web]` — web-console (`web-console/`)

### 4.1 Fondations (V0–V1, aucune dépendance externe)
| ID | Tâche atomique | Détail / fichier | Dépend de |
|---|---|---|---|
| **W1** | Tokens design system | `src/styles/tokens.css` (émeraude/typo/arrondis) importé global | — |
| **W2** | Session role-aware | `src/lib/session.ts` : décode `kind/role/account_id/cabinet_id` + cookie `nubia_role` | — |
| **W3** | Client API + Bearer/401 | `src/lib/api.ts` : injecte `Authorization`, refresh-on-401 puis rejoue | W2 |
| **W4** | Client typé par domaine | `src/lib/endpoints.ts` : fonctions par route (Annexe A du guide) | W3 |
| **W5** | Middleware garde-rôle | `src/middleware.ts` : protège `/patient` `/praticien` `/secretary` selon `nubia_role` | W2 |
| **W6** | Kit composants | `src/components/kit/*` : Button, Field, Card, Table, Modal, Tabs, Toast, Badge, EmptyState, Spinner | W1 |
| **W7** | AppShell par rôle | `src/layouts/AppShell.astro` (header + nav variable + slot) | W6 |

### 4.2 Auth & routage (V2)
| ID | Tâche atomique | Détail / fichier | Dépend de |
|---|---|---|---|
| **W8** | Écran login (+ MFA) | `src/pages/auth/login.astro` : POST login, gère `401 mfa_required` | W3, W2 |
| **W9** | Register patient + password | `auth/register.astro`, `auth/password/forgot.astro`, `reset.astro`, `mfa-verify.astro` | W3 |
| **W10** | Onboarding pro | `auth/pro/register.astro` (cabinet + RPPS), `pro/verification` | W3 |
| **W11** | Redirection post-login par rôle | sélecteur d'espace si `admin` ; route selon `kind`/`role` | W8, **R1** |

### 4.3 Espace **Patient** (V3 — indépendant de R1, dépend du seed)
| ID | Tâche atomique | Route(s) API | Dépend de |
|---|---|---|---|
| **W12** | `patient/accueil` (dashboard) | `GET /v1/dashboard` | W7, W4, W5, W8, P5, P6 |
| **W13** | `search/*` (annuaire public) | `GET /v1/search/suggest\|providers\|slots`, `providers/:id`, `cabinets/:id/info`, `professions\|specialties\|acts` | W7, W4 |
| **W14** | `patient/rdv/index` | `GET /v1/appointments?status=` | W4, P5 |
| **W15** | `patient/rdv/[id]` + actions | `GET /v1/appointments/:id` ; `PATCH`, `…/cancel`, `…/checkin`, `…/callback-request` | W14 |
| **W16** | `patient/rdv/[id]/preparation` | `GET …/preparation`, `…/directions` | W15 |
| **W17** | `patient/rdv/[id]/salle-attente` | `GET …/queue` (polling) | W15 |
| **W18** | `patient/rdv/reserver` | `POST /v1/appointments` (depuis search slots) | W13, W14 |
| **W19** | `patient/messages` index+détail | `GET /v1/conversations`, `GET\|POST …/messages`, `POST …/read`, `POST /v1/conversations` | W4, P7 |
| **W20** | `patient/documents` index+détail | `GET /v1/documents`, `…/:id`, `…/:id/download` | W4, P6 |
| **W21** | `patient/devis` (+ signature/acompte) | `GET /v1/quotes` ; sign = R5 sinon stub ; `POST /v1/payments/intent` | W4, P6 |
| **W22** | `patient/soins` (plan + passeport) | `GET /v1/treatment-plans` (+`/:id`), `GET /v1/implant-passport` (+`/export`) | W4, P6 |
| **W23** | `patient/profil` (infos) | `GET\|PATCH /v1/account` | W4, P4 |
| **W24** | `patient/profil/couverture` | `GET\|PATCH /v1/account/coverage`, `POST …/coverage/card` | W23 |
| **W25** | `patient/profil/proches` | `GET\|POST /v1/account/dependents`, `GET\|PATCH\|DELETE …/:id` | W23, P4 |
| **W26** | `patient/profil/consentements` | `GET /v1/account/consents`, `PUT …/:purpose` | W23 |
| **W27** | `patient/profil/notifications` | `GET\|PATCH /v1/account/notification-preferences`, `GET /v1/notifications`, `GET /v1/reminders` | W23, P8 |

### 4.4 Espace **Praticien** (V3 — dépend de **R1** + seed pro)
| ID | Tâche atomique | Route(s) API | Dépend de |
|---|---|---|---|
| **W28** | `praticien/dashboard` | `GET /v1/cabinet/agenda`, `…/appointments`, `…/waiting-room` | **R1**, W7, W4, W5, W8, P5 |
| **W29** | `praticien/agenda` + créneaux | `GET /v1/cabinet/agenda` ; `POST /v1/cabinet/slots`, `PATCH\|DELETE …/:id`, `PUT …/:id/online` | **R1**, P5 |
| **W30** | `praticien/file` (salle d'attente) | `GET /v1/cabinet/waiting-room` (polling), `POST …/call-next` | **R1**, P5 |
| **W31** | `praticien/patients` index+dossier | `GET /v1/cabinet/patients` (+`/:id`, `/notes`, `/medical-record`, `/dental-chart`, `/documents`) | **R1**, P3 |
| **W32** | `praticien/consultation/[id]` | `GET /v1/cabinet/consultations/:id`, `POST …/acts`, `…/complete`, `POST /v1/cabinet/appointments/:id/start` | **R1**, P5 |
| **W33** | `praticien/ordonnances` new+sign | `POST /v1/cabinet/prescriptions`, `…/:id/sign` (display-only, hors MDR) | **R1** |
| **W34** | `praticien/profil-public` | `PATCH /v1/cabinet/provider`, `PUT …/provider/listing`, `GET\|POST /v1/pro/verification` | **R1** |

### 4.5 Espace **Secrétaire** (V3 — dépend de **R1** ; clinique masqué)
| ID | Tâche atomique | Route(s) API | Dépend de |
|---|---|---|---|
| **W35** | `secretary/dashboard` | `GET /v1/cabinet/appointments`, `…/agenda`, `…/waiting-room` | **R1**, W7, W4, W5, W8, P5 |
| **W36** | `secretary/agenda` (gestion RDV) | `POST /v1/cabinet/appointments` (**R4**), `…/:id/confirm`, `PATCH …/:id` ; créneaux | **R1**, **R4**, P5 |
| **W37** | `secretary/liste-attente` | `GET /v1/cabinet/waiting-list`, `POST …/:id/offer` | **R1**, P8 |
| **W38** | `secretary/patients` (vue admin) | `GET /v1/cabinet/patients` (sans clinique) | **R1**, P3 |
| **W39** | `secretary/equipe` | `GET\|POST /v1/cabinet/members`, `PATCH\|DELETE …/:user_id` | **R1**, P3 |
| **W40** | `secretary/cabinet` (réglages) | `GET\|PATCH /v1/cabinet`, `GET /v1/cabinets/:id/info` | **R1** |
| **W41** | `secretary/facturation` | `GET /v1/quotes` (vue cabinet) | **R1**, P6 |
| **W42** | `secretary/messagerie` | `GET /v1/cabinet/conversations` (scope clinique filtré par l'API) | **R1**, P7 |

### 4.6 Finition (V4)
| ID | Tâche atomique | Détail | Dépend de |
|---|---|---|---|
| **W43** | Consolidation/nettoyage | supprimer `/test/*` + doublons `scheduling`/`appointments`/`app`, remplacer `NavMenu` | W27, W34, W42 |
| **W44** | Aligner la config ports | `scripts/dev.sh` + `README` + défaut `api.ts` → `PUBLIC_API_BASE` (`:38030`) ; **ne pas** revenir à `:3000/:4321` | — |
| **W45** | dev-stack publie 3 URLs + creds | éditer `scripts/dev-stack.sh` (racine ⚠️ hors sparse web — coordonner) : imprimer `/patient` `/praticien` `/secretary` + comptes démo | P2 |
| **W46** | E2E patient | Playwright : login → réserver → check-in | W18, W15, P5 |
| **W47** | E2E praticien | login → agenda → start → acte → complete → ordonnance | W32, W33, **R1** |
| **W48** | E2E secrétaire (+403) | login → créer RDV → inviter membre ; **403** sur route praticien-only | W36, W39, **R1** |
| **W49** | E2E cross-rôle | patient réserve → praticien voit → secrétaire confirme | W46, W47, W48 |
| **W50** | Docs | `README.md` (rôles, URLs, creds, run) + `ARCHITECTURE.md` (flux auth, matrice écran↔route↔rôle) | W45, W43 |

---

## 5. Synthèse des dépendances inter-équipes (les seules qui comptent)

| Dépendance | Sens | Pourquoi |
|---|---|---|
| **P1 → R1/R2** | `[postgre]` → `[rust]` | le login lit `cabinet_membership` |
| **R1 → W11, W28–W42** | `[rust]` → `[web]` | sans token `role`+`cabinet_id`, les écrans pro renvoient 401 |
| **R4 → W36** | `[rust]` → `[web]` | création de RDV par le secrétariat |
| **P2–P8 → W12–W42** | `[postgre]` → `[web]` | les écrans affichent des données seed |
| **R5/R6 → W21** | `[rust]` (optionnel) → `[web]` | signature/détail devis (sinon stub web) |

> **Tout le reste est intra-`[web]`.** Les équipes `[postgre]` et `[rust]` ont un périmètre court et **en amont** ; `[web]` porte le volume mais peut démarrer ses fondations et tout l'espace **patient** sans attendre les autres.

## 6. Definition of Done par équipe
- **`[postgre]`** : `make test` vert ; les 4 comptes voient leurs données sous `nubia_app` ; creds documentés.
- **`[rust]`** : `fmt`/`clippy -D warnings`/`sqlx prepare --check`/`nextest` verts ; un token issu de **login** atteint les endpoints cabinet selon son rôle (R3).
- **`[web]`** : `npm run build` + `tsc --noEmit` + Playwright (W46–W49) verts ; 3 espaces navigables sur la vraie API ; doublons supprimés.
