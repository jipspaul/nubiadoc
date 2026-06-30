# QA Explored Paths

Last run: 2026-06-30T13:15:34.466Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` capté comme marker | faux positif — feature complète, ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter placeholder | faux positif — feature complète, ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter placeholder | faux positif — feature complète, ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré | faux positif — ferme #2920-#2935. Naviger via location.hash |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | — | — | — |
| /appointments | 2026-06-30 | — | — | — |
| /mes-rdv | 2026-06-30 | — | — | — |
| /documents | 2026-06-30 | — | — | — |
| /financial | 2026-06-30 | — | — | — |
| /profile | 2026-06-30 | — | — | — |
| /messaging | 2026-06-30 | — | — | — |
| /notifications | 2026-06-30 | — | — | — |
| /reviews | 2026-06-30 | — | — | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | — | — | — |
| /agenda | 2026-06-30 | — | — | — |
| /waiting-room | 2026-06-30 | — | — | — |
| /patients | 2026-06-30 | — | — | — |
| /messages | 2026-06-30 | — | — | — |
| /consultation | 2026-06-30 | — | — | — |
| /ordonnances | 2026-06-30 | — | — | — |
| /cabinet-setup | 2026-06-30 | — | — | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | — | — | — |
| /agenda | 2026-06-30 | — | — | — |
| /appointments | 2026-06-30 | — | — | — |
| /salle-attente | 2026-06-30 | — | — | — |
| /patients | 2026-06-30 | — | — | — |
| /liste-attente | 2026-06-30 | — | — | — |
| /bookable-slots | 2026-06-30 | — | — | — |
| /devis | 2026-06-30 | — | — | — |

