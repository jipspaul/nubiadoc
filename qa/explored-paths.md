# QA Explored Paths

Last run: 2026-07-01T09:53:10.915Z

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
| /login | 2026-06-30 | 2026-07-01T09:54:04.143Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T09:54:09.743Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /coverage-setup | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| / | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /a2ui-demo | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /appointments | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /mes-rdv | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /documents | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /financial | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /profile | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /messaging | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /reviews | 2026-06-30 | 2026-07-01T09:54:10.006Z | skip-no-login | login failed |
| /notifications | 2026-06-30 | 2026-07-01T09:25:50.355Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T09:25:53.140Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T09:25:55.895Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T09:53:47.461Z | OK | — |
| /forgot-password | 2026-07-01 | 2026-07-01T09:53:52.956Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T09:53:58.519Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:54:32.329Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T09:54:37.992Z | OK | — |
| / | 2026-06-30 | 2026-07-01T09:54:38.250Z | skip-no-login | login failed |
| /agenda | 2026-06-30 | 2026-07-01T09:54:38.250Z | skip-no-login | login failed |
| /waiting-room | 2026-06-30 | 2026-07-01T09:54:38.250Z | skip-no-login | login failed |
| /patients | 2026-06-30 | 2026-07-01T09:54:38.251Z | skip-no-login | login failed |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T09:54:38.251Z | skip-no-login | login failed |
| /messages | 2026-06-30 | 2026-07-01T09:54:38.251Z | skip-no-login | login failed |
| /consultation | 2026-06-30 | 2026-07-01T09:54:38.251Z | skip-no-login | login failed |
| /ordonnances | 2026-06-30 | 2026-07-01T09:54:38.251Z | skip-no-login | login failed |
| /ordonnances/new | 2026-06-30 | 2026-07-01T09:54:38.251Z | skip-no-login | login failed |
| /a2ui-demo | 2026-06-30 | 2026-07-01T09:54:38.251Z | skip-no-login | login failed |
| /cabinet-setup | 2026-06-30 | 2026-07-01T09:54:38.251Z | skip-no-login | login failed |
| /splash | 2026-07-01 | 2026-07-01T09:54:26.738Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:55:29.886Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T09:55:35.494Z | OK | — |
| / | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /agenda | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /bookable-slots | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /a2ui-demo | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /salle-attente | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /patients | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /appointments | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /liste-attente | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /devis | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /messages | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /admin-membres | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /admin-secretariats | 2026-06-30 | 2026-07-01T09:55:35.750Z | skip-no-login | login failed |
| /splash | 2026-07-01 | 2026-07-01T09:55:24.441Z | OK | — |

