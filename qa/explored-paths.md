# QA Explored Paths

Last run: 2026-07-01T14:01:53.952Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu — BlocBuilder exhaustif | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu — OrdonnancesPage | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré | faux positif — ferme #2920-#2935. Naviger via location.hash |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:55:39.892Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T14:01:53.952Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /book | 2026-06-30 | 2026-07-01T11:56:02.303Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T14:01:53.952Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /financial | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /forgot-password | 2026-07-01 | 2026-07-01T14:01:53.952Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T14:01:53.952Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /messaging | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /notifications | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /oubliettes | 2026-06-30 | 2026-07-01T11:55:58.219Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T11:56:00.263Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T14:01:53.952Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /signup | 2026-06-30 | 2026-07-01T14:01:53.952Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T14:01:53.952Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /a2ui-demo | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /agenda | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /cabinet-setup | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /consultation | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /login | 2026-06-30 | 2026-07-01T14:01:53.952Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /ordonnances | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /ordonnances/new | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /patients | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /register-pro | 2026-06-30 | 2026-07-01T14:01:53.952Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T14:01:53.952Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /a2ui-demo | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /admin-membres | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /admin-secretariats | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /agenda | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /appointments | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /bookable-slots | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /devis | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /liste-attente | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /login | 2026-06-30 | 2026-07-01T14:01:53.952Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /onboard | 2026-06-30 | 2026-07-01T14:01:53.952Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /salle-attente | 2026-06-30 | 2026-07-01T14:01:53.952Z | navigation | login_failed |
| /splash | 2026-07-01 | 2026-07-01T14:01:53.952Z | OK | — |
