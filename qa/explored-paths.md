# QA Explored Paths

Last run: 2026-06-29T04:10:40.468Z

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
| / | 2026-06-28 | 2026-06-29T03:55:34.901Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T03:55:38.769Z | OK | — |
| /mes-rdv | 2026-06-28 | 2026-06-29T03:55:43.160Z | OK | — |
| /documents | 2026-06-28 | 2026-06-29T03:55:47.488Z | OK | — |
| /financial | 2026-06-28 | 2026-06-29T03:55:51.737Z | OK | — |
| /profile | 2026-06-29 | 2026-06-29T03:55:55.682Z | OK | — |
| /messaging | 2026-06-28 | 2026-06-29T04:00:13.702Z | OK | — |
| /book | 2026-06-29 | 2026-06-29T04:00:17.098Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T04:00:44.487Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T04:00:49.917Z | OK | — |
| /waiting-room | 2026-06-28 | 2026-06-29T04:00:53.865Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T04:00:57.770Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T04:01:01.054Z | OK | — |
| /consultation | 2026-06-28 | 2026-06-29T04:01:04.298Z | OK | — |
| /ordonnances | 2026-06-29 | 2026-06-29T04:01:08.758Z | OK | — |
| /ordonnances/new | 2026-06-28 | 2026-06-29T04:01:14.528Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T04:01:43.309Z | OK | — |
| /salle-attente | 2026-06-29 | 2026-06-29T04:01:46.717Z | OK | — |
| /bookable-slots | 2026-06-24 | 2026-06-29T04:10:15.207Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T04:10:18.776Z | OK | — |
| /devis | 2026-06-24 | 2026-06-29T04:10:24.246Z | OK | — |
| /liste-attente | 2026-06-28 | 2026-06-29T04:10:29.301Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T04:10:36.014Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T04:10:40.310Z | OK | — |
