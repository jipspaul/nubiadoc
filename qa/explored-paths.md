# QA Explored Paths

Last run: 2026-06-28T17:18

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
| / | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /appointments | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /mes-rdv | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /documents | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /financial | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /profile | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /notifications | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /reviews | 2026-06-27 | 2026-06-28T17:18 | login_failed | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /agenda | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /patients | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /messages | 2026-06-27 | 2026-06-28T17:18 | login_failed | — |
| /consultation | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /ordonnances | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /waiting-room | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /ordonnances/new | 2026-06-27 | 2026-06-28T17:18 | login_failed | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /agenda | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /bookable-slots | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /patients | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /appointments | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /devis | 2026-06-24 | 2026-06-28T17:18 | login_failed | — |
| /messages | 2026-06-27 | 2026-06-28T17:18 | login_failed | — |
| /admin-membres | 2026-06-27 | 2026-06-28T17:18 | login_failed | — |

