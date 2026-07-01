# QA Explored Paths

Last run: 2026-07-01T11:15:29.704Z

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
| /login | 2026-06-30 | 2026-07-01T11:13:27.664Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T11:13:21.563Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T11:13:23.598Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T11:13:25.631Z | OK | — |
| / | 2026-06-30 | 2026-07-01T11:13:35.798Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:13:37.829Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T11:13:39.865Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T11:13:41.896Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T11:13:43.929Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T11:13:45.962Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T11:13:47.996Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T11:13:50.031Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T11:13:52.066Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T11:13:54.099Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T11:13:56.128Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T11:13:58.161Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T11:14:00.195Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T11:13:33.764Z | OK | — |
| /forgot-password | 2026-07-01 | 2026-07-01T11:13:29.705Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T11:13:31.729Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T11:14:18.464Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T11:14:16.434Z | OK | — |
| / | 2026-06-30 | 2026-07-01T11:14:22.531Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T11:14:24.565Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T11:14:26.601Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T11:14:28.631Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T11:14:30.663Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T11:14:32.694Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T11:14:34.727Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T11:14:36.761Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T11:14:38.794Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:14:40.836Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T11:14:42.860Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T11:14:20.493Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T11:14:59.165Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T11:15:01.212Z | OK | — |
| / | 2026-06-30 | 2026-07-01T11:15:05.277Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T11:15:07.309Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T11:15:09.343Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:15:11.379Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T11:15:13.428Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T11:15:15.462Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T11:15:17.491Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T11:15:19.525Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T11:15:21.557Z | OK | — |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T11:15:23.593Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T11:15:25.624Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T11:15:27.660Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T11:15:29.691Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T11:15:03.247Z | OK | — |
