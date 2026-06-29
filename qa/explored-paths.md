# QA Explored Paths

Last run: 2026-06-29T21:04:21.267Z

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
| /profile | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /mes-rdv | 2026-06-28 | 2026-06-29T21:04:21.267Z | OK | — |
| /documents | 2026-06-28 | 2026-06-29T19:25:04.747Z | OK | — |
| /financial | 2026-06-28 | 2026-06-29T21:04:21.267Z | OK | — |
| /reviews | 2026-06-29 | 2026-06-29T19:25:10.929Z | OK | — |
| /book | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| / | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /appointments | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /messaging | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /oubliettes | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /ordonnances | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /waiting-room | 2026-06-28 | 2026-06-29T19:25:29.496Z | OK | — |
| /consultation | 2026-06-28 | 2026-06-29T21:04:21.267Z | OK | — |
| /cabinet-setup | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| / | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /patients | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /register-pro | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /appointments | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /salle-attente | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /messages | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| /agenda | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
| / | 2026-06-28 | 2026-06-29T21:04:21.267Z | OK | — |
| /patients | 2026-06-28 | 2026-06-29T21:04:21.267Z | OK | — |
| /liste-attente | 2026-06-28 | 2026-06-29T21:04:21.267Z | OK | — |
| /admin-secretariats | 2026-06-29 | 2026-06-29T21:04:21.267Z | OK | — |
