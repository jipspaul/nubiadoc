# QA Explored Paths

Last run: 2026-07-01T06:19:01.634Z

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
| /login | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| / | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| / | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| / | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T06:23:54.528Z | OK | — |
