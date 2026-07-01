# QA Explored Paths

Last run: 2026-07-01T07:25:31.401Z

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
| /login | 2026-06-30 | 2026-07-01T07:26:08.480Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T07:26:14.444Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T07:26:20.044Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T07:26:25.594Z | OK | — |
| / | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /a2ui-demo | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /appointments | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /mes-rdv | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /documents | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /financial | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /profile | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /messaging | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /reviews | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /notifications | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /oubliettes | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T07:26:25.856Z | skip-no-login | login failed |
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
| /login | 2026-06-30 | 2026-07-01T07:28:05.275Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T07:28:10.944Z | OK | — |
| / | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /agenda | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /bookable-slots | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /a2ui-demo | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /salle-attente | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /patients | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /appointments | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /liste-attente | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /devis | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /messages | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /admin-membres | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |
| /admin-secretariats | 2026-06-30 | 2026-07-01T07:28:11.206Z | skip-no-login | login failed |

