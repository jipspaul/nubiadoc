# QA Explored Paths

Last run: 2026-06-30T15:16:04.039Z

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

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /signup | 2026-06-30 | 2026-06-30T15:17:17.405Z | OK | — |
| /account-setup | 2026-06-30 | 2026-06-30T15:17:27.975Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-06-30T15:17:38.606Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-06-30T15:18:26.449Z | blank-canvas | blank-canvas P0 |
| /book | 2026-06-30 | 2026-06-30T15:18:28.684Z | blank-canvas | blank-canvas P0 |
| /a2ui-demo | 2026-06-30 | 2026-06-30T15:18:05.909Z | blank-canvas | blank-canvas P0 |
| /reviews | 2026-06-30 | 2026-06-30T15:18:21.956Z | blank-canvas | blank-canvas P0 |
| / | 2026-06-30 | 2026-06-30T15:18:03.649Z | blank-canvas | blank-canvas P0 |
| /appointments | 2026-06-30 | 2026-06-30T15:18:08.191Z | blank-canvas | blank-canvas P0 |
| /mes-rdv | 2026-06-30 | 2026-06-30T15:18:10.433Z | blank-canvas | blank-canvas P0 |
| /documents | 2026-06-30 | 2026-06-30T15:18:12.899Z | blank-canvas | blank-canvas P0 |
| /financial | 2026-06-30 | 2026-06-30T15:18:15.158Z | blank-canvas | blank-canvas P0 |
| /profile | 2026-06-30 | 2026-06-30T15:18:17.425Z | blank-canvas | blank-canvas P0 |
| /messaging | 2026-06-30 | 2026-06-30T15:18:19.674Z | blank-canvas | blank-canvas P0 |
| /notifications | 2026-06-30 | 2026-06-30T15:18:24.188Z | blank-canvas | blank-canvas P0 |
| /login | 2026-06-30 | 2026-06-30T15:17:49.394Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /register-pro | 2026-06-30 | 2026-06-30T15:18:44.564Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-06-30T15:20:11.276Z | blank-canvas | blank-canvas P0 |
| / | 2026-06-30 | 2026-06-30T15:19:20.776Z | blank-canvas | blank-canvas P0 |
| /agenda | 2026-06-30 | 2026-06-30T15:19:27.989Z | blank-canvas | blank-canvas P0 |
| /waiting-room | 2026-06-30 | 2026-06-30T15:19:35.192Z | blank-canvas | blank-canvas P0 |
| /patients | 2026-06-30 | 2026-06-30T15:19:42.427Z | blank-canvas | blank-canvas P0 |
| /messages | 2026-06-30 | 2026-06-30T15:19:49.596Z | blank-canvas | blank-canvas P0 |
| /consultation | 2026-06-30 | 2026-06-30T15:19:56.858Z | blank-canvas | blank-canvas P0 |
| /ordonnances | 2026-06-30 | 2026-06-30T15:20:04.051Z | blank-canvas | blank-canvas P0 |
| /cabinet-setup | 2026-06-30 | 2026-06-30T15:20:18.874Z | blank-canvas | blank-canvas P0 |
| /login | 2026-06-30 | 2026-06-30T15:19:01.119Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /onboard | 2026-06-30 | 2026-06-30T15:20:29.382Z | OK | — |
| /messages | 2026-06-30 | 2026-06-30T15:21:13.900Z | blank-canvas | blank-canvas P0 |
| /admin-membres | 2026-06-30 | 2026-06-30T15:21:16.156Z | blank-canvas | blank-canvas P0 |
| /admin-secretariats | 2026-06-30 | 2026-06-30T15:21:18.387Z | blank-canvas | blank-canvas P0 |
| /a2ui-demo | 2026-06-30 | 2026-06-30T15:21:00.429Z | blank-canvas | blank-canvas P0 |
| / | 2026-06-30 | 2026-06-30T15:20:53.710Z | blank-canvas | blank-canvas P0 |
| /agenda | 2026-06-30 | 2026-06-30T15:20:55.943Z | blank-canvas | blank-canvas P0 |
| /appointments | 2026-06-30 | 2026-06-30T15:21:07.203Z | blank-canvas | blank-canvas P0 |
| /salle-attente | 2026-06-30 | 2026-06-30T15:21:02.695Z | blank-canvas | blank-canvas P0 |
| /patients | 2026-06-30 | 2026-06-30T15:21:04.939Z | blank-canvas | blank-canvas P0 |
| /liste-attente | 2026-06-30 | 2026-06-30T15:21:09.436Z | blank-canvas | blank-canvas P0 |
| /bookable-slots | 2026-06-30 | 2026-06-30T15:20:58.195Z | blank-canvas | blank-canvas P0 |
| /devis | 2026-06-30 | 2026-06-30T15:21:11.669Z | blank-canvas | blank-canvas P0 |
| /login | 2026-06-30 | 2026-06-30T15:20:39.815Z | OK | — |
