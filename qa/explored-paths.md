# QA Explored Paths

Last run: 2026-07-01T09:06:18.491Z

## Faux positifs connus (méthode C)

| route | app | détecté le | cause | résolution |
| --- | --- | --- | --- | --- |
| /appointments | patient | 2026-06-25 | CSS Flutter `::placeholder` | faux positif — ferme #2724 #2749 |
| /salle-attente | secretariat | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2746 |
| /profile | patient | 2026-06-25 | idem CSS Flutter | faux positif — ferme #2728 |
| /messages | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — ferme #2734 |
| /agenda | praticien | 2026-06-25 | idem CSS Flutter `flt-text-editing::placeholder` | faux positif — ferme #2732 |
| /notifications | patient | 2026-06-25 | déjà résolu | ferme #2833 |
| /ordonnances | praticien | 2026-06-25 | déjà résolu | ferme #2853 #2854 |
| [*] blank-canvas | ALL | 2026-06-27 | go_router path routing — location.hash ignoré | faux positif — ferme #2920-#2935 |

## patient

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:07:00.713Z | OK | — |
| /signup | 2026-06-30 | 2026-07-01T09:07:03.668Z | OK | — |
| /account-setup | 2026-06-30 | 2026-07-01T08:05:25.716Z | OK | — |
| /coverage-setup | 2026-06-30 | 2026-07-01T08:05:31.792Z | OK | — |
| / | 2026-06-30 | 2026-07-01T08:05:00.752Z | failed-requests | "Erreur serveur lors du chargement du tableau de bord" — #3153 |
| /a2ui-demo | 2026-06-30 | 2026-07-01T08:05:35.101Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T08:05:38.384Z | OK | — |
| /mes-rdv | 2026-06-30 | 2026-07-01T08:05:41.672Z | OK | — |
| /documents | 2026-06-30 | 2026-07-01T08:05:44.990Z | OK | — |
| /financial | 2026-06-30 | 2026-07-01T08:05:48.286Z | OK | — |
| /profile | 2026-06-30 | 2026-07-01T08:05:04.055Z | failed-requests | "Erreur serveur lors de la mise à jour du compte" — see #3038 |
| /messaging | 2026-06-30 | 2026-07-01T08:05:51.566Z | OK | — |
| /reviews | 2026-06-30 | 2026-07-01T08:05:07.374Z | failed-requests | "Erreur lors de la récupération des avis" — #3040 open |
| /notifications | 2026-06-30 | 2026-07-01T08:05:54.858Z | OK | — |
| /oubliettes | 2026-06-30 | 2026-07-01T08:05:58.149Z | OK | — |
| /rdv/test-appt-id/prepare | 2026-06-30 | 2026-07-01T08:06:01.436Z | OK | — |
| /book | 2026-06-30 | 2026-07-01T06:19:01.634Z | OK | — |

## praticien

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:07:43.386Z | OK | — |
| /register-pro | 2026-06-30 | 2026-07-01T09:07:46.253Z | OK | — |
| / | 2026-06-30 | 2026-07-01T09:07:49.169Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T09:07:52.108Z | OK | — |
| /waiting-room | 2026-06-30 | 2026-07-01T09:07:37.594Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T09:07:55.129Z | OK | — |
| /patients/test-patient-id | 2026-06-30 | 2026-07-01T09:07:58.485Z | OK | — |
| /messages | 2026-06-30 | 2026-07-01T09:08:01.435Z | OK | — |
| /consultation | 2026-06-30 | 2026-07-01T09:07:40.509Z | OK | — |
| /ordonnances | 2026-06-30 | 2026-07-01T09:08:04.363Z | OK | — |
| /ordonnances/new | 2026-06-30 | 2026-07-01T09:08:07.165Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T09:08:09.950Z | OK | — |
| /cabinet-setup | 2026-06-30 | 2026-07-01T09:08:13.411Z | OK | — |

## secretariat

| route | first_seen | last_check | last_status | last_finding |
| --- | --- | --- | --- | --- |
| --- | --- | --- | --- | --- |
| /login | 2026-06-30 | 2026-07-01T09:08:49.015Z | OK | — |
| /onboard | 2026-06-30 | 2026-07-01T09:08:52.034Z | OK | — |
| / | 2026-06-30 | 2026-07-01T08:06:40.824Z | OK | — |
| /agenda | 2026-06-30 | 2026-07-01T08:06:18.820Z | failed-requests | "Impossible de charger l'agenda" — #3050 open |
| /bookable-slots | 2026-06-30 | 2026-07-01T08:06:44.114Z | OK | — |
| /a2ui-demo | 2026-06-30 | 2026-07-01T08:06:47.399Z | OK | — |
| /salle-attente | 2026-06-30 | 2026-07-01T08:06:50.683Z | OK | — |
| /patients | 2026-06-30 | 2026-07-01T08:06:53.971Z | OK | — |
| /appointments | 2026-06-30 | 2026-07-01T08:06:57.262Z | OK | — |
| /liste-attente | 2026-06-30 | 2026-07-01T08:07:00.547Z | OK | — |
| /devis | 2026-06-30 | 2026-07-01T08:06:22.119Z | failed-requests | "Impossible de charger les devis" — #3056 open |
| /devis/test-devis-id | 2026-06-30 | 2026-07-01T08:06:25.396Z | failed-requests | "Impossible de charger les devis" — related to #3056 |
| /messages | 2026-06-30 | 2026-07-01T08:07:03.834Z | OK | — |
| /admin-membres | 2026-06-30 | 2026-07-01T08:07:07.134Z | OK | — |
| /admin-secretariats | 2026-06-30 | 2026-07-01T08:07:10.430Z | OK | — |
