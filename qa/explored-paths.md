# QA Explored Paths

Last run: 2026-06-30T14:41:59.628Z

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
| /signup | 2026-06-30 | 2026-06-30T14:42:33.065Z | blank-canvas | blank-canvas P0 |
| /account-setup | 2026-06-30 | 2026-06-30T14:42:40.025Z | blank-canvas | blank-canvas P0 |
| /coverage-setup | 2026-06-30 | 2026-06-30T14:42:46.868Z | blank-canvas | blank-canvas P0 |
| /oubliettes | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /book | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /a2ui-demo | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /reviews | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| / | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /appointments | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /mes-rdv | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /documents | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /financial | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /profile | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /messaging | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /notifications | 2026-06-30 | 2026-06-30T14:43:43.964Z | login_failed | login_failed |
| /login | 2026-06-30 | 2026-06-30T14:42:54.080Z | blank-canvas | blank-canvas P0 |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /register-pro | 2026-06-30 | 2026-06-30T14:43:51.156Z | blank-canvas | blank-canvas P0 |
| /a2ui-demo | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| / | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| /agenda | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| /waiting-room | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| /patients | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| /messages | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| /consultation | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| /ordonnances | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| /cabinet-setup | 2026-06-30 | 2026-06-30T14:45:18.217Z | login_failed | login_failed |
| /login | 2026-06-30 | 2026-06-30T14:43:58.284Z | blank-canvas | blank-canvas P0 |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /onboard | 2026-06-30 | 2026-06-30T14:45:24.924Z | blank-canvas | blank-canvas P0 |
| /messages | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /admin-membres | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /admin-secretariats | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /a2ui-demo | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| / | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /agenda | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /appointments | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /salle-attente | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /patients | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /liste-attente | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /bookable-slots | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /devis | 2026-06-30 | 2026-06-30T14:46:21.809Z | login_failed | login_failed |
| /login | 2026-06-30 | 2026-06-30T14:45:31.950Z | blank-canvas | blank-canvas P0 |
