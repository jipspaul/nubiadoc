# QA Explored Paths

Last run: 2026-07-01T08:42:22.726Z

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
| /login | 2026-06-30 | 2026-07-01T08:42:59.244Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T08:43:01.276Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T08:43:03.310Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T08:43:05.743Z | OK | — |
| / | 2026-06-30 | 2026-07-01T08:42:53.072Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T08:43:07.887Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T08:43:09.935Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T08:43:11.975Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T08:43:14.008Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T08:43:16.044Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T08:42:55.155Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T08:43:18.076Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T08:42:57.202Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T08:43:20.110Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T08:43:22.141Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T08:43:24.174Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T08:43:49.975Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T08:43:52.007Z | OK | — |
| / | 2026-06-30 | 2026-07-01T08:43:54.039Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T08:43:56.077Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T08:43:45.908Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T08:43:58.108Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T08:44:00.140Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T08:44:02.173Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T08:43:47.941Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T08:44:04.212Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T08:44:06.242Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T08:44:08.275Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T08:44:10.306Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T08:44:32.246Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T08:44:34.273Z | OK | — |
| / | 2026-06-30 | 2026-07-01T08:06:40.824Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T08:06:18.820Z | failed-requests | "Impossible de charger l'agenda" — #3050 open |
| /bookable-slots | 2026-06-30 | 2026-07-01T08:06:44.114Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T08:06:47.399Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T08:06:50.683Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T08:06:53.971Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T08:06:57.262Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T08:07:00.547Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T08:06:22.119Z | failed-requests | "Impossible de charger les devis" — #3056 open |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T08:06:25.396Z | failed-requests | "Impossible de charger les devis" — related to #3056 |
| /messages | 2026-06-30 | 2026-07-01T08:07:03.834Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T08:07:07.134Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T08:07:10.430Z | OK | — |
