# QA Explored Paths

Last run: 2026-07-01T07:58:05.980Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` | faux positif — ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré | faux positif — ferme #2920-#2935 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T07:59:05.634Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T07:59:11.783Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T07:59:17.884Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T07:59:24.050Z | OK | — |
| / | 2026-06-30 | 2026-07-01T07:58:22.852Z | blank-canvas | blank-canvas |
| /a2ui-demo | 2026-06-30 | 2026-07-01T07:58:26.137Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T07:58:29.420Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T07:58:32.720Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T07:58:36.016Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T07:58:39.301Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T07:58:42.607Z | blank-canvas | blank-canvas |
| /messaging | 2026-06-30 | 2026-07-01T07:58:46.166Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T07:58:49.454Z | blank-canvas | blank-canvas |
| /notifications | 2026-06-30 | 2026-07-01T07:58:53.004Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T07:58:56.303Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T07:58:59.582Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T07:26:42.527Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T07:26:48.111Z | OK | — |
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
| /login | 2026-06-30 | 2026-07-01T08:00:27.266Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T08:00:33.346Z | OK | — |
| / | 2026-06-30 | 2026-07-01T07:59:41.443Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T07:59:44.734Z | blank-canvas | blank-canvas |
| /bookable-slots | 2026-06-30 | 2026-07-01T07:59:48.017Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T07:59:51.316Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T07:59:54.602Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T07:59:57.880Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T08:00:01.164Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T08:00:04.467Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T08:00:07.778Z | blank-canvas | blank-canvas |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T08:00:11.064Z | blank-canvas | blank-canvas |
| /messages | 2026-06-30 | 2026-07-01T08:00:14.613Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T08:00:17.898Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T08:00:21.207Z | OK | — |

