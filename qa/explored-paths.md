# QA Explored Paths

Last run: 2026-06-29T08:24:57.283Z

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
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré (canvas blanc) | faux positif — ferme #2920-#2935. Naviger via page.goto() |


## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:23:50.862Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T08:23:52.939Z | OK | — |
| /mes-rdv | 2026-06-28 | 2026-06-29T08:23:55.002Z | OK | — |
| /financial | 2026-06-28 | 2026-06-29T08:23:57.065Z | OK | — |
| /profile | 2026-06-29 | 2026-06-29T08:23:59.162Z | OK | — |
| /messaging | 2026-06-29 | 2026-06-29T08:24:01.228Z | OK | — |
| /notifications | 2026-06-29 | 2026-06-29T08:24:03.294Z | OK | — |
| /reviews | 2026-06-29 | 2026-06-29T08:24:05.363Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:24:16.561Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T08:24:18.626Z | OK | — |
| /waiting-room | 2026-06-28 | 2026-06-29T08:24:20.695Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T08:24:22.761Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T08:24:24.823Z | OK | — |
| /consultation | 2026-06-28 | 2026-06-29T08:24:26.876Z | OK | — |
| /ordonnances | 2026-06-29 | 2026-06-29T08:24:28.929Z | OK | — |
| /ordonnances/new | 2026-06-28 | 2026-06-29T08:24:30.975Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:24:42.800Z | OK | — |
| /salle-attente | 2026-06-29 | 2026-06-29T08:24:44.859Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T08:24:46.925Z | OK | — |
| /devis | 2026-06-24 | 2026-06-29T08:24:48.991Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T08:24:51.058Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T08:24:53.122Z | OK | — |
| /admin-membres | 2026-06-29 | 2026-06-29T08:24:55.191Z | OK | — |
| /admin-secretariats | 2026-06-29 | 2026-06-29T08:24:57.262Z | OK | — |
