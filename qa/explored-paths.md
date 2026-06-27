# QA Explored Paths

Last run: 2026-06-27T02:03

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — feature complète, ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — feature complète, ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu — BlocBuilder exhaustif, try/catch, GetIt enregistré, flutter analyze vert | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu — OrdonnancesPage, BlocBuilder exhaustif, GetIt, flutter analyze vert | ferme #2853 #2854 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /appointments | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /mes-rdv | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /documents | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /financial | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /profile | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /messaging | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /notifications | 2026-06-24 | 2026-06-27T02:03 | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /agenda | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /patients | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /messages | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /consultation | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /ordonnances | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /waiting-room | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /a2ui-demo | 2026-06-24 | 2026-06-27T02:03 | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /agenda | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /appointments | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /bookable-slots | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /devis | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /liste-attente | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /patients | 2026-06-24 | 2026-06-27T02:03 | OK | — |
| /salle-attente | 2026-06-24 | 2026-06-27T02:03 | OK | — |

