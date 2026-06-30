# QA Explored Paths

Last run: 2026-06-30T14:53:49.741Z

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
| /signup | 2026-06-30 | 2026-06-30T14:55:01.597Z | OK | — |
| /account-setup | 2026-06-30 | 2026-06-30T14:55:12.367Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-06-30T14:55:23.005Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /book | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /a2ui-demo | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /reviews | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| / | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /appointments | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /mes-rdv | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /documents | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /financial | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /profile | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /messaging | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /notifications | 2026-06-30 | 2026-06-30T14:56:18.700Z | login_failed | login_failed |
| /login | 2026-06-30 | 2026-06-30T14:55:33.861Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /register-pro | 2026-06-30 | 2026-06-30T14:56:30.233Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| / | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| /agenda | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| /waiting-room | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| /patients | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| /messages | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| /consultation | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| /ordonnances | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| /cabinet-setup | 2026-06-30 | 2026-06-30T14:57:55.604Z | login_failed | login_failed |
| /login | 2026-06-30 | 2026-06-30T14:56:41.141Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /onboard | 2026-06-30 | 2026-06-30T14:58:06.773Z | OK | — |
| /messages | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /admin-membres | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /admin-secretariats | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /a2ui-demo | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| / | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /agenda | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /appointments | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /salle-attente | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /patients | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /liste-attente | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /bookable-slots | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /devis | 2026-06-30 | 2026-06-30T14:59:01.969Z | login_failed | login_failed |
| /login | 2026-06-30 | 2026-06-30T14:58:17.874Z | OK | — |
