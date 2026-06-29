# QA Explored Paths

Last run: 2026-06-29T19:26:06.211Z

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
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré (canvas blanc) | faux positif — ferme #2920-#2935. Naviger via page.goto() avec /#/route |


## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T19:24:58.630Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T19:25:00.664Z | OK | — |
| /mes-rdv | 2026-06-28 | 2026-06-29T19:25:02.697Z | OK | — |
| /documents | 2026-06-28 | 2026-06-29T19:25:04.747Z | OK | — |
| /financial | 2026-06-28 | 2026-06-29T19:25:06.798Z | OK | — |
| /profile | 2026-06-29 | 2026-06-29T19:25:08.859Z | OK | — |
| /reviews | 2026-06-29 | 2026-06-29T19:25:10.929Z | OK | — |
| /book | 2026-06-29 | 2026-06-29T19:25:12.968Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T19:25:25.428Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T19:25:27.462Z | OK | — |
| /waiting-room | 2026-06-28 | 2026-06-29T19:25:29.496Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T19:25:31.534Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T19:25:33.576Z | OK | — |
| /consultation | 2026-06-28 | 2026-06-29T19:25:35.613Z | OK | — |
| /ordonnances | 2026-06-29 | 2026-06-29T19:25:37.644Z | OK | — |
| /cabinet-setup | 2026-06-29 | 2026-06-29T19:25:39.700Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T19:25:51.687Z | OK | — |
| /salle-attente | 2026-06-29 | 2026-06-29T19:25:53.794Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T19:25:55.870Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T19:25:57.930Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T19:25:59.960Z | OK | — |
| /liste-attente | 2026-06-28 | 2026-06-29T19:26:01.993Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T19:26:04.053Z | OK | — |
| /admin-secretariats | 2026-06-29 | 2026-06-29T19:26:06.145Z | OK | — |
