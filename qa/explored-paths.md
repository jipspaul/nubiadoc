# QA Explored Paths

Last run: 2026-07-01T11:10:27.619Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu — BlocBuilder exhaustif, try/catch, GetIt enregistré | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu — OrdonnancesPage, BlocBuilder exhaustif, GetIt | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré (canvas blanc) | faux positif — ferme #2920-#2935. Naviger via location.hash (in-page, sans page.goto) |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T11:09:05.274Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T11:08:59.174Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T11:09:01.208Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T11:09:03.240Z | OK | — |
| / | 2026-06-30 | 2026-07-01T11:09:13.426Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:09:15.458Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T11:09:17.491Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T11:09:19.524Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T11:09:21.555Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T11:09:23.590Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T11:09:25.623Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T11:09:27.664Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T11:09:29.709Z | OK | — |
| /notifications | 2026-06-30 | ? | pending | — |
| /oubliettes | 2026-06-30 | ? | pending | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | ? | pending | — |
| /book | 2026-06-30 | ? | pending | — |
| /splash | 2026-07-01 | 2026-07-01T11:09:11.393Z | OK | — |
| /forgot-password | 2026-07-01 | 2026-07-01T11:09:07.325Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T11:09:09.356Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T11:09:47.938Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T11:09:45.905Z | OK | — |
| / | 2026-06-30 | 2026-07-01T11:09:52.008Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T11:09:54.039Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T11:09:56.073Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T11:09:58.106Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T11:10:00.139Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T11:10:02.174Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T11:10:04.207Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T11:10:06.238Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T11:10:08.271Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:10:10.306Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T11:10:12.340Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T11:09:49.975Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | ? | pending | — |
| /onboard | 2026-06-30 | ? | pending | — |
| / | 2026-06-30 | ? | pending | — |
| /agenda | 2026-06-30 | ? | pending | — |
| /bookable-slots | 2026-06-30 | ? | pending | — |
| /a2ui-demo | 2026-06-30 | ? | pending | — |
| /salle-attente | 2026-06-30 | ? | pending | — |
| /patients | 2026-06-30 | ? | pending | — |
| /appointments | 2026-06-30 | ? | pending | — |
| /liste-attente | 2026-06-30 | ? | pending | — |
| /devis | 2026-06-30 | ? | pending | — |
| /devis/test-devis-id | 2026-06-30 | ? | pending | — |
| /messages | 2026-06-30 | ? | pending | — |
| /admin-membres | 2026-06-30 | ? | pending | — |
| /admin-secretariats | 2026-06-30 | ? | pending | — |
| /splash | 2026-07-01 | ? | pending | — |
