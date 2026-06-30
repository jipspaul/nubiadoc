# QA Explored Paths

Last run: 2026-06-30T15:03:29.213Z

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
| /signup | 2026-06-30 | 2026-06-30T15:04:43.478Z | OK | — |
| /account-setup | 2026-06-30 | 2026-06-30T15:04:54.425Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-06-30T15:05:05.939Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-06-30T15:05:54.445Z | blank-canvas | blank-canvas P0 |
| /book | 2026-06-30 | 2026-06-30T15:05:57.044Z | blank-canvas | blank-canvas P0 |
| /a2ui-demo | 2026-06-30 | 2026-06-30T15:05:33.534Z | blank-canvas | blank-canvas P0 |
| /reviews | 2026-06-30 | 2026-06-30T15:05:49.607Z | blank-canvas | blank-canvas P0 |
| / | 2026-06-30 | 2026-06-30T15:05:31.309Z | blank-canvas | blank-canvas P0 |
| /appointments | 2026-06-30 | 2026-06-30T15:05:36.095Z | blank-canvas | blank-canvas P0 |
| /mes-rdv | 2026-06-30 | 2026-06-30T15:05:38.347Z | blank-canvas | blank-canvas P0 |
| /documents | 2026-06-30 | 2026-06-30T15:05:40.585Z | blank-canvas | blank-canvas P0 |
| /financial | 2026-06-30 | 2026-06-30T15:05:42.824Z | blank-canvas | blank-canvas P0 |
| /profile | 2026-06-30 | 2026-06-30T15:05:45.062Z | blank-canvas | blank-canvas P0 |
| /messaging | 2026-06-30 | 2026-06-30T15:05:47.312Z | blank-canvas | blank-canvas P0 |
| /notifications | 2026-06-30 | 2026-06-30T15:05:51.863Z | blank-canvas | blank-canvas P0 |
| /login | 2026-06-30 | 2026-06-30T15:05:17.160Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /register-pro | 2026-06-30 | 2026-06-30T15:06:08.234Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| / | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| /agenda | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| /waiting-room | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| /patients | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| /messages | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| /consultation | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| /ordonnances | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| /cabinet-setup | 2026-06-30 | 2026-06-30T15:07:33.273Z | login_failed | login_failed |
| /login | 2026-06-30 | 2026-06-30T15:06:19.180Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /onboard | 2026-06-30 | 2026-06-30T15:07:43.987Z | OK | — |
| /messages | 2026-06-30 | 2026-06-30T15:08:28.760Z | blank-canvas | blank-canvas P0 |
| /admin-membres | 2026-06-30 | 2026-06-30T15:08:31.327Z | blank-canvas | blank-canvas P0 |
| /admin-secretariats | 2026-06-30 | 2026-06-30T15:08:33.902Z | blank-canvas | blank-canvas P0 |
| /a2ui-demo | 2026-06-30 | 2026-06-30T15:08:14.964Z | blank-canvas | blank-canvas P0 |
| / | 2026-06-30 | 2026-06-30T15:08:08.221Z | blank-canvas | blank-canvas P0 |
| /agenda | 2026-06-30 | 2026-06-30T15:08:10.469Z | blank-canvas | blank-canvas P0 |
| /appointments | 2026-06-30 | 2026-06-30T15:08:22.034Z | blank-canvas | blank-canvas P0 |
| /salle-attente | 2026-06-30 | 2026-06-30T15:08:17.547Z | blank-canvas | blank-canvas P0 |
| /patients | 2026-06-30 | 2026-06-30T15:08:19.797Z | blank-canvas | blank-canvas P0 |
| /liste-attente | 2026-06-30 | 2026-06-30T15:08:24.277Z | blank-canvas | blank-canvas P0 |
| /bookable-slots | 2026-06-30 | 2026-06-30T15:08:12.727Z | blank-canvas | blank-canvas P0 |
| /devis | 2026-06-30 | 2026-06-30T15:08:26.523Z | blank-canvas | blank-canvas P0 |
| /login | 2026-06-30 | 2026-06-30T15:07:54.313Z | OK | — |
