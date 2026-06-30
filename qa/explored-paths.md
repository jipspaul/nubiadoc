# QA Explored Paths

Last run: 2026-06-30T12:11:03.658Z

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
| / | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /appointments | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /documents | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /financial | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /profile | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /messaging | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /reviews | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /agenda | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /patients | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /messages | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /consultation | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /agenda | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /appointments | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /patients | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |
| /devis | 2026-06-30 | 2026-06-30T12:11:03.658Z | OK | — |

