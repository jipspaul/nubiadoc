# QA Explored Paths

Last run: 2026-07-01T07:36:28.017Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré (canvas blanc) | faux positif — ferme #2920-#2935. Naviger via location.hash (in-page, sans page.goto) |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T07:36:50.440Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T07:36:56.002Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T07:37:01.570Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T07:37:07.135Z | OK | — |
| / | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /a2ui-demo | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /appointments | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /mes-rdv | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /documents | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /financial | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /profile | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /messaging | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /reviews | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /notifications | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /oubliettes | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T07:36:45.078Z | skip-no-login | login failed run2 |
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
| /login | 2026-06-30 | 2026-07-01T07:37:29.872Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T07:37:35.400Z | OK | — |
| / | 2026-06-30 | 2026-07-01T07:37:24.548Z | skip-no-login | login failed run2 |
| /agenda | 2026-06-30 | 2026-07-01T07:37:24.548Z | skip-no-login | login failed run2 |
| /bookable-slots | 2026-06-30 | 2026-07-01T07:37:24.548Z | skip-no-login | login failed run2 |
| /a2ui-demo | 2026-06-30 | 2026-07-01T07:37:24.548Z | skip-no-login | login failed run2 |
| /salle-attente | 2026-06-30 | 2026-07-01T07:37:24.548Z | skip-no-login | login failed run2 |
| /patients | 2026-06-30 | 2026-07-01T07:37:24.548Z | skip-no-login | login failed run2 |
| /appointments | 2026-06-30 | 2026-07-01T07:37:24.549Z | skip-no-login | login failed run2 |
| /liste-attente | 2026-06-30 | 2026-07-01T07:37:24.549Z | skip-no-login | login failed run2 |
| /devis | 2026-06-30 | 2026-07-01T07:37:24.549Z | skip-no-login | login failed run2 |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T07:37:24.549Z | skip-no-login | login failed run2 |
| /messages | 2026-06-30 | 2026-07-01T07:37:24.549Z | skip-no-login | login failed run2 |
| /admin-membres | 2026-06-30 | 2026-07-01T07:37:24.549Z | skip-no-login | login failed run2 |
| /admin-secretariats | 2026-06-30 | 2026-07-01T07:37:24.549Z | skip-no-login | login failed run2 |

