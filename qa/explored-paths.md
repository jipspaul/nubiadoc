# QA Explored Paths

Last run: 2026-06-30T13:29:01.525Z

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
| / | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /appointments | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /documents | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /financial | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /profile | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /messaging | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /notifications | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /reviews | 2026-06-30 | — | — | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /agenda | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /patients | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /messages | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /consultation | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| / | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /agenda | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /appointments | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /patients | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |
| /devis | 2026-06-30 | 2026-06-30T13:29:01.525Z | OK | — |

