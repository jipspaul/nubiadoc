# QA Explored Paths

Last run: 2026-06-29T08:28:38.888Z

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
| / | 2026-06-28 | 2026-06-29T08:27:32.373Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T08:27:34.470Z | OK | — |
| /mes-rdv | 2026-06-28 | 2026-06-29T08:27:36.603Z | OK | — |
| /documents | 2026-06-28 | 2026-06-29T08:27:38.675Z | OK | — |
| /financial | 2026-06-28 | 2026-06-29T08:27:40.751Z | OK | — |
| /profile | 2026-06-29 | 2026-06-29T08:27:42.819Z | OK | — |
| /messaging | 2026-06-29 | 2026-06-29T08:27:44.883Z | OK | — |
| /notifications | 2026-06-29 | 2026-06-29T08:27:46.951Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:27:58.310Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T08:28:00.386Z | OK | — |
| /waiting-room | 2026-06-28 | 2026-06-29T08:28:02.455Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T08:28:04.571Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T08:28:06.667Z | OK | — |
| /consultation | 2026-06-28 | 2026-06-29T08:28:08.753Z | OK | — |
| /ordonnances | 2026-06-29 | 2026-06-29T08:28:10.929Z | OK | — |
| /ordonnances/new | 2026-06-28 | 2026-06-29T08:28:12.985Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:28:24.312Z | OK | — |
| /salle-attente | 2026-06-29 | 2026-06-29T08:28:26.384Z | OK | — |
| /bookable-slots | 2026-06-24 | 2026-06-29T08:28:28.448Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T08:28:30.524Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T08:28:32.607Z | OK | — |
| /liste-attente | 2026-06-28 | 2026-06-29T08:28:34.680Z | OK | — |
| /devis | 2026-06-24 | 2026-06-29T08:28:36.749Z | OK | — |
| /admin-membres | 2026-06-29 | 2026-06-29T08:28:38.821Z | OK | — |
