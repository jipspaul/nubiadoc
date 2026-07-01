# QA Explored Paths

Last run: 2026-07-01T09:00:57.243Z

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
| /login | 2026-06-30 | 2026-07-01T09:01:31.134Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T09:01:33.904Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T09:01:36.649Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T09:01:39.435Z | OK | — |
| / | 2026-06-30 | 2026-07-01T09:01:22.823Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T09:01:42.185Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T09:01:44.934Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T09:01:47.701Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T09:01:50.461Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T09:01:53.221Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T09:01:25.566Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T09:01:56.008Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T09:01:28.300Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T09:01:58.784Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T09:02:01.545Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T09:02:04.358Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:02:52.193Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T09:02:55.078Z | OK | — |
| / | 2026-06-30 | 2026-07-01T07:26:50.894Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T07:26:53.678Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T07:26:56.467Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T07:26:59.266Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T07:27:02.062Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T07:27:04.845Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T07:27:07.629Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T07:27:10.416Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T07:27:13.218Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T07:27:16.010Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T07:27:18.793Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:03:46.103Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T09:03:48.963Z | OK | — |
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
