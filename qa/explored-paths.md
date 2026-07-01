# QA Explored Paths

Last run: 2026-07-01T04:11:55.988Z

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
| /messages | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA (pas d'exception app) | faux positif — ferme #3136 |
| /patients/:id | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA | faux positif — ferme #3132 |
| /agenda | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA | faux positif — ferme #3134 |
| / | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA | fix: try/catch ajouté TodayNotesBloc — ferme #3133 |
| /ordonnances | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA | faux positif — ferme #3138 |
| /cabinet-setup | praticien | 2026-07-01 | page.goto: browser/context closed pendant le run QA | faux positif — ferme #3140 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T04:11:55.988Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T04:11:55.988Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T04:11:55.988Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T04:11:55.988Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T04:11:55.988Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T04:11:55.988Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T04:11:55.988Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T04:11:55.988Z | OK | — |
