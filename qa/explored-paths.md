# QA Explored Paths

Last run: 2026-06-30T23:45:17.127Z

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
| Auth routes | ALL | 2026-06-30 | Flutter HTML renderer white background = not blank | fix: skip white ratio for auth routes |
| /signup | patient | 2026-06-30 | CSS Flutter placeholder (NubiaTextField) | faux positif — ferme #3083 |


## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /signup | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /account-setup | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /book | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /reviews | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| / | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /appointments | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /documents | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /financial | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /profile | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /messaging | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /notifications | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /login | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /register-pro | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| / | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /agenda | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /patients | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /messages | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /consultation | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /login | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /ordonnances/new | 20260630 | 2026-06-30T23:45:17.127Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /onboard | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |
| /messages | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /admin-membres | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /admin-secretariats | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /a2ui-demo | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| / | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /agenda | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /appointments | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /salle-attente | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /patients | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /liste-attente | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /bookable-slots | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /devis | 2026-06-30 | 2026-06-30T23:45:17.127Z | blank-canvas | — |
| /login | 2026-06-30 | 2026-06-30T23:45:17.127Z | OK | — |

