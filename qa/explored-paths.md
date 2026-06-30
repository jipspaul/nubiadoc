# QA Explored Paths

Last run: 2026-06-30T14:31:09.813Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter placeholder | faux positif — ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter placeholder | faux positif — ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter placeholder | faux positif — ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing | faux positif — ferme #2920-#2935 |
| Login | ALL | 2026-06-30 | canvas click coords: email y=380, pw y=420, btn y=490 | fix appliqué run 13:15 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /signup | 2026-06-30 | 2026-06-30T14:31:27.084Z | blank-canvas | blank-canvas P0 |
| /account-setup | 2026-06-30 | 2026-06-30T14:31:32.443Z | blank-canvas | blank-canvas P0 |
| /coverage-setup | 2026-06-30 | 2026-06-30T14:31:37.812Z | blank-canvas | blank-canvas P0 |
| /oubliettes | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /book | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /reviews | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| / | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /appointments | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /documents | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /financial | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /profile | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /messaging | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /notifications | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /login | 2026-06-30 | 2026-06-30T14:31:21.705Z | blank-canvas | blank-canvas P0 |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /register-pro | 2026-06-30 | 2026-06-30T14:32:26.927Z | blank-canvas | blank-canvas P0 |
| /a2ui-demo | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| / | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /agenda | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /patients | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /messages | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /consultation | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /login | 2026-06-30 | 2026-06-30T14:32:21.539Z | blank-canvas | blank-canvas P0 |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /onboard | 2026-06-30 | 2026-06-30T14:33:46.153Z | blank-canvas | blank-canvas P0 |
| /messages | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| / | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /agenda | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /appointments | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /patients | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /devis | 2026-06-30 | 2026-06-30T13:30:55.061Z | OK | — |
| /login | 2026-06-30 | 2026-06-30T14:33:40.667Z | blank-canvas | blank-canvas P0 |
