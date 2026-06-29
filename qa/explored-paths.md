# QA Explored Paths

Last run: 2026-06-29T08:11:50.014Z

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
| / | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /appointments | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /mes-rdv | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /documents | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /financial | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /profile | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /reviews | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /notifications | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /agenda | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /waiting-room | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /patients | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /messages | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /consultation | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /ordonnances | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /ordonnances/new | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /salle-attente | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /bookable-slots | 2026-06-24 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /patients | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /devis | 2026-06-24 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /liste-attente | 2026-06-28 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /appointments | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
| /admin-membres | 2026-06-29 | 2026-06-29T08:11:50.014Z | login_failed | no login form |
