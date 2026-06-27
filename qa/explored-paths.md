# QA Explored Paths

Last run: 2026-06-27T06:34

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
| / | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /appointments | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /mes-rdv | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /documents | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /financial | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /profile | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /notifications | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /reviews | 2026-06-27 | 2026-06-27T06:34 | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /agenda | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /patients | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /messages | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /consultation | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /ordonnances | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /waiting-room | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /ordonnances/new | 2026-06-27 | 2026-06-27T06:34 | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /agenda | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /bookable-slots | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /patients | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /appointments | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /devis | 2026-06-24 | 2026-06-27T06:34 | OK | — |
| /messages | 2026-06-27 | 2026-06-27T06:34 | OK | — |
| /admin-membres | 2026-06-27 | 2026-06-27T06:34 | OK | — |
