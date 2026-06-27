# QA Explored Paths

Last run: 2026-06-27T06:11

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
| / | 2026-06-24 | 2026-06-27T06:11 | login_failed | No inputs found (tag=BODY) |
| /appointments | 2026-06-24 | 2026-06-27T06:11 | login_failed | No inputs found (tag=BODY) |
| /mes-rdv | 2026-06-24 | 2026-06-27T06:11 | login_failed | No inputs found (tag=BODY) |
| /documents | 2026-06-24 | 2026-06-27T06:11 | login_failed | No inputs found (tag=BODY) |
| /financial | 2026-06-24 | 2026-06-27T06:11 | login_failed | No inputs found (tag=BODY) |
| /profile | 2026-06-24 | 2026-06-27T06:11 | login_failed | No inputs found (tag=BODY) |
| /notifications | 2026-06-24 | 2026-06-27T06:11 | login_failed | No inputs found (tag=BODY) |
| /reviews | 2026-06-27 | 2026-06-27T06:11 | login_failed | No inputs found (tag=BODY) |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=99%) |
| /agenda | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=99%) |
| /patients | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /messages | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /consultation | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /ordonnances | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /waiting-room | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /ordonnances/new | 2026-06-27 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=99%) |
| /agenda | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /bookable-slots | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=99%) |
| /patients | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /appointments | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /devis | 2026-06-24 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /messages | 2026-06-27 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=100%) |
| /admin-membres | 2026-06-27 | 2026-06-27T06:11 | blank-canvas | blank-canvas (0 err, white=98%) |
