# QA Explored Paths

Last run: 2026-07-01T10:02:59.878Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu — BlocBuilder exhaustif, try/catch, GetIt enregistré, flutter analyze vert | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu — OrdonnancesPage, BlocBuilder exhaustif, GetIt, flutter analyze vert | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré (canvas blanc) | faux positif — ferme #2920-#2935. Naviger via location.hash (in-page, sans page.goto) |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T10:04:28.965Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T10:04:34.466Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T10:03:38.568Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T10:03:41.353Z | OK | — |
| / | 2026-06-30 | 2026-07-01T10:03:44.158Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T10:03:46.975Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T10:03:49.766Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T10:03:52.549Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T10:03:55.341Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T10:03:58.137Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T10:04:00.937Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T10:04:03.733Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T10:04:06.514Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T09:25:50.355Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T09:25:53.140Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T09:25:55.895Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T10:04:12.115Z | OK | — |
| /forgot-password | 2026-07-01 | 2026-07-01T10:04:17.631Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T10:04:23.249Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T10:05:32.997Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T10:05:38.629Z | OK | — |
| / | 2026-06-30 | 2026-07-01T10:04:53.678Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T10:04:56.466Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T10:04:59.264Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T10:05:02.071Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T10:05:04.868Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T10:05:07.691Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T10:05:10.496Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T10:05:13.282Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T10:05:16.071Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T10:05:18.851Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T10:05:21.656Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T10:05:27.367Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T10:06:45.594Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T10:06:51.124Z | OK | — |
| / | 2026-06-30 | 2026-07-01T10:06:00.785Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T10:06:03.581Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T10:06:06.364Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T10:06:09.178Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T10:06:11.965Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T10:06:14.742Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T10:06:17.608Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T10:06:20.426Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T10:06:23.232Z | OK | — |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T10:06:26.030Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T10:06:28.811Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T10:06:31.596Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T10:06:34.397Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T10:06:39.975Z | OK | — |

