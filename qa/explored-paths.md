# QA Explored Paths

Last run: 2026-07-01T14:16:46.121Z

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
| / | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T11:55:39.892Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T11:56:02.303Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /forgot-password | 2026-07-01 | 2026-07-01T14:16:46.121Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T11:55:58.219Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T11:56:00.263Z | OK | — |
| /reset-password | 2026-07-01 | 2026-07-01T14:16:46.121Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T14:16:46.121Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T14:16:46.121Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /login | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T14:16:46.121Z | OK | — |
| /splash | 2026-07-01 | 2026-07-01T14:16:46.121Z | OK | — |
