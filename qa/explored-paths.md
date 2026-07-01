# QA Explored Paths

Last run: 2026-07-01T09:24:19.460Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` | faux positif — ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré | faux positif — ferme #2920-#2935 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:25:21.981Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T09:25:24.782Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T09:25:27.644Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T09:25:30.554Z | OK | — |
| / | 2026-06-30 | 2026-07-01T09:25:13.557Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T09:25:33.378Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T09:25:36.181Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T09:25:38.963Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T09:25:41.827Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T09:25:44.697Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T09:25:16.346Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T09:25:47.530Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T09:25:19.126Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T09:25:50.355Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T09:25:53.140Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T09:25:55.895Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:26:43.184Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T09:26:46.263Z | OK | — |
| / | 2026-06-30 | 2026-07-01T09:26:49.269Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T09:26:52.288Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T09:26:37.278Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T09:26:55.268Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T09:26:58.259Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T09:27:01.474Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T09:26:40.047Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T09:27:04.367Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T09:27:07.167Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T09:27:09.964Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T09:27:12.769Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:28:07.026Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T09:28:09.846Z | OK | — |
| / | 2026-06-30 | 2026-07-01T09:28:12.810Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T09:27:58.459Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T09:28:15.703Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T09:28:18.888Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T09:28:21.928Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T09:28:25.068Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T09:28:28.020Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T09:28:30.911Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T09:28:01.342Z | OK | — |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T09:28:04.190Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T09:28:33.746Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T09:28:36.660Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T09:28:39.665Z | OK | — |
