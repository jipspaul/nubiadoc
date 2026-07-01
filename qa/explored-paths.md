# QA Explored Paths

Last run: 2026-07-01T10:59:01.143Z

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
| /login | 2026-06-30 | ? | pending | — |
| /signup | 2026-06-30 | ? | pending | — |
| /account-setup | 2026-06-30 | ? | pending | — |
| /coverage-setup | 2026-06-30 | ? | pending | — |
| / | 2026-06-30 | ? | pending | — |
| /a2ui-demo | 2026-06-30 | ? | pending | — |
| /appointments | 2026-06-30 | ? | pending | — |
| /mes-rdv | 2026-06-30 | ? | pending | — |
| /documents | 2026-06-30 | ? | pending | — |
| /financial | 2026-06-30 | ? | pending | — |
| /profile | 2026-06-30 | ? | pending | — |
| /messaging | 2026-06-30 | ? | pending | — |
| /reviews | 2026-06-30 | ? | pending | — |
| /notifications | 2026-06-30 | ? | pending | — |
| /oubliettes | 2026-06-30 | ? | pending | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | ? | pending | — |
| /book | 2026-06-30 | ? | pending | — |
| /splash | 2026-07-01 | ? | pending | — |
| /forgot-password | 2026-07-01 | ? | pending | — |
| /reset-password | 2026-07-01 | ? | pending | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | ? | pending | — |
| /register-pro | 2026-06-30 | ? | pending | — |
| / | 2026-06-30 | ? | pending | — |
| /agenda | 2026-06-30 | ? | pending | — |
| /waiting-room | 2026-06-30 | ? | pending | — |
| /patients | 2026-06-30 | ? | pending | — |
| /patients/test-patient-id | 2026-06-30 | ? | pending | — |
| /messages | 2026-06-30 | ? | pending | — |
| /consultation | 2026-06-30 | ? | pending | — |
| /ordonnances | 2026-06-30 | ? | pending | — |
| /ordonnances/new | 2026-06-30 | ? | pending | — |
| /a2ui-demo | 2026-06-30 | ? | pending | — |
| /cabinet-setup | 2026-06-30 | ? | pending | — |
| /splash | 2026-07-01 | ? | pending | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | ? | pending | — |
| /onboard | 2026-06-30 | ? | pending | — |
| / | 2026-06-30 | ? | pending | — |
| /agenda | 2026-06-30 | ? | pending | — |
| /bookable-slots | 2026-06-30 | ? | pending | — |
| /a2ui-demo | 2026-06-30 | ? | pending | — |
| /salle-attente | 2026-06-30 | ? | pending | — |
| /patients | 2026-06-30 | ? | pending | — |
| /appointments | 2026-06-30 | ? | pending | — |
| /liste-attente | 2026-06-30 | ? | pending | — |
| /devis | 2026-06-30 | ? | pending | — |
| /devis/test-devis-id | 2026-06-30 | ? | pending | — |
| /messages | 2026-06-30 | ? | pending | — |
| /admin-membres | 2026-06-30 | ? | pending | — |
| /admin-secretariats | 2026-06-30 | ? | pending | — |
| /splash | 2026-07-01 | ? | pending | — |
