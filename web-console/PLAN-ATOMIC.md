# Plan d'exécution atomique — état après audit (07/06)

> Audit du **code réel** (pas du backlog) : `git log` + fichiers sur disque + `api/src` + `db/seed`.
> **Bilan : 42 tâches livrées · 38 restantes** (dont **1 régression critique** et la **suite E2E parcours**).
> Convention : `P#`=`db/`, `R#`=`api/`, `W#`=`web-console/`, `E*`=tests E2E parcours. `[postgre]` `[rust]` `[web]`.

---

## A. ✅ Déjà livré — ne plus refaire

| Équipe | Tâches livrées |
|---|---|
| `[postgre]` | **P1–P9** (table membership, seed comptes/agenda/docs/messagerie/engagement, sanity RLS) — **complet** |
| `[rust]` | **R2** (refresh porte cabinet_id+role via `user_active_membership()`), **R4** (`POST /v1/cabinet/appointments`), **R5** (`POST /v1/quotes/:id/sign`), **R6** (`GET /v1/quotes/:id`) |
| `[web]` fondations | **W1** tokens · **W2** session role-aware · **W3** api Bearer/401 · **W4** endpoints · **W5** middleware garde-rôle · **W6** kit (10 composants) · **W7** AppShell |
| `[web]` auth | **W8** login+MFA · **W9** register+password · **W10** onboarding pro · **W11** routage par rôle |
| `[web]` patient | **W13** search · **W14** rdv/index · **W19** messages · **W21** devis · **W22** soins · **W23** profil · **W24** couverture · **W25** proches · **W26** consentements |
| `[web]` praticien | **W28** dashboard · **W29** agenda+créneaux · **W33** ordonnances · **W34** profil-public |
| `[web]` secrétaire | **W38** patients · **W39** équipe · **W40** cabinet · **W42** messagerie |
| `[web]` finition | **W44** alignement ports |

> ⚠️ **Caveat** : les pages **praticien/secrétaire livrées s'affichent mais leurs appels `/v1/cabinet/*` renvoient 401** tant que **R1** (ci-dessous) n'est pas restauré. Elles ne sont « vraiment » fonctionnelles qu'après B.

---

## B. ⛔ RÉGRESSION CRITIQUE — à traiter en premier

| ID | Tâche | Constat d'audit | Correctif |
|---|---|---|---|
| **R1** | `[rust]` login pro doit porter `cabinet_id`+`role` | **PR #1093 mergée puis écrasée par un merge ultérieur.** `api/src/auth/login.rs` (branche `else`, l.154-163) émet encore `ProClaims{sub,kind,exp}` — **sans `cabinet_id` ni `role`**. Le struct `ProClaims` (mod.rs:97) n'a que 3 champs. | Répliquer dans `login.rs` la logique **déjà présente dans `refresh.rs`** : `SELECT cabinet_id, role FROM user_active_membership($1)` → encoder `ProRegisterClaims{cabinet_id, role}`. ~15 lignes. |
| **R3** | `[rust]` test garde login pro → cabinet | **N'a jamais existé** → rien n'a détecté la régression R1. `tests/auth_login.rs` ne teste que le cas MFA. | `tests/auth_login_pro.rs` : login `practitioner`/`secretary` via `/v1/auth/login` → `GET /v1/cabinet/agenda` = 200 ; `secretary` sur conversation `scope=clinical` filtré ; pro sans membership → token nu. **Doit échouer aujourd'hui, passer après R1.** |

> **Pourquoi P0** : `R1` débloque **TOUTES** les tâches praticien + secrétaire (réelles) et **tous** les parcours E2E pro/cross (D*, S*, X*). `R2` étant déjà bon, le risque est minime (copier-coller du lookup existant).

---

## C. ⬜ Reste à faire — pages & écrans

