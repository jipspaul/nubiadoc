# QA Explored Paths

Last run: 2026-07-01T05:40:21.956Z

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
| Login | ALL | 2026-06-30 | canvas click coords | fix appliqué |
| Auth routes | ALL | 2026-06-30 | Flutter HTML renderer white = not blank | fix applied |
| /signup | patient | 2026-06-30 | CSS placeholder | faux positif — ferme #3083 |
| /messages | praticien | 2026-07-01 | context closed during QA | faux positif — ferme #3136 |
| /patients/:id | praticien | 2026-07-01 | context closed during QA | faux positif — ferme #3132 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| / | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /messaging | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /notifications | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| / | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| / | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /bookable-slots | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T05:40:21.956Z | OK | — |
