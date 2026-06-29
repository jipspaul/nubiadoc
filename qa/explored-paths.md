# QA Explored Paths

Last run: 2026-06-29T08:28:53.490Z

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
| / | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /appointments | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /mes-rdv | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /documents | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /financial | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /profile | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /reviews | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /notifications | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /agenda | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /waiting-room | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /patients | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /messages | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /consultation | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /ordonnances | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /ordonnances/new | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /salle-attente | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /bookable-slots | 2026-06-24 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /patients | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /devis | 2026-06-24 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /liste-attente | 2026-06-28 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /appointments | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
| /admin-membres | 2026-06-29 | 2026-06-29T08:28:53.490Z | login_failed | login failed |
