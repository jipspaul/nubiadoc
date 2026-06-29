# QA Explored Paths

Last run: 2026-06-29T18:52:12.935Z

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
| /reviews | 2026-06-29 | 2026-06-29T08:49:23.320Z | OK | — |
| /notifications | 2026-06-29 | 2026-06-29T08:49:23.320Z | OK | — |
| /messaging | 2026-06-29 | 2026-06-29T18:21:33.433Z | OK | — |
| /oubliettes | 2026-06-29 | 2026-06-29T18:21:33.433Z | OK | — |
| / | 2026-06-28 | 2026-06-29T18:51:04.895Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T18:51:06.989Z | OK | — |
| /mes-rdv | 2026-06-28 | 2026-06-29T18:51:09.097Z | OK | — |
| /documents | 2026-06-28 | 2026-06-29T18:51:11.217Z | OK | — |
| /financial | 2026-06-28 | 2026-06-29T18:51:13.330Z | OK | — |
| /profile | 2026-06-29 | 2026-06-29T18:51:15.423Z | OK | — |
| /a2ui-demo | 2026-06-29 | 2026-06-29T18:51:17.519Z | OK | — |
| /book | 2026-06-29 | 2026-06-29T18:51:19.618Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /ordonnances/new | 2026-06-28 | 2026-06-29T08:49:23.320Z | OK | — |
| /a2ui-demo | 2026-06-29 | 2026-06-29T18:21:33.433Z | OK | — |
| /register-pro | 2026-06-29 | 2026-06-29T18:21:33.433Z | OK | — |
| / | 2026-06-28 | 2026-06-29T18:51:31.391Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T18:51:33.494Z | OK | — |
| /waiting-room | 2026-06-28 | 2026-06-29T18:51:35.622Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T18:51:37.725Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T18:51:39.821Z | OK | — |
| /consultation | 2026-06-28 | 2026-06-29T18:51:41.922Z | OK | — |
| /cabinet-setup | 2026-06-29 | 2026-06-29T18:51:44.030Z | OK | — |
| /ordonnances | 2026-06-29 | 2026-06-29T18:51:46.124Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /liste-attente | 2026-06-28 | 2026-06-29T08:49:23.320Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T18:21:33.433Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T18:21:33.433Z | OK | — |
| / | 2026-06-28 | 2026-06-29T18:51:58.191Z | OK | — |
| /salle-attente | 2026-06-29 | 2026-06-29T18:52:00.295Z | OK | — |
| /bookable-slots | 2026-06-24 | 2026-06-29T18:52:02.392Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T18:52:04.493Z | OK | — |
| /devis | 2026-06-24 | 2026-06-29T18:52:06.596Z | OK | — |
| /admin-membres | 2026-06-29 | 2026-06-29T18:52:08.714Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T18:52:10.800Z | OK | — |
| /admin-secretariats | 2026-06-29 | 2026-06-29T18:52:12.911Z | OK | — |

