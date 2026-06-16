# Plan d'exécution atomique — `front/` (3 apps Flutter)

> Source de vérité pour finir les 3 apps Flutter (`app_patient`, `app_practicien`, `app_secretariat`).
> Convention : `FR#` = tâche `front/`, label `[flutter-front]`. 1 issue = 1 deliverable testable, branche `agent/front-<id>`, CI front verte.
>
> Audit du code réel `front/` (16/06) : 5 packages partagés **complets** (`nubia_core`/`design_system`/`a2ui` + `nubia_domain`/`nubia_data` **surface patient**). Les 3 apps n'ont que **login + dashboard stub**. Référence à porter pour le patient = `app/` (14 features patient full-BLoC).
>
> **Décisions actées (16/06)** : profondeur **production-ready** · cache offline **Drift** (PAS Hive) · les **3 apps en parallèle** · 1 issue = 1 deliverable testable (bloc OU page OU test), diff ≤200 lignes.

## ⚠️ Points d'attention

- **Goulot data-layer** : `nubia_data` ne couvre que la surface **patient**. Toute la surface **pro** `/v1/cabinet/*` (agenda, patients, consultations, salle d'attente, membres, secrétariats, devis cabinet) est **absente** côté domaine+data ET sans référence dans `app/`. FR0.2→FR0.4 débloquent FR2/FR3.
- **Dépendance backend** : plusieurs features front consomment des routes API encore **documentées sans handler** (backlog routes API = `web-console/PLAN-ATOMIC.md` section E, en **lecture seule** ici). Colonne « Back » ci-dessous = dépendance vers une route/issue rust. Une feature front n'est verte E2E que si sa route backend est livrée → créer/prioriser l'issue rust correspondante d'abord.
- **Conventions établies** (à suivre) : `AppRouter` go_router + `buildAuthGuard` (`nubia_core`), DI GetIt `registerCore → registerData → register<App>`, features sous `apps/<app>/lib/features/<feat>/` (`bloc/ pages/ widgets/`).

---

## 1. Fondations partagées (`packages/` + infra) — à faire en premier

| ID | Tâche | Détail | Back |
|---|---|---|---|
| **FR0.1** | Audit contrat `nubia_data` ↔ `api/` | Aligner DTO/chemins divergents : `appointments/:id/cancel` (POST, pas DELETE), `documents/:id/download` (pas `signed-url`), `quotes/:id/sign` + `payments/intent` (pas `/deposits`+`/signatures`), `me` (pas `auth/me`), prefix `account/*`. 1 test de désérialisation par DTO corrigé. | — |
| **FR0.2** | Domaine pro (`nubia_domain`) | Entités `CabinetPatient`, `AgendaEntry`, `CabinetAppointment`, `ConsultationContext`, `WaitingRoomEntry`, `WaitingListEntry`, `Member`, `Secretariat`, `Slot`, `CabinetQuote` + ports repo. | — |
| **FR0.3** | Use cases pro (`nubia_domain`) | UC agenda/patients/consultation/waiting-room/slots/membres/secrétariats/devis-cabinet + gating `includeClinical` sur consultation/acts. | — |
| **FR0.4** | Data pro (`nubia_data`) | DTOs + `CabinetPatientsApi`/`CabinetAgendaApi`/`CabinetAppointmentsApi`/`ConsultationApi`/`WaitingRoomApi`/`SlotsApi`/`MembersApi`/`SecretariatApi`/`CabinetQuotesApi` + repo impls + `registerData(includeClinical, includePro)`. Tests DTO. | E.2, E.5 |
| **FR0.5** | `ProShell` partagé | Extraire le scaffold side-nav (NavigationRail desktop / drawer mobile) piloté par `ProConfig.nav` + garde `AuthSession.canAccessClinical`, route-par-destination. Mini-lib `packages/nubia_app_shell`. | — |
| **FR0.6** | Infra test front + CI | Harness `pumpApp`, repos mock (mocktail), `melos test` câblé, job CI Forgejo `flutter analyze` + `flutter test` workspace (bloquant merge). | — |
| **FR0.7** | Couche cache offline **Drift** | Base Drift partagée + pattern repo décoré (cache-then-network) réutilisable par feature. Remplace l'approche Hive de `app/`. | — |

---

## 2. `app_patient` (port depuis `app/`) — dépend FR0.1, FR0.6, FR0.7

| ID | Feature | Détail | Back |
|---|---|---|---|
| **FR1.1** | Dashboard réel | bloc `GetDashboardSummary` → remplace `_HomeTab` stub + test. | `GET /v1/dashboard` ✅ |
| **FR1.2** | Recherche praticien + booking (tab 1) | search providers/slots → `hold` → `POST /appointments` ; bloc + pages liste/détail/créneaux + test. | E.3 (21-23), search ✅ |
| **FR1.3** | Mes RDV (tab 2) | liste upcoming/historique, détail, cancel/modify/checkin, directions/queue ; bloc + pages + test. | E.1 (1-8) |
| **FR1.4** | Messages (tab 3) | conversations + thread + envoi + read ; bloc + 2 pages + test. | 34, conv ✅ |
| **FR1.5** | Documents (tab 4) | liste, upload, download URL signée ; bloc + pages + test. | 35,36,37 |
| **FR1.6** | Profil (tab 5) | compte, couverture/mutuelle, dépendants, consentements, préférences notif ; bloc + pages + test. | 31,32,33 |
| **FR1.7** | Wedge financier | devis liste/détail → signature Yousign → `payments/intent` ; bloc multi-étapes + pages + test. | 39,40, quotes ✅ |
| **FR1.8** | Avis + notifications inbox | submit/list reviews, notifications/reminders ; blocs + pages + test. | 41 |
| **FR1.9** | Retrait `app/` | parité atteinte → supprimer `app/`, MAJ README/PROGRESS. | — |

---

## 3. `app_practicien` (build) — dépend FR0.2→FR0.5

| ID | Feature | Détail | Back |
|---|---|---|---|
| **FR2.1** | Shell praticien + dashboard pro | brancher `ProShell` + routes par destination + dashboard pro. | dashboard ✅ |
| **FR2.2** | Agenda | vue semaine/jour, confirm/start ; bloc + pages + test. | E.2 (12,13), agenda ✅ |
| **FR2.3** | Patients liste + fiche | liste cabinet, fiche (notes, dossier, schéma dentaire) ; bloc + pages + test. | E.2 (16,17), patients ✅ |
| **FR2.4** | Consultation clinique (gated) | acts CCAM, complete ; bloc + page + test. | E.2 (18,19,20) |
| **FR2.5** | Ordonnances (gated) | create + sign ; bloc + page + test. | prescriptions ✅ |
| **FR2.6** | Devis cabinet | create/édit ; bloc + pages + test. | E.5 (27,28) |
| **FR2.7** | Messages cabinet | `/cabinet/conversations` ; bloc + pages + test. | E.6 (29,30) |
| **FR2.8** | Salle d'attente | waiting-room + call-next ; bloc + page + test. | E.2 (14,15) |

---

## 4. `app_secretariat` (build, **zéro clinique**) — dépend FR0.2→FR0.5, réutilise §3

| ID | Feature | Détail | Back |
|---|---|---|---|
| **FR3.1** | Shell secrétariat | `includeClinical:false`, nav admin + test garde de base. | — |
| **FR3.2** | Agenda + gestion RDV | create/confirm/reschedule, slots online ; bloc + pages + test. | E.2 (12), slots ✅ |
| **FR3.3** | Patients (vue admin scoped) | scope secrétariat, sans motif clinique ; bloc + pages + test. | patients ✅ |
| **FR3.4** | Liste d'attente | `/cabinet/waiting-list` offer ; bloc + page + test. | 38, waiting-list ✅ |
| **FR3.5** | Devis cabinet (liste/suivi) | bloc + pages + test. | devis ✅ |
| **FR3.6** | Messages cabinet | réutilise FR2.7 ; câblage + test. | E.6 |
| **FR3.7** | Admin membres + secrétariats | `/cabinet/members` + `/cabinet/secretariats` ; bloc + pages + test. | E.2 (9-11), R12/R13 ✅ |
| **FR3.8** | Test cloisonnement | assert binaire secrétariat n'enregistre **aucun** UC/repo clinique + nav sans entrée clinique. | — |

---

## 5. Transverse / finition

| ID | Tâche | Détail |
|---|---|---|
| **FR4.1** | A2UI transport réel | brancher SSE/WebSocket sur endpoint serveur (aujourd'hui fixture locale). |
| **FR4.2** | Push FCM + `POST /devices` | enregistrement device + deep-links. |
| **FR4.3** | i18n (fr) + états homogènes | états vides/erreur/skeleton via DS sur les 3 apps. |
| **FR4.4** | E2E `integration_test` | parcours clés des 3 apps. |
| **FR4.5** | MAJ doc | `PROGRESS.md` + créer `front/AGENTS.md` + tableau d'état. |

---

## 6. Ordre d'attaque conseillé (planner front)
1. **FR0.1 + FR0.6 + FR0.7** (fondations transverses, parallélisables).
2. **FR0.2 → FR0.3 → FR0.4** (séquentiel, débloque tout le pro) + **FR0.5** en parallèle.
3. Puis les 3 apps **en parallèle** : §2 (patient), §3 (praticien), §4 (secrétariat) — 1 agent par feature, max 15 issues/run.
4. Pour chaque FR consommant une route encore sans handler (colonne « Back » → section E de `web-console/PLAN-ATOMIC.md`) → **créer/prioriser l'issue rust correspondante d'abord** (sinon E2E rouge).
5. **FR4.\*** en finition.

## 7. Definition of Done (par issue FR#)
- 1 deliverable testable livré (bloc OU page OU test), diff ≤200 lignes.
- `dart analyze` + `flutter test` verts (job CI front, FR0.6).
- Branche `agent/front-<id>`, commit FR à l'impératif, CI verte avant merge.
- Issues créées via `scripts/create-front-issues.sh` (source `scripts/front-issues.json`), cap 15/run.