### C.1 `[web]` Espace patient (7 écrans)
| ID | Écran | Route(s) API | Dépend de |
|---|---|---|---|
| **W12** | `patient/accueil` (dashboard agrégé) | `GET /v1/dashboard` | (fond. ✅) |
| **W15** | `patient/rdv/[id]` + actions | `GET/PATCH /v1/appointments/:id`, `…/cancel`, `…/checkin`, `…/callback-request` | W14 ✅ |
| **W16** | `patient/rdv/[id]/preparation` | `GET …/preparation`, `…/directions` | W15 |
| **W17** | `patient/rdv/[id]/salle-attente` | `GET …/queue` (polling) | W15 |
| **W18** | `patient/rdv/reserver` | `POST /v1/appointments` (depuis search slots) | W13 ✅ |
| **W20** | `patient/documents` index+détail | `GET /v1/documents`, `…/:id`, `…/:id/download` | (fond. ✅) |
| **W27** | `patient/profil/notifications` | `GET/PATCH /v1/account/notification-preferences`, `GET /v1/notifications`, `GET /v1/reminders` | W23 ✅ |

### C.2 `[web]` Espace praticien (3 écrans) — **dépend de R1**
| ID | Écran | Route(s) API | Dépend de |
|---|---|---|---|
| **W30** | `praticien/file` (salle d'attente) | `GET /v1/cabinet/waiting-room` (polling), `POST …/call-next` | **R1** |
| **W31** | `praticien/patients` index+dossier | `GET /v1/cabinet/patients` (+`/:id`,`/notes`,`/medical-record`,`/dental-chart`,`/documents`) | **R1** |
| **W32** | `praticien/consultation/[id]` | `GET /v1/cabinet/consultations/:id`, `POST …/acts`, `…/complete`, `POST /v1/cabinet/appointments/:id/start` | **R1** |

### C.3 `[web]` Espace secrétaire (4 écrans) — **dépend de R1**
| ID | Écran | Route(s) API | Dépend de |
|---|---|---|---|
| **W35** | `secretary/dashboard` | `GET /v1/cabinet/appointments`, `…/agenda`, `…/waiting-room` | **R1** |
| **W36** | `secretary/agenda` (gestion RDV) | `POST /v1/cabinet/appointments` (R4 ✅), `…/:id/confirm`, `PATCH …/:id`, créneaux | **R1** |
| **W37** | `secretary/liste-attente` | `GET /v1/cabinet/waiting-list`, `POST …/:id/offer` | **R1** |
| **W41** | `secretary/facturation` | `GET /v1/quotes` (vue cabinet) | **R1** |

### C.4 `[web]` Finition
| ID | Tâche | Détail | Dépend de |
|---|---|---|---|
| **W43** | Consolidation/nettoyage | supprimer `src/pages/test/*` (≈70) + doublons (`app/`,`scheduling/`,`appointments/`,`cabinet/`,`clinical/`,`documents/`,`marketplace/`,`me/`,`dashboard/`,`account/`,`pro/`,`notifications/`,`devices/`,`implant-passport/`,`reviews/`,`providers/`,`login.astro`,`register.astro`) ; remplacer `NavMenu` par les navs de rôle | C.1–C.3 finies |
| **W45** | dev-stack publie 3 URLs + creds | `scripts/dev-stack.sh` (racine ⚠️ hors sparse web) imprime `/patient` `/praticien` `/secretary` + comptes démo | — |
| **W50** | Docs | `README.md` (rôles/URLs/creds/run) + `ARCHITECTURE.md` (flux auth, matrice écran↔route↔rôle) | W43, EX1, EP5 |

---

## D. 🧪 Suite E2E « tous les parcours utilisateur » (NOUVEAU)

> **Constat** : 134 specs existent mais **toutes au niveau page** (`tests/e2e/*.spec.ts`), **aucun parcours bout-en-bout**. Voici la suite de **parcours** demandée. 1 tâche = 1 fichier `tests/flows/<id>.flow.spec.ts`. Sur **vraie API + seed** via `dev-stack`.

### D.0 Harnais (prérequis)
| ID | Tâche | Détail | Dépend de |
|---|---|---|---|
| **E0** | Harnais parcours + fixtures | Playwright `projects` par rôle, helpers `loginAs(role)`, comptes seed (P2), `baseURL :38040`, reset d'état entre parcours | (fond. ✅) |

### D.1 Parcours **Patient** (indépendants de R1)
| ID | Parcours bout-en-bout | Couvre | Dépend de |
|---|---|---|---|
| **EP1** | Onboarding | register → login → profil → couverture(+carte) → proches CRUD | E0, W8✅, W23✅, W24✅, W25✅ |
| **EP2** | Recherche → réservation | search → profil praticien → slot → `POST appointment` → visible dans Mes RDV | E0, W13✅, **W18**, W14✅ |
| **EP3** | Gestion RDV + jour J | détail → modifier → annuler ; check-in → salle d'attente → préparation | E0, **W15**, **W16**, **W17** |
| **EP4** | Messagerie | créer conversation → envoyer → marquer lu → relire | E0, W19✅ |
| **EP5** | Documents + devis | docs liste→détail→download ; devis liste→signer→acompte | E0, **W20**, W21✅ |
| **EP6** | Soins + profil | plan→passeport(export) ; consentements ; notifications | E0, W22✅, W26✅, **W27** |
| **EP7** | Auth bords | MFA login ; mot de passe oublié→reset | E0, W8✅ |

### D.2 Parcours **Praticien** — **dépendent de R1**
| ID | Parcours | Couvre | Dépend de |
|---|---|---|---|
| **ED1** | Dashboard + agenda | login → dashboard → créneaux (créer/éditer/supprimer/en ligne) | E0, **R1**, W28✅, W29✅ |
| **ED2** | Salle d'attente | file → call-next (polling) | E0, **R1**, **W30** |
| **ED3** | Patient + consultation | dossier(med-record/dental-chart/notes/docs) ; start→acte→complete | E0, **R1**, **W31**, **W32** |
| **ED4** | Ordonnance + profil public | créer→signer ; provider patch/listing + vérif RPPS | E0, **R1**, W33✅, W34✅ |

### D.3 Parcours **Secrétaire** — **dépendent de R1**
| ID | Parcours | Couvre | Dépend de |
|---|---|---|---|
| **ES1** | Agenda | login → dashboard → créer RDV(R4) → confirmer → modifier | E0, **R1**, R4✅, **W35**, **W36** |
| **ES2** | Liste d'attente + patients | liste d'attente→offer ; patients vue admin (sans clinique) | E0, **R1**, **W37**, W38✅ |
| **ES3** | Équipe + cabinet + facturation | inviter→modifier→retirer membre ; réglages cabinet ; devis cabinet | E0, **R1**, W39✅, W40✅, **W41** |
| **ES4** | Cloisonnement | 403/redirect sur route praticien-only ; messagerie scope clinique masqué | E0, **R1**, W42✅, W5✅ |

### D.4 Parcours **Cross-rôle** — **dépendent de R1**
| ID | Parcours | Couvre | Dépend de |
|---|---|---|---|
| **EX1** | Réservation bout-en-bout | patient réserve → praticien voit dans agenda → secrétaire confirme | E0, **R1**, **W18**, W28✅, **W36** |
| **EX2** | RDV créé par secrétaire | secrétaire crée RDV → patient le voit dans Mes RDV | E0, **R1**, R4✅, **W36**, W14✅ |
| **EX3** | Wedge devis | praticien pousse devis → patient signe → secrétaire voit règlement | E0, **R1**, W33✅, W21✅, **W41** |

---

## E. Dépendances qui restent (les seules qui comptent)
- **R1 → W30, W31, W32, W35, W36, W37, W41** (écrans pro réels) **et → ED*, ES*, EX*** (parcours pro/cross). **C'est le goulot unique.**
- **Pages C.1–C.3 → leurs parcours E2E** (D.1–D.4) : un parcours ne peut passer que si ses écrans existent.
- `[postgre]` et `[rust]` (hors R1/R3) : **terminés** — plus de blocage amont.

## F. Definition of Done (mise à jour)
- **`[rust]`** : R1 restauré + R3 vert (login pro → cabinet 200) ; `fmt`/`clippy`/`sqlx prepare --check`/`nextest` verts.
- **`[web]` écrans** : C.1–C.3 livrés ; `npm run build` + `tsc --noEmit` verts.
- **`[web]` E2E** : `tests/flows/` couvre **EP1–EP7, ED1–ED4, ES1–ES4, EX1–EX3** au vert sur vraie API + seed.
- **`[web]` finition** : doublons/`test` supprimés (W43) ; dev-stack imprime 3 URLs+creds (W45) ; docs (W50).

## G. Ordre conseillé
1. **R1** (déblocage) → **R3** (garde anti-régression).
2. `[web]` patient C.1 (W12,W15,W16,W17,W18,W20,W27) — **en parallèle**, sans attendre R1.
3. `[web]` pro C.2/C.3 (W30→W32, W35→W41) — après R1.
4. **E0** puis parcours E2E (D) au fur et à mesure que les écrans tombent.
5. **W43** nettoyage → **W45** dev-stack → **W50** docs.

---

## H. Évolution — multi-établissement & secrétariats (NOUVEAU, 07/06)

> **Besoin métier** : un **docteur exerce dans plusieurs établissements** ; il **assigne sa liste de patients + son agenda à un secrétariat précis** ; les **utilisateurs (secrétaires, managers)** sont **rattachés à un secrétariat** et peuvent appartenir à **plusieurs établissements/secrétariats** ; chaque secrétaire est **différenciée** selon son secrétariat et peut avoir **des docteurs/patients différents** ; un **directeur/manager peut créer/assigner des comptes secrétaires**.

### Décisions de modélisation (autonome — Option A, à valider)
- **Établissement = `cabinet` existant** (reste la frontière tenant/RLS ; pas de renommage).
- **`secretariat`** = sous-unité d'un établissement (**1..n par cabinet**).
- **3 catégories d'utilisateurs distinctes** : `patient` · `provider` (docteur) · **personnel de secrétariat** (`secretary`, `manager`). Le personnel = `app_user(kind=pro)` rattaché par `secretariat_membership`, **sans** ligne `provider`.
- **Scoping secrétaire** : ne voit que les **docteurs assignés à son secrétariat** (`provider_secretariat`) + leurs patients (dérivé via RDV) → cloisonnement **intra-établissement**.
- **Contexte actif** : un user multi-appartenance **choisit son contexte** (établissement + secrétariat) ; le JWT porte `cabinet_id`+`role`(+`secretariat_id`). **Remplace le `LIMIT 1` de R1** (R9).
- **Patient↔secrétariat** : dérivé (via docteur assigné) pour la démo ; table explicite `patient_secretariat` = post-démo si besoin.
- **Manager** : rôle au niveau **secrétariat** (`secretariat_membership.role='manager'`) ; l'**admin** établissement a le sur-ensemble. Provisioning de comptes secrétaires autorisé pour `{admin, manager}`.

### H.1 `[postgre]`
| ID | Tâche | Détail | Dépend de |
|---|---|---|---|
| **P10** | table `secretariat` | `(id, cabinet_id FK, name, created_at)` ; RLS cabinet-scoped ; backfill 1/cabinet + seed 2 sur cabinet démo | — |
| **P11** | table `secretariat_membership` | `(secretariat_id, user_id, role∈{secretary,manager}, active)` ; RLS ; seed 1 manager + 2 secrétaires | P10 |
| **P12** | table `provider_secretariat` | `(provider_id, secretariat_id, active)` — assignation docteur→secrétariat ; seed A→A, B→B | P10 |
| **P13** | contexte actif + RLS secrétaire | `user_active_memberships()` (cabinet_id, role, secretariat_id) + GUC `app.current_secretariat_id` ; policies agenda/patients/waiting-room/conversations filtrées par secrétariat | P11, P12 |
| **P14** | pgTAP isolation secrétariat | secrétaire A ≠ voit secrétariat B (même établissement) ; docteur voit ses 2 établissements | P13 |

### H.2 `[rust]`
| ID | Tâche | Détail | Dépend de |
|---|---|---|---|
| **R7** | `GET /v1/me` tous contextes | établissements + secrétariats + rôles (multi-appartenance) | P11 |
| **R8** | `POST /v1/auth/select-context` | `{cabinet_id, secretariat_id?}` → JWT scoped ; role ∈ {admin,practitioner,secretary,manager} | P11, P13 |
| **R9** | login/refresh multi-contexte | révise R1/R2 : 1 contexte→embarqué ; n→token nu + `context_required` | **R1**, R8, P13 |
| **R10** | endpoints cabinet **secretary-scoped** | agenda/patients/waiting-room/appointments/conversations filtrés par `secretariat_id` ; claim porte `secretariat_id` | R8, R9, P13 |
| **R11** | assignation docteur→secrétariat | `GET/PUT /v1/cabinet/providers/:id/secretariats` | P12 |
| **R12** | CRUD secrétariats + membres | `GET/POST /v1/cabinet/secretariats`, `PATCH/DELETE :id`, `POST/DELETE :id/members` (admin/manager) | P10, P11 |
| **R13** | provisionner un compte secrétaire | `POST /v1/cabinet/secretariats/:id/staff` : crée app_user(pro,secretary) ou rattache existant + membership ; `{admin,manager}` ; audité | P11, P12, R12 |

### H.3 `[web]`
| ID | Tâche | Détail | Dépend de |
|---|---|---|---|
| **W51** | session contexte | `secretariat_id` + cookie `nubia_ctx` + helpers | R8 |
| **W52** | sélecteur de contexte (AppShell) | établissement + secrétariat ; `/v1/auth/select-context` ; affiché si >1 ; nom du secrétariat visible | R7, R8, W51, W7 |
| **W53** | écran choix de contexte post-login | si `context_required` → choisir établissement+secrétariat | R7, R8, W51 |
| **W54** | praticien — mes secrétariats / assignation | assigner patients+agenda à un secrétariat par établissement (`PUT providers/:id/secretariats`) | R11, W51 |
| **W55** | secrétaire — bandeau contexte + données scoped | « Secrétariat X — Établissement Y » ; agenda/patients filtrés ; adapte W35/W36/W38 | R10, W51, W35 |
| **W56** | middleware garde contexte | `secretariat_id` ; user sans contexte → W53 | W5, W51 |
| **W57** | admin — gestion des secrétariats | CRUD secrétariats + affectation membres (R12) | R12, W51 |
| **W58** | manager — gestion du personnel | créer/inviter secrétaire + affecter/retirer (R13) ; visible `{admin,manager}` | R13, W51, W52 |

### H.4 `[web][e2e]` parcours
| ID | Parcours | Dépend de |
|---|---|---|
| **ED5** | docteur multi-établissement : choisit A puis B → assigne agenda au secrétariat de chacun → bonne secrétaire le voit | E0, R9, W54, R11 |
| **ES5** | secrétaire multi-secrétariat : 2 secrétariats → sélection contexte → patients/docteurs différents (cloisonnement) | E0, R10, W52, W55, P11, P12 |
| **ES6** | manager provisionne une secrétaire → assigne au secrétariat A → la secrétaire se connecte, scoped A | E0, R13, R10, W58, W55 |
| **EX4** | docteur assigne patient-list à secrétariat A → secrétaire A voit, secrétaire B ne voit pas | E0, R10, R11, W54, W55 |

### H.5 Dépendances inter-équipes & séquencement
- **Chemin** : `P10→P11/P12→P13→R8→R9/R10→W51→W52/W55→ES5/EX4`. Manager : `R12→R13→W58→ES6`.
- **R9 supersede la simplification `LIMIT 1` de R1** : faire **R1** (restaurer le contexte simple) d'abord, **puis** R9 (multi-contexte) — pas l'un sans l'autre en prod.
- `[rust]` R7/R8 et `[web]` W51/W52/W53 sont le **socle contexte** : tout le scoping secrétaire en dépend.
- **Ordre conseillé épique** : P10→P14 · R7→R13 · W51→W58 · ED5/ES5/ES6/EX4. Démarre dès que **R1** est restauré (section B).
