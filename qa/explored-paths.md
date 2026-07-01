# QA Explored Paths

Last run: 2026-07-01T11:54:32.530Z

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
| / | 2026-06-30 | 2026-07-01T11:55:37.832Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:55:39.892Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T11:55:21.732Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T11:55:41.936Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T11:56:02.303Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T11:55:23.771Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T11:55:45.996Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T11:55:48.028Z | OK | — |
| /forgot-password | 2026-07-01 | 2026-07-01T11:55:27.681Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T11:55:15.714Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T11:55:43.966Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T11:55:52.099Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T11:55:56.182Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T11:55:58.219Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T11:55:50.068Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T11:56:00.263Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T11:55:31.767Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T11:55:54.146Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T11:55:19.696Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T11:55:35.765Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-07-01T11:56:51.680Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:57:10.009Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T11:56:53.738Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T11:57:12.046Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T11:57:03.910Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T11:56:41.661Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T11:57:01.882Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T11:57:05.944Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T11:57:07.977Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T11:56:57.810Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T11:56:59.843Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T11:56:45.613Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T11:56:49.645Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T11:56:55.777Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-07-01T11:57:59.263Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:58:05.358Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T11:58:21.645Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T11:58:23.705Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T11:58:01.292Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T11:58:11.476Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T11:58:03.329Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T11:58:15.545Z | OK | — |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T11:58:17.581Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T11:58:13.511Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T11:57:49.076Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T11:58:19.608Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T11:57:57.219Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T11:58:09.426Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T11:58:07.391Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T11:57:53.127Z | OK | — |

