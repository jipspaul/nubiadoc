# QA Explored Paths

Last run: 2026-06-27T05:59

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
| / | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /appointments | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /mes-rdv | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /documents | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /financial | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /profile | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /notifications | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /reviews | 2026-06-27 | 2026-06-27T05:59 | login_failed | No input found for email |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /agenda | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /patients | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /messages | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /consultation | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /ordonnances | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /waiting-room | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /ordonnances/new | 2026-06-27 | 2026-06-27T05:59 | login_failed | No input found for email |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /agenda | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /bookable-slots | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /patients | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /appointments | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /devis | 2026-06-24 | 2026-06-27T05:59 | login_failed | No input found for email |
| /messages | 2026-06-27 | 2026-06-27T05:59 | login_failed | No input found for email |
| /admin-membres | 2026-06-27 | 2026-06-27T05:59 | login_failed | No input found for email |
