# QA Explored Paths

Last run: 2026-06-30T06:43:16.927Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` | faux positif — ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | `flt-text-editing::placeholder` | faux positif — ferme #2734 |
| /agenda | praticien | 2026-06-25 | `flt-text-editing::placeholder` | faux positif — ferme #2732 |
| /notifications | patient | 2026-06-25 | résolu | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | résolu | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router hash | ferme #2920-#2935. Naviger via page.goto() avec /#/route |


## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /appointments | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /mes-rdv | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /documents | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /financial | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /profile | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /messaging | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /reviews | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /agenda | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /waiting-room | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /patients | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /messages | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /consultation | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /ordonnances | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /cabinet-setup | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /agenda | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /appointments | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /salle-attente | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /patients | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /liste-attente | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /bookable-slots | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |
| /devis | 2026-06-30 | 2026-06-30T06:43:16.927Z | blank-canvas | blank-canvas |

